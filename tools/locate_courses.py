#!/usr/bin/env python3
"""Interactive locator for US catalog courses that have no lat/lon.

(The 2026-07-07 audit already fixed every gps_ready course's location via
tools/fix_sql/coords_*.sql — what's left is the unmapped tail: 1,100+ US
courses with neither geometry nor coordinates.)

For each course this opens a Google Maps search in your browser; you paste
"lat, lon" (right-click the spot in Maps → copy coordinates), or:
    <enter> / s   skip for now
    g             mark gone (status='closed' — not a real/open course)
    q             quit (progress is saved per-answer; rerun to resume)

Each answer is applied to Supabase immediately (service key) AND appended to
tools/fix_sql/located_coords.sql as the durable record. Courses that gain a
location become scrapeable again: re-run tools/build_rescrape_worklist.py to
feed them to the geometry scraper with a real position to verify against.

Usage:
    python3 tools/locate_courses.py                 # interactive session
    python3 tools/locate_courses.py --worklist out.csv   # just export the tail
"""
import csv, json, os, re, sys, urllib.parse, urllib.request, webbrowser

SB = "https://aoxturoezgecwceudeef.supabase.co"
KEY = open(os.path.expanduser("~/Downloads/BallStrikeCamera/Config/service_role.key")).read().strip()
HERE = os.path.dirname(__file__)
SQL_LOG = os.path.join(HERE, "fix_sql", "located_coords.sql")

def rest(path, method="GET", body=None):
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
        page = rest("/rest/v1/courses?select=id,name,city,state,postal_code,website,hole_count"
                    "&country=eq.US&status=eq.active&latitude=is.null"
                    f"&order=state.asc,name.asc&limit=1000&offset={off}")
        rows += page
        if len(page) < 1000:
            return rows
        off += 1000

def log_sql(stmt):
    os.makedirs(os.path.dirname(SQL_LOG), exist_ok=True)
    with open(SQL_LOG, "a") as f:
        f.write(stmt + "\n")

def set_coords(cid, lat, lon):
    rest(f"/rest/v1/courses?id=eq.{cid}", method="PATCH", body={"latitude": lat, "longitude": lon})
    log_sql(f"update public.courses set latitude={lat}, longitude={lon} where id='{cid}';")

def mark_gone(cid):
    rest(f"/rest/v1/courses?id=eq.{cid}", method="PATCH", body={"status": "closed"})
    log_sql(f"update public.courses set status='closed' where id='{cid}';  -- verified gone")

COORD_RE = re.compile(r"^\s*(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)\s*$")

def main():
    if "--worklist" in sys.argv:
        out = sys.argv[sys.argv.index("--worklist") + 1]
        rows = pending_courses()
        with open(out, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=["id", "name", "city", "state", "postal_code", "website", "hole_count"])
            w.writeheader()
            w.writerows(rows)
        print(f"{len(rows)} US courses without coordinates → {out}")
        return

    rows = pending_courses()
    print(f"{len(rows)} US courses need locations. Paste 'lat, lon', or s(kip)/g(one)/q(uit).\n")
    done = 0
    for c in rows:
        where = ", ".join(x for x in (c.get("city"), c.get("state"), c.get("postal_code")) if x)
        query = urllib.parse.quote_plus(f"{c['name']} golf {where}")
        print(f"— {c['name']}  [{where or 'no city/state'}]  holes={c.get('hole_count')}  {c.get('website') or ''}")
        webbrowser.open(f"https://www.google.com/maps/search/{query}")
        while True:
            ans = input("  lat, lon > ").strip().lower()
            if ans in ("q", "quit"):
                print(f"\nStopped. {done} located this session. Rerun to continue.")
                return
            if ans in ("", "s", "skip"):
                break
            if ans in ("g", "gone"):
                mark_gone(c["id"])
                print("  → marked closed")
                done += 1
                break
            m = COORD_RE.match(ans)
            if m:
                lat, lon = float(m.group(1)), float(m.group(2))
                if 18 <= lat <= 72 and -180 <= lon <= -66:   # US incl. AK/HI sanity box
                    set_coords(c["id"], lat, lon)
                    print(f"  → saved {lat}, {lon}")
                    done += 1
                    break
                print("  outside US bounds — try again")
            else:
                print("  couldn't parse — paste like: 41.0564, -74.6463")
    print(f"\nAll done — {done} updated.")

if __name__ == "__main__":
    main()
