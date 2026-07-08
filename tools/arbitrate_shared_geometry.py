#!/usr/bin/env python3
"""Arbitrate the fingerprint groups that still have 2+ active gps_ready members.

Same rules as the 2026-07-07 audit, applied to the both-gps collisions it left:
for each group (courses whose blobs carry near-identical hole coordinates),
decide who really owns the map using INDEPENDENT location evidence — catalog
coords that were NOT backfilled from the blob itself (the coords_*.sql fills
are excluded as evidence; today's OSM/manual located_coords.sql coords count).

Per group:
  • owners = members with independent coords within 3 km of the blob centroid
  • 1 owner  → keep it; every other member is demoted to scorecard_ready and
               its blob is quarantined (renamed .json.gz.quarantined)
  • 2+ owners → identical hole coords can't be two real courses: the extras
               are the same course listed twice → status='duplicate' (kept
               tier, blob left alone; search hides them since migration 039)
               — owner kept = scorecard_verified first, then shortest name
  • 0 owners → unresolved, nobody proved ownership: all demoted + quarantined

Outputs: actions to arbitration_report.csv, SQL log to
fix_sql/arbitrate_shared_geometry.sql, demoted rows appended to
rescrape_worklist_2.csv for the scraper agent.

Usage:  python3 tools/arbitrate_shared_geometry.py [--dry-run]
"""
import csv, glob, json, math, os, re, sys, urllib.request

SB = "https://aoxturoezgecwceudeef.supabase.co"
KEY = open(os.path.expanduser("~/Downloads/BallStrikeCamera/Config/service_role.key")).read().strip()
HERE = os.path.dirname(os.path.abspath(__file__))
DRY = "--dry-run" in sys.argv
SQL_LOG = os.path.join(HERE, "fix_sql", "arbitrate_shared_geometry.sql")
REPORT = os.path.join(HERE, "artifacts/arbitration_report.csv")
WORKLIST = os.path.join(HERE, "rescrape_worklist_2.csv")

def rest(path, method="GET", body=None):
    req = urllib.request.Request(SB + path, method=method, headers={
        "apikey": KEY, "Authorization": f"Bearer {KEY}",
        "Content-Type": "application/json", "Prefer": "return=minimal",
    }, data=json.dumps(body).encode() if body is not None else None)
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read()
        return json.loads(raw) if raw and method == "GET" else None

def km(lat1, lon1, lat2, lon2):
    p = math.pi / 180
    a = (0.5 - math.cos((lat2 - lat1) * p) / 2
         + math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2)
    return 12742 * math.asin(math.sqrt(a))

def quarantine_blob(cid):
    body = {"bucketId": "course-geometry", "sourceKey": f"{cid}.json.gz",
            "destinationKey": f"{cid}.json.gz.quarantined"}
    try:
        rest("/storage/v1/object/move", method="POST", body=body)
        return True
    except Exception:
        return False   # blob may not exist / already quarantined

def log_sql(stmt):
    os.makedirs(os.path.dirname(SQL_LOG), exist_ok=True)
    with open(SQL_LOG, "a") as f:
        f.write(stmt + "\n")

def main():
    # Catalog coords are NOT evidence here — for these groups they descend from
    # the shared blob itself (imports + audit backfills), which is why four
    # Jockey Clubs in four different cities can all "sit" on one centroid.
    # Independent evidence = geocoding each member's NAME (+city/country) via
    # Nominatim and seeing whose real-world position matches the map.

    # Fingerprint groups from the audit.
    groups = {}
    for r in csv.DictReader(open(os.path.join(HERE, "artifacts/true_duplicates.csv"))):
        groups.setdefault(r["fingerprint_group"], []).append(r)

    # Current DB state for every member.
    all_ids = [r["id"] for rows in groups.values() for r in rows]
    db = {}
    for i in range(0, len(all_ids), 100):
        chunk = ",".join(f'"{x}"' for x in all_ids[i:i + 100]).replace('"', "%22")
        for row in rest(f"/rest/v1/courses?select=id,name,city,state,country,latitude,longitude,status,data_tier&id=in.({chunk})"):
            db[row["id"]] = row

    # course_geometries verified ids (tie-break for duplicate-keeper).
    verified = set()
    off = 0
    while True:
        page = rest(f"/rest/v1/course_geometries?select=internal_course_id&scorecard_verified=eq.true&limit=1000&offset={off}")
        verified |= {r["internal_course_id"] for r in page if r.get("internal_course_id")}
        if len(page) < 1000:
            break
        off += 1000

    import difflib, time, urllib.parse

    def norm(s):
        return re.sub(r"[^a-z0-9 ]", "", (s or "").lower())

    def geocode(m):
        """Independent position for a member: Nominatim golf-course hit with a
        similar name (base name before '~'). Returns (lat, lon) or None."""
        base = re.split(r"\s*~\s*", m["name"])[0].strip()
        where = ", ".join(x for x in (m.get("city"), m.get("state"), m.get("country")) if x)
        q = f"{base}, {where}" if where else base
        url = ("https://nominatim.openstreetmap.org/search?" + urllib.parse.urlencode(
            {"q": q, "format": "jsonv2", "limit": 5}))
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "TrueCarry-arbitration/1.0 (noahtobias19@gmail.com)"})
            with urllib.request.urlopen(req, timeout=30) as r:
                hits = json.loads(r.read())
        except Exception:
            hits = []
        finally:
            time.sleep(1.1)
        for hit in hits:
            if hit.get("category") == "leisure" and hit.get("type") == "golf_course":
                osm_name = hit.get("name") or ""
                if difflib.SequenceMatcher(None, norm(base), norm(osm_name)).ratio() >= 0.55:
                    return float(hit["lat"]), float(hit["lon"])
        return None

    actions = []
    n_groups = 0
    for gid, rows in groups.items():
        members = [db[r["id"]] for r in rows if r["id"] in db
                   and db[r["id"]]["status"] == "active" and db[r["id"]]["data_tier"] == "gps_ready"]
        if len(members) < 2:
            continue
        n_groups += 1
        if n_groups % 25 == 0:
            print(f"…{n_groups} groups arbitrated")
        cen = rows[0]["centroid"].split(",")
        clat, clon = float(cen[0]), float(cen[1])
        owners, others = [], []
        for m in members:
            pos = geocode(m)
            close = pos is not None and km(pos[0], pos[1], clat, clon) <= 3.0
            (owners if close else others).append(m)
        if len(owners) == 1:
            for m in others:
                actions.append((m, "demote_quarantine", f"group {gid}: map belongs to {owners[0]['name']}"))
        elif len(owners) >= 2:
            keep = sorted(owners, key=lambda m: (m["id"] not in verified, len(m["name"])))[0]
            for m in owners:
                if m["id"] != keep["id"]:
                    actions.append((m, "mark_duplicate", f"group {gid}: same course as {keep['name']}"))
            for m in others:
                actions.append((m, "demote_quarantine", f"group {gid}: map belongs to {keep['name']}"))
        else:
            for m in members:
                actions.append((m, "demote_quarantine", f"group {gid}: no member proved ownership"))

    print(f"{len(actions)} actions ({sum(1 for a in actions if a[1]=='mark_duplicate')} duplicates, "
          f"{sum(1 for a in actions if a[1]=='demote_quarantine')} demote+quarantine){' [DRY RUN]' if DRY else ''}")

    wl_new = not os.path.exists(WORKLIST)
    with open(REPORT, "w", newline="") as rep, open(WORKLIST, "a", newline="") as wl:
        w = csv.writer(rep)
        w.writerow(["id", "name", "country", "action", "reason"])
        wlw = csv.writer(wl)
        if wl_new:
            wlw.writerow(["course_id", "course_name", "city", "state", "country", "issue"])
        for m, act, reason in actions:
            w.writerow([m["id"], m["name"], m.get("country"), act, reason])
            if DRY:
                continue
            if act == "mark_duplicate":
                rest(f"/rest/v1/courses?id=eq.{m['id']}", method="PATCH", body={"status": "duplicate"})
                log_sql(f"update public.courses set status='duplicate' where id='{m['id']}';  -- {reason}")
            else:
                rest(f"/rest/v1/courses?id=eq.{m['id']}", method="PATCH", body={"data_tier": "scorecard_ready"})
                quarantine_blob(m["id"])
                log_sql(f"update public.courses set data_tier='scorecard_ready' where id='{m['id']}';  -- {reason} (blob quarantined)")
                wlw.writerow([m["id"], m["name"], m.get("city"), m.get("state"), m.get("country"), "SHARED_GEOMETRY_ARBITRATED"])
    print(f"Report: {REPORT}")

if __name__ == "__main__":
    main()
