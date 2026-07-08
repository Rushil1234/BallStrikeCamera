#!/usr/bin/env python3
"""Builds the re-scrape worklist for courses demoted in the 2026-07-07 audit.

Output: tools/rescrape_worklist.csv — one row per demoted course, with the diagnosis,
whose geometry it was actually wearing (the course we HAVE), and what we NEED.
Also writes tools/fix_sql/remove_fakes.sql (NOT executed) for suspect-phantom listings.
"""
import csv, json, math, os, re, urllib.request

SB  = "https://aoxturoezgecwceudeef.supabase.co"
KEY = open(os.path.expanduser("~/Downloads/BallStrikeCamera/Config/service_role.key")).read().strip()
HERE = os.path.dirname(__file__)

def rest(path):
    req = urllib.request.Request(SB + path, headers={"apikey": KEY, "Authorization": f"Bearer {KEY}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())

def km(a, b):
    dlat = (b[0] - a[0]) * 111.32
    dlon = (b[1] - a[1]) * 111.32 * math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot(dlat, dlon)

def club(name):
    return re.sub(r"[^a-z0-9]", "", (name or "").split("~")[0].lower())

# ── load audit + catalog ──
recs = {}
for line in open(os.path.join(HERE, "artifacts/audit_progress.jsonl")):
    try:
        r = json.loads(line); recs[r["id"]] = r
    except Exception:
        pass

cat, off = {}, 0
while True:
    page = rest(f"/rest/v1/courses?select=id,name,city,state,country,latitude,longitude,data_tier&limit=1000&offset={off}")
    for r in page:
        cat[r["id"]] = r
    if len(page) < 1000:
        break
    off += 1000

quarantined = set(json.load(open(os.path.join(HERE, "quarantined_ids.json"))))

# fingerprint groups → keeper (OK-status member = catalog coords matched geometry pre-fix)
byfp = {}
for r in recs.values():
    if r.get("fp"):
        byfp.setdefault(r["fp"], []).append(r)

rows, fakes = [], []
for cid in sorted(quarantined):
    a = recs.get(cid, {})
    c = cat.get(cid, {})
    centroid = a.get("centroid", "")
    cen = tuple(map(float, centroid.split(","))) if centroid else None

    keeper_id, keeper_name = "", ""
    group = byfp.get(a.get("fp"), [])
    keepers = [g for g in group if g["id"] != cid and g.get("status") == "OK"]
    if keepers:
        keeper_id = keepers[0]["id"]
        keeper_name = (cat.get(keeper_id) or {}).get("name", keepers[0].get("cat_name", ""))
        issue = "STOLEN_GEOMETRY"
    elif a.get("status") == "MISMATCH":
        issue = "WRONG_LOCATION_MERGE"
        # probable true owner of the geometry: nearest catalog course to the blob centroid
        if cen:
            best = None
            for o in cat.values():
                if o["id"] == cid or o.get("latitude") is None:
                    continue
                d = km(cen, (o["latitude"], o["longitude"]))
                if d < 5 and (best is None or d < best[0]):
                    best = (d, o)
            if best:
                keeper_id, keeper_name = best[1]["id"], best[1]["name"]
    else:
        issue = "SHARED_GEOMETRY_UNRESOLVED"   # duplicate group with no provable owner

    # phantom-listing suspicion: this course's only known location IS the stolen geometry
    # (its catalog coords came from the audit's centroid fill), or it sits on the keeper's
    # property. Cozy Acres pattern.
    suspect = False
    if a.get("status") == "NO_COORDS":
        suspect = True     # coords were filled FROM the stolen blob — no independent location
    elif cen and c.get("latitude") is not None and keeper_id:
        ko = cat.get(keeper_id)
        if ko and ko.get("latitude") is not None:
            suspect = km((c["latitude"], c["longitude"]), (ko["latitude"], ko["longitude"])) < 2

    rows.append({
        "course_id": cid,
        "course_name": c.get("name", a.get("cat_name", "")),
        "city": c.get("city") or "", "state": c.get("state") or "", "country": c.get("country") or "",
        "catalog_lat": c.get("latitude"), "catalog_lon": c.get("longitude"),
        "issue": issue,
        "geometry_belongs_to_id": keeper_id,
        "geometry_belongs_to_name": keeper_name,
        "wrong_geometry_centroid": centroid,
        "dist_catalog_to_geometry_km": a.get("dist_km", ""),
        "suspect_phantom": suspect,
        "quarantined_blob": f"{cid}.json.gz.quarantined",
    })
    if suspect:
        fakes.append(cid)

out = os.path.join(HERE, "rescrape_worklist.csv")
with open(out, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)

os.makedirs(os.path.join(HERE, "fix_sql"), exist_ok=True)
with open(os.path.join(HERE, "fix_sql", "remove_fakes.sql"), "w") as f:
    f.write("-- REVIEW BEFORE RUNNING: marks suspect phantom listings inactive (reversible).\n")
    for ci in range(0, len(fakes), 500):
        chunk = ",".join(f"'{i}'" for i in fakes[ci:ci+500])
        f.write(f"update public.courses set status='inactive' where id in ({chunk});\n")

from collections import Counter
print("rows:", len(rows), dict(Counter(r["issue"] for r in rows)),
      "| suspect_phantom:", len(fakes), f"| csv: {out}")
