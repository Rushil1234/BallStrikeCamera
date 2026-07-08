#!/usr/bin/env python3
"""Second-pass locator: GolfCourseAPI address → geocode.maps.co coordinates.

Takes the courses the OSM batch (geolocate_courses.py) could NOT resolve
(no golf_course object in OSM), finds each one's street address via
GolfCourseAPI name search, geocodes the address with geocode.maps.co, and
cross-checks the result against GolfCourseAPI's own lat/lon when present —
two independent sources must agree before anything is written.

Acceptance:
  • GolfCourseAPI name match: similarity ≥ 0.60, and state must agree with
    the catalog row's state when both exist
  • coords: maps.co(address) within ~7 km of GolfCourseAPI's lat/lon → accept
    maps.co; no GolfCourseAPI coords → need similarity ≥ 0.75; no maps.co
    hit → fall back to GolfCourseAPI coords at similarity ≥ 0.75

Tails geolocate_progress.jsonl live (safe to run while the OSM batch is
still going; exits ~5 min after the stream goes quiet). Skips anything the
GUI/manual pass already handled. Applies via PATCH + logs to
tools/fix_sql/located_coords.sql. Progress: address_geolocate_progress.jsonl.

Usage:  python3 tools/address_geolocate.py [--dry-run]
"""
import difflib, json, os, re, sys, time, urllib.parse, urllib.request

SB = "https://aoxturoezgecwceudeef.supabase.co"
KEY = open(os.path.expanduser("~/Downloads/BallStrikeCamera/Config/service_role.key")).read().strip()
HERE = os.path.dirname(os.path.abspath(__file__))
GEO_PROGRESS = os.path.join(HERE, "artifacts/geolocate_progress.jsonl")
GUI_PROGRESS = os.path.join(HERE, "artifacts/gui_locate_progress.jsonl")
MY_PROGRESS = os.path.join(HERE, "artifacts/address_geolocate_progress.jsonl")
SQL_LOG = os.path.join(HERE, "fix_sql", "located_coords.sql")
DRY = "--dry-run" in sys.argv

MAPSCO_KEY = "6a4e486d0668f414082429cvaa69492"
GC_KEY = re.search(r'GC_KEY = "([^"]+)"',
                   open(os.path.join(HERE, "golfcourseapi_backfill.py")).read()).group(1)

def http_json(url, headers=None, tries=3, backoff=3):
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers=headers or {})
            with urllib.request.urlopen(req, timeout=45) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(backoff * (attempt + 2))
                continue
            if attempt == tries - 1:
                return None
            time.sleep(backoff)
        except Exception:
            if attempt == tries - 1:
                return None
            time.sleep(backoff)

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

def similarity(a, b):
    norm = lambda s: re.sub(r"[^a-z0-9 ]", "", (s or "").lower())
    return difflib.SequenceMatcher(None, norm(a), norm(b)).ratio()

def base_name(name):
    return re.split(r"\s*~\s*", name)[0].strip()

def gc_best_match(course):
    """GolfCourseAPI search → best (address, gc_lat, gc_lon, sim, matched_name)."""
    name = base_name(course["name"])
    d = http_json("https://api.golfcourseapi.com/v1/search?search_query=" + urllib.parse.quote(name),
                  headers={"Authorization": f"Key {GC_KEY}"})
    best = None
    for hit in (d or {}).get("courses", []):
        loc = hit.get("location") or {}
        if (loc.get("country") or "United States") not in ("United States", "USA", "US"):
            continue
        want_state = (course.get("state") or "").upper()
        if want_state and (loc.get("state") or "").upper() not in ("", want_state):
            continue
        sim = max(similarity(name, hit.get("club_name")),
                  similarity(name, hit.get("course_name")),
                  similarity(course["name"], hit.get("course_name")))
        if sim < 0.60:
            continue
        if best is None or sim > best["sim"]:
            best = {"sim": round(sim, 2),
                    "matched": hit.get("club_name") or hit.get("course_name"),
                    "address": loc.get("address"),
                    "gc_lat": loc.get("latitude"), "gc_lon": loc.get("longitude")}
    return best

def mapsco_geocode(address):
    d = http_json("https://geocode.maps.co/search?q=" + urllib.parse.quote(address)
                  + "&api_key=" + MAPSCO_KEY)
    time.sleep(0.25)   # 5 req/s cap
    if d:
        try:
            return float(d[0]["lat"]), float(d[0]["lon"])
        except (KeyError, ValueError, IndexError):
            pass
    return None

def handled_ids():
    ids = set()
    for path in (GUI_PROGRESS, MY_PROGRESS):
        if os.path.exists(path):
            with open(path) as f:
                ids |= {json.loads(l)["id"] for l in f if l.strip()}
    return ids

def no_match_stream():
    done = handled_ids()
    offset, quiet = 0, 0
    while True:
        new = []
        if os.path.exists(GEO_PROGRESS):
            with open(GEO_PROGRESS) as f:
                f.seek(offset)
                chunk = f.read()
                offset = f.tell()
            for line in chunk.splitlines():
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if r.get("state_") == "no_match" and r["id"] not in done:
                    new.append(r)
        if new:
            quiet = 0
            yield from new
        else:
            quiet += 1
            if quiet > 60:      # ~5 min silent → OSM batch is done
                return
            time.sleep(5)

def resolve(course):
    gc = gc_best_match(course)
    if not gc:
        return {"state_": "no_gc_match"}
    if not gc["address"] and gc["gc_lat"] is None:
        return {"state_": "gc_no_location", "matched": gc["matched"]}
    mc = mapsco_geocode(gc["address"]) if gc["address"] else None
    if mc and gc["gc_lat"] is not None:
        # Two independent sources must agree (~7 km).
        if abs(mc[0] - gc["gc_lat"]) + abs(mc[1] - gc["gc_lon"]) <= 0.07:
            return {"state_": "located", "lat": mc[0], "lon": mc[1],
                    "src": "mapsco+gc_agree", **gc}
        return {"state_": "sources_disagree", **gc,
                "mapsco": {"lat": mc[0], "lon": mc[1]}}
    if mc and gc["sim"] >= 0.75:
        return {"state_": "located", "lat": mc[0], "lon": mc[1], "src": "mapsco_only", **gc}
    if gc["gc_lat"] is not None and gc["sim"] >= 0.75:
        return {"state_": "located", "lat": gc["gc_lat"], "lon": gc["gc_lon"],
                "src": "gc_only", **gc}
    return {"state_": "low_confidence", **gc}

def main():
    print(f"Address pass over OSM-batch leftovers{' [DRY RUN]' if DRY else ''}")
    counts = {}
    with open(MY_PROGRESS, "a") as prog:
        for n, c in enumerate(no_match_stream(), 1):
            res = resolve(c)
            res.update(id=c["id"], name=c["name"], city=c.get("city"), state=c.get("state"))
            if res["state_"] == "located":
                lat, lon = res["lat"], res["lon"]
                if not (18 <= lat <= 72 and -180 <= lon <= -66):
                    res["state_"] = "out_of_bounds"
                elif not DRY:
                    sb_patch(c["id"], {"latitude": lat, "longitude": lon})
                    log_sql(f"update public.courses set latitude={lat}, longitude={lon} "
                            f"where id='{c['id']}';  -- {res['src']}: {res['matched']} (sim {res['sim']})")
            counts[res["state_"]] = counts.get(res["state_"], 0) + 1
            prog.write(json.dumps(res) + "\n")
            prog.flush()
            if n % 50 == 0:
                print(f"{n} processed — {counts}")
            time.sleep(0.3)   # be gentle to GolfCourseAPI
    print(f"Done — {counts}")

if __name__ == "__main__":
    main()
