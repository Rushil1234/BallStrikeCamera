#!/usr/bin/env python3
"""Third-pass locator: fuzzy-match leftovers against the full US OSM golf dump.

Nominatim search (pass 1) is strict about names — "Waurika Municipal Golf
Course" won't find OSM's "Waurika Golf Course". This pass matches locally
against tools/us_golf_courses_osm.json (all 13k named US golf courses from
one Overpass query), so name variants land.

Precision rules (validated by hand on a 25-course sample — false positives
like "Lost Valley Resort"→"Hudson Valley Resort" are exactly the stolen-
geometry poison the July audit cleaned up, so this is deliberately strict):
  • every distinctive token of the catalog name must appear in the OSM name
    (generic words — golf/course/club/country/… — don't count)
  • similarity ≥ 0.5 on top of the token rule
  • nationally unique: a second candidate >~10 km away rejects the match

Input: no_match rows from geolocate_progress.jsonl, minus anything the GUI
or address passes already handled. Applies via PATCH + logs to
tools/fix_sql/located_coords.sql. Progress: osm_dump_match_progress.jsonl.

Usage:  python3 tools/osm_dump_match.py [--dry-run]
"""
import difflib, json, os, re, sys, urllib.request

SB = "https://aoxturoezgecwceudeef.supabase.co"
KEY = open(os.path.expanduser("~/Downloads/BallStrikeCamera/Config/service_role.key")).read().strip()
HERE = os.path.dirname(os.path.abspath(__file__))
DUMP = os.path.join(HERE, "artifacts/us_golf_courses_osm.json")
GEO_PROGRESS = os.path.join(HERE, "artifacts/geolocate_progress.jsonl")
OTHER_PROGRESS = [os.path.join(HERE, "artifacts/gui_locate_progress.jsonl"),
                  os.path.join(HERE, "artifacts/address_geolocate_progress.jsonl")]
MY_PROGRESS = os.path.join(HERE, "artifacts/osm_dump_match_progress.jsonl")
SQL_LOG = os.path.join(HERE, "fix_sql", "located_coords.sql")
REMAINING = os.path.join(HERE, "artifacts/still_unlocated.csv")
DRY = "--dry-run" in sys.argv

GENERIC = {"golf", "course", "club", "country", "the", "at", "of", "and", "links",
           "cc", "gc", "g", "c", "resort", "municipal", "memorial", "park", "hotel",
           "driving", "range", "executive"}

def norm(s):
    return re.sub(r"[^a-z0-9 ]", "", (s or "").lower())

def toks(s):
    return set(norm(s).split()) - GENERIC

def load_dump():
    els = json.load(open(DUMP))["elements"]
    out = []
    for e in els:
        name = e["tags"].get("name", "")
        lat = e.get("lat") or (e.get("center") or {}).get("lat")
        lon = e.get("lon") or (e.get("center") or {}).get("lon")
        if name and lat:
            out.append((name, toks(name), norm(name), lat, lon))
    return out

def match(name, osm):
    base = re.split(r"\s*~\s*", name)[0]
    nt = toks(base)
    if not nt:
        return None, "no_distinctive_tokens"
    nb = norm(base)
    cands = []
    for oname, ot, on, lat, lon in osm:
        if not nt <= ot:
            continue
        sim = difflib.SequenceMatcher(None, nb, on).ratio()
        if sim >= 0.5:
            cands.append((sim, oname, lat, lon))
    if not cands:
        return None, "no_match"
    cands.sort(reverse=True)
    best = cands[0]
    for c in cands[1:]:
        if abs(c[2] - best[2]) + abs(c[3] - best[3]) > 0.1:
            return None, "ambiguous"
    return best, "located"

def sb_patch(cid, body):
    req = urllib.request.Request(f"{SB}/rest/v1/courses?id=eq.{cid}", method="PATCH", headers={
        "apikey": KEY, "Authorization": f"Bearer {KEY}",
        "Content-Type": "application/json", "Prefer": "return=minimal",
    }, data=json.dumps(body).encode())
    urllib.request.urlopen(req, timeout=30).read()

def log_sql(stmt):
    os.makedirs(os.path.dirname(SQL_LOG), exist_ok=True)
    with open(SQL_LOG, "a") as f:
        f.write(stmt + "\n")

def main():
    osm = load_dump()
    print(f"{len(osm)} OSM golf courses loaded{' [DRY RUN]' if DRY else ''}")
    handled = set()
    for path in OTHER_PROGRESS + [MY_PROGRESS]:
        if os.path.exists(path):
            with open(path) as f:
                handled |= {json.loads(l)["id"] for l in f if l.strip()}
    pending = []
    seen = set()
    with open(GEO_PROGRESS) as f:
        for line in f:
            r = json.loads(line)
            if r.get("state_") == "no_match" and r["id"] not in handled and r["id"] not in seen:
                pending.append(r)
                seen.add(r["id"])
    print(f"{len(pending)} leftovers to match")
    counts = {}
    misses = []
    with open(MY_PROGRESS, "a") as prog:
        for c in pending:
            best, state = match(c["name"], osm)
            rec = {"id": c["id"], "name": c["name"], "city": c.get("city"),
                   "state": c.get("state"), "state_": state}
            if best:
                sim, oname, lat, lon = best
                rec.update(lat=lat, lon=lon, osm_name=oname, sim=round(sim, 2))
                if not DRY:
                    sb_patch(c["id"], {"latitude": lat, "longitude": lon})
                    log_sql(f"update public.courses set latitude={lat}, longitude={lon} "
                            f"where id='{c['id']}';  -- OSM dump: {oname} (sim {round(sim, 2)})")
            else:
                misses.append(rec)
            counts[state] = counts.get(state, 0) + 1
            prog.write(json.dumps(rec) + "\n")
    import csv
    with open(REMAINING, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["id", "name", "city", "state", "state_"])
        w.writeheader()
        w.writerows(misses)
    print(f"Done — {counts}. Unresolved worklist: {REMAINING}")

if __name__ == "__main__":
    main()
