#!/usr/bin/env python3
"""GUI course locator — manual companion to geolocate_courses.py.

Native macOS dialogs (osascript) — no tkinter needed (the system Tk 8.5
aborts on macOS 26). Feeds you ONLY the courses the batch geocoder marked
no_match (reading geolocate_progress.jsonl live, so new leftovers appear
while it's still running — zero collisions with the automated pass).

Per course: Google Maps opens → right-click the course → copy coordinates
→ paste into the popup → Save. Applied to Supabase immediately + logged to
tools/fix_sql/located_coords.sql. Progress in gui_locate_progress.jsonl
(resumable). Press Escape/Cancel in the dialog to quit.

    python3 tools/locate_gui.py
"""
import json, os, re, subprocess, time, urllib.parse, urllib.request

SB = "https://aoxturoezgecwceudeef.supabase.co"
KEY = open(os.path.expanduser("~/Downloads/BallStrikeCamera/Config/service_role.key")).read().strip()
HERE = os.path.dirname(os.path.abspath(__file__))
GEO_PROGRESS = os.path.join(HERE, "artifacts/geolocate_progress.jsonl")
GUI_PROGRESS = os.path.join(HERE, "artifacts/gui_locate_progress.jsonl")
SQL_LOG = os.path.join(HERE, "fix_sql", "located_coords.sql")
COORD_RE = re.compile(r"^\s*(-?\d+\.?\d*)\s*,\s*(-?\d+\.?\d*)\s*$")

def patch(cid, body):
    req = urllib.request.Request(f"{SB}/rest/v1/courses?id=eq.{cid}", method="PATCH", headers={
        "apikey": KEY, "Authorization": f"Bearer {KEY}",
        "Content-Type": "application/json", "Prefer": "return=minimal",
    }, data=json.dumps(body).encode())
    urllib.request.urlopen(req, timeout=30).read()

def log_sql(stmt):
    os.makedirs(os.path.dirname(SQL_LOG), exist_ok=True)
    with open(SQL_LOG, "a") as f:
        f.write(stmt + "\n")

def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')

def dialog(title, message, with_input=True):
    """Native macOS dialog. Returns (button, text) or (None, None) on Cancel."""
    answer = 'default answer ""' if with_input else ""
    script = (f'display dialog "{esc(message)}" {answer} '
              f'buttons {{"Gone", "Skip", "Save"}} default button "Save" '
              f'with title "{esc(title)}"')
    p = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if p.returncode != 0:      # Cancel / Escape
        return None, None
    out = p.stdout.strip()     # e.g. button returned:Save, text returned:41.0, -74.6
    btn = re.search(r"button returned:([^,]+)", out)
    txt = re.search(r"text returned:(.*)$", out)
    return (btn.group(1) if btn else None), (txt.group(1).strip() if txt else "")

def notify(msg):
    subprocess.run(["osascript", "-e",
                    f'display notification "{esc(msg)}" with title "True Carry locator"'],
                   capture_output=True)

def handled_ids():
    if not os.path.exists(GUI_PROGRESS):
        return set()
    with open(GUI_PROGRESS) as f:
        return {json.loads(l)["id"] for l in f if l.strip()}

def record(course, outcome, **extra):
    with open(GUI_PROGRESS, "a") as f:
        f.write(json.dumps({"id": course["id"], "name": course["name"],
                            "outcome": outcome, **extra}) + "\n")

def no_match_stream():
    """Yields no_match rows from the geocoder's progress file, tailing it live."""
    done = handled_ids()
    offset = 0
    quiet_polls = 0
    while True:
        new = []
        if os.path.exists(GEO_PROGRESS):
            with open(GEO_PROGRESS) as f:
                f.seek(offset)
                chunk = f.read()
                offset = f.tell()
            for line in chunk.splitlines():
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if r.get("state_") == "no_match" and r["id"] not in done:
                    new.append(r)
        if new:
            quiet_polls = 0
            for r in new:
                yield r
        else:
            quiet_polls += 1
            if quiet_polls == 1:
                notify("Caught up — waiting for the geocoder to hand over more…")
            if quiet_polls > 60:   # ~5 min of nothing new → geocoder is done
                return
            time.sleep(5)

def main():
    done_count = len(handled_ids())
    for c in no_match_stream():
        where = ", ".join(x for x in (c.get("city"), c.get("state")) if x)
        q = urllib.parse.quote_plus(f"{c['name']} golf {where}")
        subprocess.run(["open", f"https://www.google.com/maps/search/{q}"])
        note = ""
        while True:
            msg = (f"{c['name']}\n{where or '(no city/state on file)'}\n\n"
                   f"Paste 'lat, lon' (right-click the course in Maps → copy coords)."
                   f"{chr(10) + '⚠️ ' + note if note else ''}")
            btn, txt = dialog(f"Locate course — {done_count} done", msg)
            if btn is None:
                print(f"Quit. {done_count} handled this far; rerun to resume.")
                return
            if btn == "Skip":
                record(c, "skipped")
                break
            if btn == "Gone":
                try:
                    patch(c["id"], {"status": "closed"})
                except Exception as e:
                    note = f"save failed: {e}"
                    continue
                log_sql(f"update public.courses set status='closed' "
                        f"where id='{c['id']}';  -- manual: verified gone")
                record(c, "gone")
                done_count += 1
                break
            m = COORD_RE.match(txt or "")
            if not m:
                note = "couldn't parse — paste like: 41.0564, -74.6463"
                continue
            lat, lon = float(m.group(1)), float(m.group(2))
            if not (18 <= lat <= 72 and -180 <= lon <= -66):
                note = "outside US bounds — double-check"
                continue
            try:
                patch(c["id"], {"latitude": lat, "longitude": lon})
            except Exception as e:
                note = f"save failed: {e}"
                continue
            log_sql(f"update public.courses set latitude={lat}, longitude={lon} "
                    f"where id='{c['id']}';  -- manual: {c['name']}")
            record(c, "located", lat=lat, lon=lon)
            done_count += 1
            break
    notify(f"All caught up — {done_count} courses handled.")
    print(f"Done — {done_count} handled.")

if __name__ == "__main__":
    main()
