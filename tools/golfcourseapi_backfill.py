#!/usr/bin/env python3
"""GolfCourseAPI scorecard backfill — pull tees/ratings/gendered handicaps for every course
WITHOUT anyone having to play it, replicating the app's Berkshire-style merge:

  • confident name match (normalized containment, ≥8 chars)
  • sanitize raw tees (drop zero-yardage phantoms), dedupe color+yardage
  • merge tees the geometry misses (skip same-name or total within 25y = same markers)
  • backfill rating/slope (men's + women's) onto same-name tees
  • gendered stroke indexes: male → handicap, female → womens_handicap (first-write-wins)
  • write merged payload to course_geometries with scorecard_verified = true

The app's enrich() then serves these rows and never calls GolfCourseAPI for them again.

Usage:
  python3 tools/golfcourseapi_backfill.py --limit 50            # process 50 unverified courses
  python3 tools/golfcourseapi_backfill.py --course-id <uuid>    # one course
Resumable: progress in tools/backfill_progress.jsonl. Respect API rate limits — run in batches.
"""
import argparse, gzip, json, os, re, time, urllib.parse, urllib.request

SB  = "https://aoxturoezgecwceudeef.supabase.co"
KEY = open(os.path.expanduser("~/Downloads/BallStrikeCamera/Config/service_role.key")).read().strip()
GC_KEY = "IXUJAYAEVORVW2Z4M24EAE3H4U"   # GolfCourseAPI (100k req/day plan)
PROGRESS = os.path.join(os.path.dirname(__file__), "artifacts/backfill_progress.jsonl")

def rest(path, method="GET", body=None):
    req = urllib.request.Request(SB + path, method=method,
        headers={"apikey": KEY, "Authorization": f"Bearer {KEY}",
                 "Content-Type": "application/json", "Prefer": "resolution=merge-duplicates"})
    data = json.dumps(body).encode() if body is not None else None
    with urllib.request.urlopen(req, data=data, timeout=30) as r:
        raw = r.read()
        return json.loads(raw) if raw.strip() else None

def gc_search(name, tries=5):
    url = "https://api.golfcourseapi.com/v1/search?search_query=" + urllib.parse.quote(name)
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"Authorization": f"Key {GC_KEY}"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read()).get("courses", [])
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < tries - 1:
                time.sleep(3 * (attempt + 1))   # rate limited — back off and retry
                continue
            if e.code == 404:
                return []
            raise RuntimeError(f"gcapi:{e.code}")

def norm(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())

def names_match(a, b):
    na, nb = norm(a), norm(b)
    if len(na) < 8 or len(nb) < 8:
        return na == nb
    return na == nb or na in nb or nb in na

def fetch_blob(cid):
    url = f"{SB}/storage/v1/object/public/course-geometry/{cid}.json.gz"
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            raw = r.read()
        return json.loads(gzip.decompress(raw) if raw[:2] == b"\x1f\x8b" else raw)
    except Exception:
        return None

TEE_COLORS = [("championship", "Black"), ("black", "Black"), ("blue", "Blue"), ("white", "White"),
              ("green", "Green"), ("gold", "Gold"), ("yellow", "Gold"), ("red", "Red"),
              ("forward", "Red"), ("silver", "Silver")]

def infer_color(name):
    low = (name or "").lower()
    for k, v in TEE_COLORS:
        if k in low:
            return v
    return "Gray"

def merge(payload, gc):
    """Apply the app's merge rules onto a geometry payload dict (snake_case keys)."""
    raw_m = (gc.get("tees") or {}).get("male") or []
    raw_f = (gc.get("tees") or {}).get("female") or []
    entries = [(t, False) for t in raw_m] + [(t, True) for t in raw_f]

    # ── gendered handicaps: first-write-wins per gender ──
    holes = payload.get("holes") or []
    by_num = {h.get("number"): h for h in holes}
    for tee, is_f in entries:
        for i, rh in enumerate(tee.get("holes") or []):
            h = by_num.get(i + 1)
            hcp = rh.get("handicap")
            if not h or hcp is None:
                continue
            key = "womens_handicap" if is_f else "handicap"
            if h.get(key) is None:
                h[key] = hcp

    # ── tee merge (sanitize, dedupe, rating backfill) ──
    tees_out = payload.get("tee_boxes") or payload.get("teeBoxes") or []
    existing_names = {norm(t.get("name", "")) for t in tees_out}
    existing_totals = [t.get("total_yards") or t.get("totalYards") or 0 for t in tees_out]
    seen = set()
    for tee, is_f in entries:
        name = tee.get("tee_name") or tee.get("name") or ""
        total = tee.get("total_yards") or 0
        if total <= 0:
            continue
        # rating backfill onto same-name geometry tee
        for t in tees_out:
            if norm(t.get("name", "")) == norm(name):
                rk, sk = ("womens_rating", "womens_slope") if is_f else ("rating", "slope")
                if t.get(rk) is None:
                    t[rk] = tee.get("course_rating")
                if t.get(sk) is None:
                    t[sk] = tee.get("slope_rating")
        dk = f"{norm(name)}|{total}"
        if dk in seen or norm(name) in existing_names:
            continue
        if any(abs(total - et) <= 25 for et in existing_totals if et > 0):
            continue   # same physical markers under another name
        seen.add(dk)
        tees_out.append({"id": f"gcapi-{norm(name)}{'-w' if is_f else ''}",
                         "name": name + (" (W)" if is_f and norm(name) in {norm(t.get('tee_name') or t.get('name') or '') for t in raw_m} else ""),
                         "color": infer_color(name), "total_yards": total,
                         "rating": tee.get("course_rating"), "slope": tee.get("slope_rating")})
        existing_totals.append(total)
    payload["tee_boxes"] = tees_out
    return payload

def process(row):
    cid, name = row["id"], row["name"]
    club = name.split("~")[0].strip()
    payload = fetch_blob(cid)
    if payload is None:
        return "no_blob"
    matches = gc_search(club)
    gc = next((c for c in matches if names_match(c.get("club_name") or c.get("course_name") or "", club)), None)
    if gc is None:
        return "no_match"
    merged = merge(payload, gc)
    body = {"course_id": cid, "course_name": name, "city": row.get("city") or "",
            "state": row.get("state") or "", "source": "gcapi-backfill",
            "geometry_state": "accepted", "schema_version": 1,
            "validation_errors": [], "payload": merged,
            "scorecard_verified": True, "generated_by": "gcapi-backfill",
            "latitude": row.get("latitude"), "longitude": row.get("longitude")}
    rest("/rest/v1/course_geometries?on_conflict=course_id", "POST", [body])
    return "verified"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=25)
    ap.add_argument("--course-id")
    ap.add_argument("--sleep", type=float, default=1.2, help="seconds between API calls")
    args = ap.parse_args()

    done = set()
    if os.path.exists(PROGRESS):
        done = {json.loads(l)["id"] for l in open(PROGRESS) if l.strip()}

    if args.course_id:
        rows = rest(f"/rest/v1/courses?id=eq.{args.course_id}&select=id,name,city,state,latitude,longitude")
    else:
        rows, off = [], 0
        while True:
            page = rest(f"/rest/v1/courses?data_tier=eq.gps_ready&select=id,name,city,state,latitude,longitude&limit=1000&offset={off}")
            rows += page
            if len(page) < 1000: break
            off += 1000
    todo = [r for r in rows if r["id"] not in done][:args.limit]
    print(f"processing {len(todo)} courses ({len(done)} already done)", flush=True)
    from concurrent.futures import ThreadPoolExecutor
    import threading
    lock = threading.Lock()
    counts = {}
    def work(r):
        try:
            status = process(r)
        except Exception as e:
            status = f"error:{e}"
        with lock:
            counts[status.split(':')[0]] = counts.get(status.split(':')[0], 0) + 1
            with open(PROGRESS, "a") as f:
                f.write(json.dumps({"id": r["id"], "name": r["name"], "status": status}) + "\n")
            n = sum(counts.values())
            if n % 250 == 0:
                print(f"{n}/{len(todo)} — {counts}", flush=True)
        time.sleep(args.sleep)
    with ThreadPoolExecutor(max_workers=4) as ex:
        list(ex.map(work, todo))
    print(f"BATCH DONE — {counts}", flush=True)

if __name__ == "__main__":
    main()
