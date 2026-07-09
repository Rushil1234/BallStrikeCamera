#!/usr/bin/env python3
"""Exhaustive audit of course-geometry blobs vs the catalog.

Flags the corruption classes found by hand (Knoll East, Cozy Acres):
  MISMATCH  — blob's tee-coordinate centroid > 3 km from the catalog row's lat/lon
  DUPLICATE — two different course ids whose hole coordinates are (nearly) identical
  NO_COORDS — catalog row has no lat/lon to check against

Usage:  python3 tools/course_audit.py            (resumable; writes audit_report.csv + audit_progress.jsonl)
"""
import csv, gzip, io, json, math, os, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor

SB = "https://aoxturoezgecwceudeef.supabase.co"
KEY = open(os.path.expanduser("~/Downloads/BallStrikeCamera/Config/service_role.key")).read().strip()
OUT = os.path.join(os.path.dirname(__file__), "artifacts/audit_report.csv")
PROGRESS = os.path.join(os.path.dirname(__file__), "artifacts/audit_progress.jsonl")

def rest(path, tries=5):
    for attempt in range(tries):
        try:
            req = urllib.request.Request(SB + path, headers={"apikey": KEY, "Authorization": f"Bearer {KEY}"})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read())
        except Exception:
            if attempt == tries - 1:
                raise
            import time as _t; _t.sleep(2 * (attempt + 1))

def load_catalog():
    rows, off = {}, 0
    while True:
        page = rest(f"/rest/v1/courses?select=id,name,city,state,latitude,longitude,data_tier&limit=1000&offset={off}")
        for r in page:
            rows[r["id"]] = r
        if len(page) < 1000:
            return rows
        off += 1000

def fetch_blob(cid):
    url = f"{SB}/storage/v1/object/public/course-geometry/{cid}.json.gz"
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            raw = r.read()
        data = gzip.decompress(raw) if raw[:2] == b"\x1f\x8b" else raw
        return json.loads(data)
    except Exception:
        return None

def km(lat1, lon1, lat2, lon2):
    dlat = (lat2 - lat1) * 111.32
    dlon = (lon2 - lon1) * 111.32 * math.cos(math.radians((lat1 + lat2) / 2))
    return math.hypot(dlat, dlon)

def analyze(cid, cat, done):
    if cid in done:
        return done[cid]
    d = fetch_blob(cid)
    if d is None:
        rec = {"id": cid, "status": "FETCH_FAIL"}
    else:
        holes = d.get("holes") or []
        tees = [h.get("tee_coordinate") or h.get("teeCoordinate") for h in holes]
        tees = [t for t in tees if t]
        if not tees:
            rec = {"id": cid, "status": "NO_GEOMETRY"}
        else:
            clat = sum(t["latitude"] for t in tees) / len(tees)
            clon = sum(t["longitude"] for t in tees) / len(tees)
            # coordinate fingerprint for duplicate detection (~11 m resolution)
            fp = hash(tuple(sorted((round(t["latitude"], 4), round(t["longitude"], 4)) for t in tees)))
            row = cat.get(cid) or {}
            lat, lon = row.get("latitude"), row.get("longitude")
            if lat is None or lon is None:
                status, dist = "NO_COORDS", ""
            else:
                dist = km(clat, clon, lat, lon)
                status = "MISMATCH" if dist > 3 else "OK"
            rec = {"id": cid, "status": status, "dist_km": round(dist, 1) if dist != "" else "",
                   "blob_name": d.get("name", ""), "cat_name": row.get("name", ""),
                   "cat_state": row.get("state", ""), "fp": fp,
                   "centroid": f"{clat:.4f},{clon:.4f}"}
    with open(PROGRESS, "a") as f:
        f.write(json.dumps(rec) + "\n")
    return rec

def main():
    cat = load_catalog()
    print(f"catalog rows: {len(cat)}", flush=True)
    names = rest("/rest/v1/rpc/") if False else None  # placeholder
    # blob ids = storage object names (from catalog ids that are gps_ready + any known blob)
    ids = [cid for cid, r in cat.items() if r.get("data_tier") == "gps_ready"]
    print(f"gps_ready blobs to audit: {len(ids)}", flush=True)
    done = {}
    if os.path.exists(PROGRESS):
        for line in open(PROGRESS):
            try:
                r = json.loads(line)
                done[r["id"]] = r
            except Exception:
                pass
        print(f"resuming — {len(done)} already done", flush=True)
    results = []
    with ThreadPoolExecutor(max_workers=24) as ex:
        for i, rec in enumerate(ex.map(lambda c: analyze(c, cat, done), ids)):
            results.append(rec)
            if i % 1000 == 0:
                print(f"{i}/{len(ids)}", flush=True)
    # duplicate detection by fingerprint
    byfp = {}
    for r in results:
        fp = r.get("fp")
        if fp:
            byfp.setdefault(fp, []).append(r["id"])
    dup_ids = {cid for ids2 in byfp.values() if len(ids2) > 1 for cid in ids2}
    with open(OUT, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["id", "status", "dist_km", "blob_name", "cat_name", "cat_state", "centroid", "duplicate_of"])
        for r in results:
            status = r["status"]
            dup = ""
            if r["id"] in dup_ids:
                fp = r.get("fp")
                others = [x for x in byfp.get(fp, []) if x != r["id"]]
                dup = "|".join(others[:4])
                if status == "OK":
                    status = "DUPLICATE"
            if status in ("OK",):
                continue
            w.writerow([r["id"], status, r.get("dist_km", ""), r.get("blob_name", ""),
                        r.get("cat_name", ""), r.get("cat_state", ""), r.get("centroid", ""), dup])
    bad = sum(1 for r in results if r["status"] != "OK" or r["id"] in dup_ids)
    print(f"DONE. flagged {bad} of {len(results)} — report: {OUT}", flush=True)

if __name__ == "__main__":
    main()
