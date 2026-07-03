#!/usr/bin/env python3
"""enrich_tee_ratings.py — merge USGA/R&A slope+rating tees into course geometry blobs.

For each course id in slope_ratings_by_id.csv, fetch course-geometry/<id>.json.gz, merge the
CSV tees into the blob's teeBoxes (rating/slope feed the app's handicap differential), and
re-upload. Existing hole-linked teeBoxes are preserved (and filled with rating/slope where they
match); the only ones dropped are the empty "Course GPS" fallback. Women's tees are labeled "(W)".

Usage:
  python3 enrich_tee_ratings.py <csv> [--limit N] [--dry-run] [--workers 24]

Env: reads Config/service_role.key relative to repo root; SUPABASE_URL overrides the default.
Idempotent + resumable (processed ids logged to a .done file next to the csv).
"""
import csv, json, gzip, io, os, re, sys, time, urllib.request, urllib.error, collections, threading, concurrent.futures

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
URL = os.environ.get("SUPABASE_URL", "https://aoxturoezgecwceudeef.supabase.co").rstrip("/")
KEY = open(os.path.join(REPO, "Config", "service_role.key")).read().strip()
BUCKET = "course-geometry"

CSV = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else os.path.join(REPO, "slope_ratings_by_id.csv")
DRY = "--dry-run" in sys.argv
LIMIT = next((int(sys.argv[i + 1]) for i, a in enumerate(sys.argv) if a == "--limit"), None)
WORKERS = next((int(sys.argv[i + 1]) for i, a in enumerate(sys.argv) if a == "--workers"), 24)
DONE_PATH = CSV + ".done"

COLORS = {"white", "red", "blue", "gold", "green", "black", "purple", "yellow", "silver",
          "orange", "teal", "gray", "grey", "bronze", "copper", "pink", "tan", "maroon",
          "navy", "brown", "championship", "charcoal", "burgundy"}

def norm(s):
    s = (s or "").lower().strip()
    s = re.sub(r"\(\s*[wmf]\s*\)", " ", s)   # drop our own "(W)" gender label
    s = re.sub(r"\btees?\b", "", s)
    s = re.sub(r"[^a-z0-9/]+", " ", s).strip()
    return s

def gender_of(*vals):
    # Recognizes source tees ("blue-male"/"blue-female") AND our appended ids/names
    # ("black-w"/"Black (W)") so re-runs stay idempotent.
    for v in vals:
        v = (v or "").lower()
        if "female" in v or "(w)" in v or "(f)" in v or v.endswith("-w") or v == "f": return "F"
        if "male" in v or "(m)" in v or v.endswith("-m") or v == "m": return "M"
    return None

def color_from(name):
    for tok in re.split(r"[^a-z]+", (name or "").lower()):
        if tok in COLORS:
            return "Gray" if tok in ("gray", "grey") else tok.capitalize()
    return "Gray"

def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", (s or "tee").lower()).strip("-") or "tee"

# ---- load CSV grouped by course ----
by_course = collections.defaultdict(list)
with open(CSV) as f:
    for row in csv.DictReader(f):
        by_course[row["id"]].append(row)
ids = list(by_course.keys())
if LIMIT: ids = ids[:LIMIT]

done = set()
if os.path.exists(DONE_PATH):
    with open(DONE_PATH) as f: done = set(l.strip() for l in f if l.strip())
todo = [i for i in ids if i not in done]
print(f"csv courses: {len(ids)}  already done: {len(done & set(ids))}  to process: {len(todo)}"
      + ("  [DRY RUN]" if DRY else ""))

def http(method, path, data=None, headers=None, tries=5):
    for a in range(tries):
        try:
            req = urllib.request.Request(URL + path, data=data, method=method, headers=headers or {})
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404: return 404, None
            if a == tries - 1: return e.code, (e.read() if hasattr(e, "read") else None)
        except Exception:
            if a == tries - 1: return -1, None
        time.sleep(0.6 * (a + 1))

def fetch_blob(cid):
    # authenticated endpoint bypasses the public CDN cache (fresh reads on re-runs)
    st, body = http("GET", f"/storage/v1/object/{BUCKET}/{cid}.json.gz",
                    headers={"apikey": KEY, "Authorization": f"Bearer {KEY}"})
    if st != 200 or not body: return st, None
    try: return 200, json.loads(gzip.decompress(body))
    except Exception: return -2, None

def upload_blob(cid, obj):
    raw = gzip.compress(json.dumps(obj, separators=(",", ":")).encode())
    st, _ = http("POST", f"/storage/v1/object/{BUCKET}/{cid}.json.gz", data=raw, headers={
        "apikey": KEY, "Authorization": f"Bearer {KEY}",
        "Content-Type": "application/json", "Content-Encoding": "gzip", "x-upsert": "true",
    })
    return st in (200, 201)

def build_tees(cid, blob):
    existing = blob.get("tee_boxes") or blob.get("teeBoxes") or []
    holes = blob.get("holes") or []
    linked = set()
    for h in holes:
        for k in ("teeYardsByTeeBox", "tee_yards_by_tee_box", "teeCoordinateByTeeBox", "tee_coordinate_by_tee_box"):
            v = h.get(k)
            if isinstance(v, dict): linked.update(v.keys())

    # index CSV rows by (gender, normalized name), first wins
    idx = {}
    glist = collections.defaultdict(list)
    for r in by_course[cid]:
        g = "F" if r["gender"] in ("F", "Female") else "M"
        key = (g, norm(r["tee_name"]))
        idx.setdefault(key, r)
        try: glist[g].append((float(r["length_yards"]), r))
        except (ValueError, TypeError): pass

    consumed = set()
    out = []
    matched = 0
    for tb in existing:
        tid = tb.get("id", ""); tname = tb.get("name", "")
        # drop the empty GPS fallback if we have real tees to add
        if (tid == "gps" or norm(tname) == "course gps") and by_course[cid]:
            continue
        g = gender_of(tid, tname) or "M"
        r = idx.get((g, norm(tname)))
        method = "name"
        if not r:
            y = tb.get("totalYards") or tb.get("total_yards") or 0
            if 1000 < y < 8500 and glist[g]:
                r = min(glist[g], key=lambda x: abs(x[0] - y))[1]; method = "yards"
        # Rebuild cleanly: a single int totalYards (never emit snake `total_yards`, which would
        # collide with camelCase under convertFromSnakeCase and null out a non-optional Int).
        yards = tb.get("totalYards")
        if not isinstance(yards, int): yards = tb.get("total_yards")
        if not isinstance(yards, int): yards = 0
        nt = {"id": tid or slug(tname), "name": tname or "Tee",
              "color": tb.get("color") or color_from(tname), "totalYards": yards}
        if tb.get("rating") is not None: nt["rating"] = tb["rating"]
        if tb.get("slope") is not None: nt["slope"] = tb["slope"]
        if r:
            nt["rating"] = float(r["course_rating"]); nt["slope"] = int(float(r["slope_rating"]))
            if not nt.get("totalYards"):
                try: nt["totalYards"] = int(float(r["length_yards"]))
                except (ValueError, TypeError): pass
            consumed.add((g, norm(r["tee_name"]))); matched += 1
        out.append(nt)

    # append CSV tees not already represented
    added = 0
    for (g, nm), r in idx.items():
        if (g, nm) in consumed: continue
        try: yards = int(float(r["length_yards"]))
        except (ValueError, TypeError): yards = 0
        nm_label = r["tee_name"] + (" (W)" if g == "F" else "")
        out.append({
            "id": f"{slug(r['tee_name'])}-{'w' if g == 'F' else 'm'}",
            "name": nm_label, "color": color_from(r["tee_name"]),
            "totalYards": yards,
            "rating": float(r["course_rating"]), "slope": int(float(r["slope_rating"])),
        })
        added += 1
    return out, matched, added

lock = threading.Lock()
stats = collections.Counter()
done_f = None if DRY else open(DONE_PATH, "a")

def process(cid):
    st, blob = fetch_blob(cid)
    if st == 404: return "missing"
    if blob is None: return "fetch_err"
    tees, matched, added = build_tees(cid, blob)
    blob.pop("teeBoxes", None)          # standardize on snake_case key
    blob["tee_boxes"] = tees
    with lock:
        stats["tees_total"] += len(tees); stats["tees_filled_existing"] += matched; stats["tees_added"] += added
    if DRY: return "ok"
    if upload_blob(cid, blob):
        with lock:
            done_f.write(cid + "\n"); done_f.flush()
        return "ok"
    return "upload_err"

n = 0
with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as ex:
    for res in ex.map(process, todo):
        stats[res] += 1; n += 1
        if n % 500 == 0 or n == len(todo):
            print(f"  {n}/{len(todo)}  ok={stats['ok']} missing={stats['missing']} "
                  f"fetch_err={stats['fetch_err']} upload_err={stats['upload_err']}")

if done_f: done_f.close()
print("\ndone.")
print(f"  courses ok: {stats['ok']}  missing blob: {stats['missing']}  "
      f"fetch_err: {stats['fetch_err']}  upload_err: {stats['upload_err']}")
print(f"  tee boxes written: {stats['tees_total']}  "
      f"(filled existing: {stats['tees_filled_existing']}, newly added: {stats['tees_added']})")
