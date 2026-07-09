#!/usr/bin/env python3
"""Recompute missing tee totalYards from the blob's own per-hole yardages.

Targets every gps_ready blob where a declared tee lacks totalYards but the
holes carry per-hole yardage maps (keyed by tee id, name, or color — matched
case-insensitively, same as the app's summing logic). Pure arithmetic, no
external data. Only rewrites blobs where at least one tee gains a total;
originals backed up to tools/tee_totals_backup/. Candidates come from
blob_completeness.jsonl (tees > 0 and t_yards < tees).

Usage:  python3 tools/fix_tee_totals.py [--dry-run]
"""
import gzip, json, os, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor

SB = "https://aoxturoezgecwceudeef.supabase.co"
KEY = open(os.path.expanduser("~/Downloads/BallStrikeCamera/Config/service_role.key")).read().strip()
HERE = os.path.dirname(os.path.abspath(__file__))
COMPLETENESS = os.path.join(HERE, "artifacts/blob_completeness.jsonl")
PROGRESS = os.path.join(HERE, "artifacts/fix_tee_totals_progress.jsonl")
BACKUP = os.path.join(HERE, "artifacts/tee_totals_backup")
DRY = "--dry-run" in sys.argv

def fetch(cid):
    url = f"{SB}/storage/v1/object/public/course-geometry/{cid}.json.gz"
    with urllib.request.urlopen(urllib.request.Request(url), timeout=60) as r:
        return r.read()

def upload(cid, raw):
    req = urllib.request.Request(f"{SB}/storage/v1/object/course-geometry/{cid}.json.gz",
                                 data=raw, method="PUT", headers={
        "Authorization": f"Bearer {KEY}", "apikey": KEY,
        "Content-Type": "application/gzip", "x-upsert": "true"})
    urllib.request.urlopen(req, timeout=120).read()

def recompute(doc):
    tees_key = "tee_boxes" if doc.get("tee_boxes") is not None else "teeBoxes"
    tees = doc.get(tees_key) or []
    holes = doc.get("holes") or []
    fixed = []
    for t in tees:
        if t.get("totalYards"):
            continue
        keys = {str(t.get(k, "")).strip().lower() for k in ("id", "name", "color")} - {""}
        total = 0
        for h in holes:
            ymap = h.get("tee_yards_by_tee_box") or h.get("teeYardsByTeeBox") or {}
            for mk, yards in ymap.items():
                if str(mk).strip().lower() in keys and isinstance(yards, (int, float)) and yards > 0:
                    total += int(yards)
                    break
        if total > 0:
            t["totalYards"] = total
            fixed.append((t.get("name") or t.get("id") or "?", total))
    return fixed

def process(cid):
    try:
        raw = fetch(cid)
        doc = json.loads(gzip.decompress(raw))
        fixed = recompute(doc)
        if not fixed:
            return {"id": cid, "state": "unfixable"}
        if not DRY:
            os.makedirs(BACKUP, exist_ok=True)
            with open(os.path.join(BACKUP, f"{cid}.json.gz"), "wb") as f:
                f.write(raw)
            upload(cid, gzip.compress(json.dumps(doc).encode()))
        return {"id": cid, "state": "fixed", "tees": [f"{n}={y}" for n, y in fixed]}
    except Exception as e:
        return {"id": cid, "state": "error", "error": str(e)[:150]}

def main():
    done = set()
    if os.path.exists(PROGRESS):
        with open(PROGRESS) as f:
            done = {json.loads(l)["id"] for l in f if l.strip()}
    cands = []
    with open(COMPLETENESS) as f:
        for line in f:
            r = json.loads(line)
            if r.get("state") == "ok" and r.get("tees", 0) > 0 and r["t_yards"] < r["tees"] and r["id"] not in done:
                cands.append(r["id"])
    print(f"{len(cands)} blobs with recomputable tee totals{' [DRY RUN]' if DRY else ''}")
    counts = {}
    with open(PROGRESS, "a") as prog, ThreadPoolExecutor(max_workers=12) as ex:
        for n, res in enumerate(ex.map(process, cands), 1):
            counts[res["state"]] = counts.get(res["state"], 0) + 1
            prog.write(json.dumps(res) + "\n")
            if n % 1000 == 0:
                prog.flush()
                print(f"{n}/{len(cands)} — {counts}")
    print(f"Done — {counts}")

if __name__ == "__main__":
    main()
