#!/usr/bin/env python3
"""Dedupe tee boxes inside course-geometry blobs.

The GolfCourseAPI/USGA merge sometimes wrote the SAME tee twice — identical
data, one name in ALL CAPS and one not ("GOLD" + "Gold"). Duplicate = same
case-folded name AND same totalYards. Keeper per group = most non-null fields,
preferring the mixed-case display name. Hole-level maps key by tee COLOR, not
tee id, so dropping a tee_boxes entry never orphans hole data.

Safety: every rewritten blob's original bytes are saved to
tools/tee_dedupe_backup/<id>.json.gz first. Progress in
tee_dedupe_progress.jsonl (resumable); summary in tee_dedupe_report.csv.

Usage:  python3 tools/dedupe_tees.py [--dry-run]
"""
import csv, gzip, json, os, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor

SB = "https://aoxturoezgecwceudeef.supabase.co"
KEY = open(os.path.expanduser("~/Downloads/BallStrikeCamera/Config/service_role.key")).read().strip()
HERE = os.path.dirname(__file__)
PROGRESS = os.path.join(HERE, "artifacts/tee_dedupe_progress.jsonl")
REPORT = os.path.join(HERE, "artifacts/tee_dedupe_report.csv")
BACKUP_DIR = os.path.join(HERE, "artifacts/tee_dedupe_backup")
DRY = "--dry-run" in sys.argv

def rest(path, tries=4):
    for attempt in range(tries):
        try:
            req = urllib.request.Request(SB + path, headers={"apikey": KEY, "Authorization": f"Bearer {KEY}"})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read())
        except Exception:
            if attempt == tries - 1:
                raise
            import time as _t; _t.sleep(2 * (attempt + 1))

def gps_ready_ids():
    ids, off = [], 0
    while True:
        page = rest(f"/rest/v1/courses?select=id&data_tier=eq.gps_ready&status=eq.active&order=id.asc&limit=1000&offset={off}")
        ids += [r["id"] for r in page]
        if len(page) < 1000:
            return ids
        off += 1000

def fetch_blob(cid):
    url = f"{SB}/storage/v1/object/public/course-geometry/{cid}.json.gz"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()

def upload_blob(cid, raw_gzip):
    url = f"{SB}/storage/v1/object/course-geometry/{cid}.json.gz"
    req = urllib.request.Request(url, data=raw_gzip, method="PUT", headers={
        "Authorization": f"Bearer {KEY}", "apikey": KEY,
        "Content-Type": "application/gzip", "x-upsert": "true",
    })
    with urllib.request.urlopen(req, timeout=120) as r:
        r.read()

def tee_score(t):
    s = sum(1 for k in ("rating", "slope", "color") if t.get(k) is not None)
    if t.get("totalYards"):
        s += 1
    name = t.get("name") or ""
    if name and not name.isupper():
        s += 0.5   # tiebreak: prefer the mixed-case twin as keeper
    return s

def dedupe(tees):
    """Returns (new_tees, removed_names) or (None, []) when nothing to do."""
    groups = {}
    for t in tees:
        key = ((t.get("name") or "").strip().lower(), t.get("totalYards"))
        groups.setdefault(key, []).append(t)
    if all(len(g) == 1 for g in groups.values()):
        return None, []
    kept, removed = [], []
    for t in tees:
        key = ((t.get("name") or "").strip().lower(), t.get("totalYards"))
        group = groups[key]
        if len(group) == 1:
            kept.append(t)
            continue
        best = max(group, key=tee_score)
        if t is best:
            kept.append(t)
        else:
            removed.append(t.get("name") or "?")
    return kept, removed

def process(cid):
    try:
        raw = fetch_blob(cid)
        doc = json.loads(gzip.decompress(raw))
        tees = doc.get("tee_boxes") or doc.get("teeBoxes")
        tee_key = "tee_boxes" if doc.get("tee_boxes") is not None else "teeBoxes"
        if not tees:
            return {"id": cid, "state": "no_tees"}
        new_tees, removed = dedupe(tees)
        if new_tees is None:
            return {"id": cid, "state": "clean"}
        if not DRY:
            os.makedirs(BACKUP_DIR, exist_ok=True)
            with open(os.path.join(BACKUP_DIR, f"{cid}.json.gz"), "wb") as f:
                f.write(raw)
            doc[tee_key] = new_tees
            upload_blob(cid, gzip.compress(json.dumps(doc).encode()))
        return {"id": cid, "state": "fixed", "removed": removed,
                "before": len(tees), "after": len(new_tees)}
    except Exception as e:
        return {"id": cid, "state": "error", "error": str(e)[:200]}

def main():
    done = set()
    if os.path.exists(PROGRESS):
        with open(PROGRESS) as f:
            done = {json.loads(l)["id"] for l in f if l.strip()}
    ids = [i for i in gps_ready_ids() if i not in done]
    print(f"{len(ids)} blobs to scan ({len(done)} already done){' [DRY RUN]' if DRY else ''}")
    fixed = errors = 0
    with open(PROGRESS, "a") as prog, ThreadPoolExecutor(max_workers=12) as ex:
        for n, res in enumerate(ex.map(process, ids), 1):
            prog.write(json.dumps(res) + "\n")
            if res["state"] == "fixed":
                fixed += 1
            elif res["state"] == "error":
                errors += 1
            if n % 500 == 0:
                prog.flush()
                print(f"{n}/{len(ids)} scanned — {fixed} fixed, {errors} errors")
    # Summary CSV from the full progress log.
    with open(PROGRESS) as f, open(REPORT, "w", newline="") as out:
        w = csv.writer(out)
        w.writerow(["course_id", "state", "tees_before", "tees_after", "removed_names"])
        for line in f:
            r = json.loads(line)
            if r["state"] in ("fixed", "error"):
                w.writerow([r["id"], r["state"], r.get("before", ""), r.get("after", ""),
                            "; ".join(r.get("removed", [])) or r.get("error", "")])
    print(f"Done. {fixed} blobs rewritten, {errors} errors. Report: {REPORT}")

if __name__ == "__main__":
    main()
