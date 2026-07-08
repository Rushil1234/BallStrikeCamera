#!/usr/bin/env python3
"""Merge the R&A ratings CSV (randa_slope_tees_FINAL.csv) into the backend.

Three phases (all resumable via randa_merge_progress.jsonl):
  blob    — existing gps_ready courses: merge tees into the geometry blob's
            tee_boxes. Match by case-folded base name + gender (blob keeps
            women's tees as separate "NAME (W)" / -w entries). Fill missing
            rating/slope only — NEVER overwrite a non-null value. Append
            R&A tees the blob lacks (totalYards 0 until a yardage source
            exists). Originals backed up to tools/randa_merge_backup/.
  table   — existing non-gps courses: same merge into the course_geometries
            row's payload.teeBoxes (row located by payload->>id; created
            minimal if absent). scorecard_verified is NOT touched — R&A has
            ratings but no yardages, so these aren't full scorecards.
  insert  — randa_new_course rows: new catalog courses (data_tier basic,
            no coordinates → they join the locate pipeline) + a payload row
            carrying their tees.

Usage:  python3 tools/randa_merge.py [--dry-run]
"""
import csv, gzip, json, os, re, sys, urllib.parse, urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor

SB = "https://aoxturoezgecwceudeef.supabase.co"
KEY = open(os.path.expanduser("~/Downloads/BallStrikeCamera/Config/service_role.key")).read().strip()
HERE = os.path.dirname(os.path.abspath(__file__))
CSV = os.path.join(HERE, "randa_slope_tees_FINAL.csv")
PROGRESS = os.path.join(HERE, "artifacts/randa_merge_progress.jsonl")
BACKUP = os.path.join(HERE, "artifacts/randa_merge_backup")
DRY = "--dry-run" in sys.argv

def rest(path, method="GET", body=None, prefer=None):
    headers = {"apikey": KEY, "Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}
    if prefer: headers["Prefer"] = prefer
    req = urllib.request.Request(SB + path, method=method, headers=headers,
                                 data=json.dumps(body).encode() if body is not None else None)
    with urllib.request.urlopen(req, timeout=90) as r:
        raw = r.read()
        return json.loads(raw) if raw else None

# ── CSV → per-course tee lists ─────────────────────────────────────────────
def slugify(s):
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", (s or "").lower())).strip("-")

def load_csv():
    existing, new = defaultdict(list), defaultdict(list)
    meta = {}
    for r in csv.DictReader(open(CSV)):
        cid = r["course_id"]
        tee = {
            "name": r["teeName"].strip(),
            "gender": r["gender"].strip().lower(),   # male / female
            "rating": float(r["courseRating"]) if r["courseRating"] else None,
            "slope": int(float(r["slopeRating"])) if r["slopeRating"] else None,
            "par": int(float(r["par"])) if r["par"] else None,
            "nine": not (r["backPar"] and float(r["backPar"]) > 0),
        }
        (existing if r["record_source"] == "existing_missing_course" else new)[cid].append(tee)
        meta[cid] = r
    return existing, new, meta

BASE_W = re.compile(r"\s*\((w|women|ladies|f)\)\s*$", re.I)

def base_name(name):
    return BASE_W.sub("", name or "").strip().lower()

def is_female_entry(t):
    return bool(BASE_W.search(t.get("name") or "")) or str(t.get("id") or "").endswith("-w")

COLORS = {"black","blue","white","red","gold","green","silver","yellow","orange",
          "purple","bronze","copper","tan","teal","pink","gray","grey","platinum"}

def to_entry(tee):
    nm = tee["name"]
    display = nm if tee["gender"] != "female" or BASE_W.search(nm) else f"{nm} (W)"
    color = next((c.capitalize() for c in COLORS if c in nm.lower()), None)
    suffix = "w" if tee["gender"] == "female" else "m"
    return {"id": f"{slugify(nm)}-{suffix}-randa", "name": display, "color": color,
            "totalYards": 0, "rating": tee["rating"], "slope": tee["slope"]}

def merge_tees(entries, randa_tees):
    """Merge R&A tees into a tee list (blob or payload shape). Returns
    (changed, filled_count, added_count)."""
    entries = entries if entries is not None else []
    index = {}
    for t in entries:
        index[(base_name(t.get("name")), is_female_entry(t))] = t
    filled = added = 0
    for rt in randa_tees:
        key = (rt["name"].strip().lower(), rt["gender"] == "female")
        hit = index.get(key)
        if hit is not None:
            if hit.get("rating") is None and rt["rating"] is not None:
                hit["rating"] = rt["rating"]; filled += 1
            if hit.get("slope") is None and rt["slope"] is not None:
                hit["slope"] = rt["slope"]; filled += 1
        else:
            e = to_entry(rt)
            if (base_name(e["name"]), rt["gender"] == "female") in index:
                continue
            entries.append(e)
            index[(base_name(e["name"]), rt["gender"] == "female")] = e
            added += 1
    return (filled + added) > 0, filled, added, entries

# ── phase: blobs ───────────────────────────────────────────────────────────
def process_blob(args):
    cid, tees = args
    try:
        url = f"{SB}/storage/v1/object/public/course-geometry/{cid}.json.gz"
        with urllib.request.urlopen(urllib.request.Request(url), timeout=60) as r:
            raw = r.read()
        doc = json.loads(gzip.decompress(raw))
        key = "tee_boxes" if doc.get("tee_boxes") is not None else "teeBoxes"
        changed, filled, added, merged = merge_tees(doc.get(key) or [], tees)
        if not changed:
            return {"id": cid, "phase": "blob", "state": "no_change"}
        if not DRY:
            os.makedirs(BACKUP, exist_ok=True)
            with open(os.path.join(BACKUP, f"{cid}.json.gz"), "wb") as f:
                f.write(raw)
            doc[key] = merged
            req = urllib.request.Request(f"{SB}/storage/v1/object/course-geometry/{cid}.json.gz",
                                         data=gzip.compress(json.dumps(doc).encode()), method="PUT",
                                         headers={"Authorization": f"Bearer {KEY}", "apikey": KEY,
                                                  "Content-Type": "application/gzip", "x-upsert": "true"})
            urllib.request.urlopen(req, timeout=120).read()
        return {"id": cid, "phase": "blob", "state": "merged", "filled": filled, "added": added}
    except Exception as e:
        return {"id": cid, "phase": "blob", "state": "error", "error": str(e)[:150]}

# ── phase: course_geometries payloads ─────────────────────────────────────
def process_table(args):
    cid, tees, name, country = args
    try:
        rows = rest(f"/rest/v1/course_geometries?select=course_id,payload&payload->>id=eq.{cid}&limit=1")
        if rows:
            row = rows[0]
            payload = row["payload"]
            changed, filled, added, merged = merge_tees(payload.get("teeBoxes"), tees)
            if not changed:
                return {"id": cid, "phase": "table", "state": "no_change"}
            payload["teeBoxes"] = merged
            if not DRY:
                rest(f"/rest/v1/course_geometries?course_id=eq.{urllib.parse.quote(str(row['course_id']))}",
                     method="PATCH", body={"payload": payload, "source": "randa_merge"}, prefer="return=minimal")
            return {"id": cid, "phase": "table", "state": "merged", "filled": filled, "added": added}
        _, filled, added, merged = merge_tees([], tees)
        payload = {"id": cid, "name": name, "country": country, "holes": [], "teeBoxes": merged}
        if not DRY:
            rest("/rest/v1/course_geometries", method="POST",
                 body={"course_id": cid, "course_name": name, "payload": payload,
                       "source": "randa_merge", "geometry_state": "auto_draft"},
                 prefer="return=minimal,resolution=merge-duplicates")
        return {"id": cid, "phase": "table", "state": "created", "added": added}
    except Exception as e:
        return {"id": cid, "phase": "table", "state": "error", "error": str(e)[:150]}

def main():
    existing, new, meta = load_csv()
    done = set()
    if os.path.exists(PROGRESS):
        with open(PROGRESS) as f:
            done = {(j["phase"], j["id"]) for j in map(json.loads, f) if j.get("state") != "error"}

    tiers = {}
    ids = list(existing)
    for i in range(0, len(ids), 100):
        q = ",".join(f'"{x}"' for x in ids[i:i + 100]).replace('"', "%22")
        for r in rest(f"/rest/v1/courses?select=id,name,country,data_tier&id=in.({q})"):
            tiers[r["id"]] = r

    blob_jobs = [(cid, tees) for cid, tees in existing.items()
                 if tiers.get(cid, {}).get("data_tier") == "gps_ready" and ("blob", cid) not in done]
    table_jobs = [(cid, tees, tiers[cid]["name"], tiers[cid].get("country"))
                  for cid, tees in existing.items()
                  if cid in tiers and tiers[cid]["data_tier"] != "gps_ready" and ("table", cid) not in done]
    print(f"blob: {len(blob_jobs)}  table: {len(table_jobs)}  new: {len(new)}{' [DRY RUN]' if DRY else ''}")

    stats = defaultdict(int)
    with open(PROGRESS, "a") as prog, ThreadPoolExecutor(max_workers=12) as ex:
        for n, res in enumerate(ex.map(process_blob, blob_jobs), 1):
            stats[f"blob_{res['state']}"] += 1
            prog.write(json.dumps(res) + "\n")
            if n % 500 == 0: prog.flush(); print(f"blob {n}/{len(blob_jobs)}")
        for n, res in enumerate(ex.map(process_table, table_jobs), 1):
            stats[f"table_{res['state']}"] += 1
            prog.write(json.dumps(res) + "\n")
            if n % 500 == 0: prog.flush(); print(f"table {n}/{len(table_jobs)}")

        # phase: new catalog courses (bulk inserts of 200)
        new_jobs = [cid for cid in new if ("insert", cid) not in done]
        for i in range(0, len(new_jobs), 200):
            chunk = new_jobs[i:i + 200]
            course_rows, geo_rows = [], []
            for cid in chunk:
                m = meta[cid]
                tees = new[cid]
                nine = all(t["nine"] for t in tees)
                par = max((t["par"] or 0) for t in tees) or None
                slug = f"{(m['country'] or 'xx').lower()}-{slugify(m['course_name'])}-randa-{m['randa_cid']}-{cid[:8]}"
                course_rows.append({"id": cid, "name": m["course_name"], "country": m["country"] or "",
                                    "slug": slug, "normalized_name": re.sub(r"[^a-z0-9 ]", "", m["course_name"].lower()),
                                    "source_system": "randa", "source_id": f"{m['randa_cid']}:{m['randa_courseName']}",
                                    "status": "active", "data_tier": "basic",
                                    "hole_count": 9 if nine else 18, "par": par,
                                    "attribution": "Ratings © The R&A Course Rating Database"})
                _, _, added, merged = merge_tees([], tees)
                geo_rows.append({"course_id": cid, "course_name": m["course_name"],
                                 "payload": {"id": cid, "name": m["course_name"], "country": m["country"] or "",
                                             "holes": [], "teeBoxes": merged},
                                 "source": "randa_merge", "geometry_state": "auto_draft"})
            if not DRY:
                try:
                    rest("/rest/v1/courses", method="POST", body=course_rows,
                         prefer="return=minimal,resolution=merge-duplicates")
                    rest("/rest/v1/course_geometries", method="POST", body=geo_rows,
                         prefer="return=minimal,resolution=merge-duplicates")
                    for cid in chunk:
                        stats["insert_ok"] += 1
                        prog.write(json.dumps({"id": cid, "phase": "insert", "state": "ok"}) + "\n")
                except Exception as e:
                    stats["insert_error"] += len(chunk)
                    for cid in chunk:
                        prog.write(json.dumps({"id": cid, "phase": "insert", "state": "error",
                                               "error": str(e)[:150]}) + "\n")
            prog.flush()
    print("Done —", dict(stats))

if __name__ == "__main__":
    main()
