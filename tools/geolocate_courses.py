#!/usr/bin/env python3
"""Batch-geocode US catalog courses that have no lat/lon via Nominatim (OSM).

Automated companion to locate_courses.py: OSM maps most US golf courses as
leisure=golf_course polygons, so a name+city+state search usually pins the
actual course grounds — good enough for the scraper's 3 km location check.

Acceptance (strict — wrong coords are worse than none):
  • result is class=leisure, type=golf_course (the course itself, not the town)
  • result state matches the catalog row's state (when the row has one)
  • fuzzy name similarity ≥ 0.55 against the OSM display name
Everything else lands in geolocate_remaining.csv for the interactive pass
(tools/locate_courses.py skips rows that gained coords, so just rerun it).

Applied matches PATCH Supabase immediately and append to
tools/fix_sql/located_coords.sql. Progress in geolocate_progress.jsonl
(resumable). Nominatim policy: 1 request/second, identifying User-Agent.

Usage:  python3 tools/geolocate_courses.py [--limit N] [--dry-run]
"""
import csv, difflib, json, os, re, sys, time, urllib.parse, urllib.request

SB = "https://aoxturoezgecwceudeef.supabase.co"
KEY = open(os.path.expanduser("~/Downloads/BallStrikeCamera/Config/service_role.key")).read().strip()
HERE = os.path.dirname(__file__)
PROGRESS = os.path.join(HERE, "artifacts/geolocate_progress.jsonl")
REMAINING = os.path.join(HERE, "artifacts/geolocate_remaining.csv")
SQL_LOG = os.path.join(HERE, "fix_sql", "located_coords.sql")
UA = "TrueCarry-course-locator/1.0 (noahtobias19@gmail.com)"
DRY = "--dry-run" in sys.argv
LIMIT = int(sys.argv[sys.argv.index("--limit") + 1]) if "--limit" in sys.argv else None

STATES = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
    "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "FL": "Florida", "GA": "Georgia",
    "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
    "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
    "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi",
    "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire",
    "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York", "NC": "North Carolina",
    "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania",
    "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee",
    "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
    "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming", "DC": "District of Columbia",
}

def sb_rest(path, method="GET", body=None):
    req = urllib.request.Request(SB + path, method=method, headers={
        "apikey": KEY, "Authorization": f"Bearer {KEY}",
        "Content-Type": "application/json", "Prefer": "return=minimal",
    }, data=json.dumps(body).encode() if body is not None else None)
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read()
        return json.loads(raw) if raw and method == "GET" else None

def pending_courses():
    rows, off = [], 0
    while True:
        page = sb_rest("/rest/v1/courses?select=id,name,city,state,postal_code"
                       "&country=eq.US&status=eq.active&latitude=is.null"
                       f"&order=id.asc&limit=1000&offset={off}")
        rows += page
        if len(page) < 1000:
            return rows
        off += 1000

def nominatim(q):
    url = ("https://nominatim.openstreetmap.org/search?" + urllib.parse.urlencode({
        "q": q, "format": "jsonv2", "limit": 5, "countrycodes": "us", "addressdetails": 1,
    }))
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read())
        except Exception:
            if attempt == 2:
                return []
            time.sleep(5 * (attempt + 1))

def base_name(name):
    # "Trilogy at Ocala Preserve ~ Players' Course" → facility part before "~"
    return re.split(r"\s*~\s*", name)[0].strip()

def similarity(a, b):
    norm = lambda s: re.sub(r"[^a-z0-9 ]", "", s.lower())
    return difflib.SequenceMatcher(None, norm(a), norm(b)).ratio()

def best_match(course):
    name, city, state = base_name(course["name"]), course.get("city") or "", course.get("state") or ""
    want_state = STATES.get(state.upper()) if state else None
    queries = [f"{name}, {city}, {state}" if (city or state) else name]
    if "golf" not in name.lower():
        queries.append(f"{name} Golf Course, {city}, {state}")
    for q in queries:
        candidates = []
        for hit in nominatim(q):
            if hit.get("category") != "leisure" or hit.get("type") != "golf_course":
                continue
            hit_state = (hit.get("address") or {}).get("state")
            if want_state and hit_state and hit_state != want_state:
                continue
            osm_name = hit.get("name") or hit.get("display_name", "").split(",")[0]
            sim = max(similarity(name, osm_name), similarity(course["name"], osm_name))
            candidates.append({"lat": float(hit["lat"]), "lon": float(hit["lon"]),
                               "osm_name": osm_name, "sim": round(sim, 2), "query": q})
        candidates.sort(key=lambda c: c["sim"], reverse=True)
        if candidates:
            best = candidates[0]
            # Without a catalog state to cross-check, a same-name course in another
            # state is exactly the stolen-geometry failure mode — demand a stronger
            # name match and no second plausible hit somewhere else.
            min_sim = 0.55 if want_state else 0.75
            ambiguous = (not want_state and len(candidates) > 1
                         and candidates[1]["sim"] >= best["sim"] - 0.05
                         and abs(candidates[1]["lat"] - best["lat"]) + abs(candidates[1]["lon"] - best["lon"]) > 0.05)
            if best["sim"] >= min_sim and not ambiguous:
                return best
        time.sleep(1.1)   # Nominatim: max 1 req/s
    return None

def log_sql(stmt):
    os.makedirs(os.path.dirname(SQL_LOG), exist_ok=True)
    with open(SQL_LOG, "a") as f:
        f.write(stmt + "\n")

def main():
    done = set()
    if os.path.exists(PROGRESS):
        with open(PROGRESS) as f:
            done = {json.loads(l)["id"] for l in f if l.strip()}
    rows = [r for r in pending_courses() if r["id"] not in done]
    if LIMIT:
        rows = rows[:LIMIT]
    print(f"{len(rows)} courses to geocode ({len(done)} already done){' [DRY RUN]' if DRY else ''}")
    located = 0
    with open(PROGRESS, "a") as prog:
        for n, c in enumerate(rows, 1):
            m = best_match(c)
            rec = {"id": c["id"], "name": c["name"], "city": c.get("city"), "state": c.get("state")}
            if m:
                rec.update(state_="located", **m)
                rec["state_"] = "located"
                if not DRY:
                    sb_rest(f"/rest/v1/courses?id=eq.{c['id']}", method="PATCH",
                            body={"latitude": m["lat"], "longitude": m["lon"]})
                    log_sql(f"update public.courses set latitude={m['lat']}, longitude={m['lon']} "
                            f"where id='{c['id']}';  -- OSM: {m['osm_name']} (sim {m['sim']})")
                located += 1
            else:
                rec["state_"] = "no_match"
            prog.write(json.dumps(rec) + "\n")
            prog.flush()
            if n % 50 == 0:
                print(f"{n}/{len(rows)} — {located} located")
            time.sleep(1.1)
    # Remaining worklist for the interactive pass.
    with open(PROGRESS) as f:
        recs = [json.loads(l) for l in f if l.strip()]
    misses = [r for r in recs if r["state_"] == "no_match"]
    with open(REMAINING, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["id", "name", "city", "state"])
        w.writeheader()
        w.writerows([{k: r.get(k) for k in ("id", "name", "city", "state")} for r in misses])
    print(f"Done. {located} located this run; "
          f"{len(misses)} unresolved → {REMAINING} (use tools/locate_courses.py for those).")

if __name__ == "__main__":
    main()
