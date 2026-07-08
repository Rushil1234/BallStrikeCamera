#!/usr/bin/env python3
"""Read-only completeness audit of every gps_ready course's geometry blob.

Records, per course: hole count, holes with tee/green coordinates, holes with
handicap and par, tee-box count and how many carry total yards / rating /
slope, and whether green/fairway polygons exist. Output feeds the
"how done is gps_ready really" ladder. Resumable; ~12 workers.

Usage:  python3 tools/blob_completeness_audit.py
"""
import gzip, json, os, urllib.request
from concurrent.futures import ThreadPoolExecutor

SB = "https://aoxturoezgecwceudeef.supabase.co"
KEY = open(os.path.expanduser("~/Downloads/BallStrikeCamera/Config/service_role.key")).read().strip()
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "artifacts/blob_completeness.jsonl")

def rest(path, tries=4):
    for attempt in range(tries):
        try:
            req = urllib.request.Request(SB + path, headers={"apikey": KEY, "Authorization": f"Bearer {KEY}"})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read())
        except Exception:
            if attempt == tries - 1:
                raise
            import time; time.sleep(2 * (attempt + 1))

def gps_ready_ids():
    ids, off = [], 0
    while True:
        page = rest(f"/rest/v1/courses?select=id&data_tier=eq.gps_ready&status=eq.active&order=id.asc&limit=1000&offset={off}")
        ids += [r["id"] for r in page]
        if len(page) < 1000:
            return ids
        off += 1000

def audit(cid):
    try:
        url = f"{SB}/storage/v1/object/public/course-geometry/{cid}.json.gz"
        with urllib.request.urlopen(urllib.request.Request(url), timeout=60) as r:
            doc = json.loads(gzip.decompress(r.read()))
        holes = doc.get("holes") or []
        tees = doc.get("tee_boxes") or doc.get("teeBoxes") or []
        def hv(h, *keys):
            for k in keys:
                if h.get(k) is not None:
                    return True
            return False
        return {
            "id": cid, "state": "ok",
            "holes": len(holes),
            "h_tee":   sum(1 for h in holes if hv(h, "tee_coordinate", "teeCoordinate")),
            "h_green": sum(1 for h in holes if hv(h, "green_center_coordinate", "greenCenterCoordinate")),
            "h_hcp":   sum(1 for h in holes if hv(h, "handicap")),
            "h_par":   sum(1 for h in holes if h.get("par")),
            "h_yards": sum(1 for h in holes if (h.get("tee_yards_by_tee_box") or h.get("teeYardsByTeeBox"))),
            "h_gpoly": sum(1 for h in holes if hv(h, "green_polygon", "greenPolygon")),
            "tees": len(tees),
            "t_yards":  sum(1 for t in tees if t.get("totalYards")),
            "t_rating": sum(1 for t in tees if t.get("rating") is not None),
            "t_slope":  sum(1 for t in tees if t.get("slope") is not None),
        }
    except Exception as e:
        return {"id": cid, "state": "error", "error": str(e)[:120]}

def main():
    done = set()
    if os.path.exists(OUT):
        with open(OUT) as f:
            done = {json.loads(l)["id"] for l in f if l.strip()}
    ids = [i for i in gps_ready_ids() if i not in done]
    print(f"{len(ids)} blobs to audit ({len(done)} already done)")
    with open(OUT, "a") as out, ThreadPoolExecutor(max_workers=12) as ex:
        for n, res in enumerate(ex.map(audit, ids), 1):
            out.write(json.dumps(res) + "\n")
            if n % 2000 == 0:
                out.flush()
                print(f"{n}/{len(ids)}")
    print("done")

if __name__ == "__main__":
    main()
