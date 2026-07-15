#!/usr/bin/env python3
"""HSV + contour object explorer — tracker-free detection sanity check.

Finds objects that differ from the (green turf) background using nothing but
HSV masks + contour geometry, so detection quality can be judged independently
of any tracking logic:

  white_mask : achromatic + bright  (ball paint, chrome crown highlights)
  nongreen   : anything whose hue/saturation says "not turf" and isn't shadow

Per contour classification:
  BALL  candidate — enclosing circle 5..48 px across, circularity >= 0.55 (red)
  CLUB  candidate — big or elongated blob (blue box)
  other foreground — thin green outline

Usage:
  python3 hsv_object_explorer.py --archive <AllFramesArchive> \
      [--replay <ReplayResults dir>] [--shots shot_a,shot_b | --auto 10] \
      [--pre 2] [--post 7] --out explorer.html [--open]

Impact frame comes from --replay's detected impact when available, else the
shot's metadata.json, else 20.
"""
import argparse, base64, json, os, sys
import cv2
import numpy as np


def frame_path(d, fi):
    """New captures are .jpg (July 14 JPEG switch); old archives are .png."""
    import os as _os
    for ext in ('png', 'jpg'):
        p = _os.path.join(d, f'frame_{fi:03d}.{ext}')
        if _os.path.exists(p):
            return p
    return _os.path.join(d, f'frame_{fi:03d}.png')


def list_shots(archive):
    return sorted(d for d in os.listdir(archive)
                  if d.startswith('shot_') and os.path.isdir(os.path.join(archive, d)))


def pick_diverse(archive, n):
    """One shot per distinct date+hour bucket, oldest first, padded from the
    biggest buckets if there are fewer buckets than requested."""
    shots = list_shots(archive)
    buckets = {}
    for s in shots:
        key = s[5:16]  # yyyymmdd_hh
        buckets.setdefault(key, []).append(s)
    picks = [v[len(v) // 2] for k, v in sorted(buckets.items())]  # mid-bucket shot
    # Round-robin the remaining shots across buckets (largest first) until n.
    if len(picks) < n:
        pools = [ [s for s in v if s not in picks]
                  for k, v in sorted(buckets.items(), key=lambda kv: -len(kv[1])) ]
        i = 0
        while len(picks) < n and any(pools):
            pool = pools[i % len(pools)]
            if pool:
                picks.append(pool.pop(0))
            i += 1
    return sorted(picks)[:n]


def impact_index(shot, archive, replay_dir):
    if replay_dir:
        rp = os.path.join(replay_dir, f'{shot}.json')
        if os.path.exists(rp):
            j = json.load(open(rp))
            if isinstance(j.get('impactDetected'), int):
                return j['impactDetected'], 'replay'
    mp = os.path.join(archive, shot, 'metadata.json')
    if os.path.exists(mp):
        j = json.load(open(mp))
        if isinstance(j.get('impact_frame_index'), int):
            return j['impact_frame_index'], 'metadata'
    return 20, 'default'


def detect(bgr):
    """Returns (annotated image, ball candidates, club candidates)."""
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    H, S, V = hsv[..., 0], hsv[..., 1], hsv[..., 2]

    white = ((S <= 60) & (V >= 135)).astype(np.uint8)
    green = ((H >= 30) & (H <= 95) & (S >= 45)).astype(np.uint8)
    nongreen = ((green == 0) & (V >= 80)).astype(np.uint8)
    fg = ((white | nongreen) * 255).astype(np.uint8)

    fg = cv2.morphologyEx(fg, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    fg = cv2.morphologyEx(fg, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))

    contours, _ = cv2.findContours(fg, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    out = cv2.convertScaleAbs(bgr, alpha=1.6, beta=0)
    balls, clubs = [], []
    for c in contours:
        area = cv2.contourArea(c)
        if area < 8:
            continue
        (cx, cy), r = cv2.minEnclosingCircle(c)
        circ = float(area / (np.pi * r * r + 1e-6))
        x, y, w, h = cv2.boundingRect(c)
        elong = max(w, h) / max(1, min(w, h))
        if 5 <= 2 * r <= 48 and circ >= 0.55:
            balls.append((cx, cy, r, circ, area))
        elif area >= 400 or (elong >= 2.5 and area >= 60):
            clubs.append((x, y, w, h, area))
        else:
            cv2.drawContours(out, [c], -1, (90, 220, 90), 1)

    for (x, y, w, h, area) in clubs:
        cv2.rectangle(out, (x, y), (x + w, y + h), (255, 160, 60), 2)
    for (cx, cy, r, circ, area) in sorted(balls, key=lambda b: -b[3]):
        cv2.circle(out, (int(cx), int(cy)), int(r) + 2, (60, 60, 255), 2)
        cv2.putText(out, f'{circ:.2f}', (int(cx) - 12, int(cy) - int(r) - 5),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.35, (60, 60, 255), 1)
    return out, balls, clubs


def b64jpg(img, scale=2):
    img = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_LANCZOS4)
    ok, buf = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 68])
    return base64.b64encode(buf).decode()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--archive', required=True)
    ap.add_argument('--replay', default=None)
    ap.add_argument('--shots', default=None, help='comma-separated shot folder names')
    ap.add_argument('--auto', type=int, default=10, help='auto-pick N diverse shots')
    ap.add_argument('--pre', type=int, default=2)
    ap.add_argument('--post', type=int, default=7)
    ap.add_argument('--out', required=True)
    ap.add_argument('--open', action='store_true')
    a = ap.parse_args()

    shots = a.shots.split(',') if a.shots else pick_diverse(a.archive, a.auto)
    sections = []
    for shot in shots:
        imp, src = impact_index(shot, a.archive, a.replay)
        cells = []
        for fi in range(imp - a.pre, imp + a.post + 1):
            p = os.path.join(a.archive, shot, f'frame_{fi:03d}.png')
            if not os.path.exists(p):
                continue
            bgr = cv2.imread(p)
            out, balls, clubs = detect(bgr)
            tag = f'f{fi}' + (' IMPACT' if fi == imp else '')
            cv2.rectangle(out, (0, 0), (10 + 9 * len(tag), 22), (0, 0, 0), -1)
            cv2.putText(out, tag, (5, 16), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (60, 235, 255), 1)
            cells.append(
                f'<div class="cell"><img src="data:image/jpeg;base64,{b64jpg(out)}">'
                f'<div class="meta">{len(balls)} ball-like · {len(clubs)} club-like</div></div>')
        t = shot[5:]
        pretty = f'{t[4:6]}/{t[6:8]} {t[9:11]}:{t[11:13]}:{t[13:15]}'
        sections.append(
            f'<h2>{shot}</h2><p class="sub">captured {pretty} · impact f{imp} ({src})</p>'
            f'<div class="strip">{"".join(cells)}</div>')

    html = f"""<title>HSV Object Explorer — 10 shots across the week</title>
<style>
:root {{ --bg:#111417; --panel:#1a1f24; --line:#2a3138; --text:#e8ebee; --mut:#98a2ab; }}
@media (prefers-color-scheme: light) {{ :root {{ --bg:#f2f4f6; --panel:#fff; --line:#d9dee3; --text:#1a2026; --mut:#5b6570; }} }}
:root[data-theme="dark"] {{ --bg:#111417; --panel:#1a1f24; --line:#2a3138; --text:#e8ebee; --mut:#98a2ab; }}
:root[data-theme="light"] {{ --bg:#f2f4f6; --panel:#fff; --line:#d9dee3; --text:#1a2026; --mut:#5b6570; }}
body {{ background:var(--bg); color:var(--text); font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; margin:0; padding:28px 18px 70px; }}
main {{ max-width:1200px; margin:0 auto; }}
h1 {{ font-size:24px; margin:0 0 2px; }}
h2 {{ font-size:15px; font-family:ui-monospace,Menlo,monospace; margin:34px 0 2px; }}
.sub {{ color:var(--mut); font-size:12.5px; margin:0 0 8px; }}
.legend {{ color:var(--mut); font-size:13px; margin:6px 0 8px; }}
.legend b {{ font-weight:600; }}
.strip {{ display:flex; gap:6px; overflow-x:auto; padding:8px; background:var(--panel); border:1px solid var(--line); border-radius:8px; }}
.cell img {{ height:210px; display:block; border-radius:4px; }}
.cell .meta {{ font-size:11px; color:var(--mut); text-align:center; padding-top:3px; }}
</style>
<main>
<h1>HSV Object Explorer</h1>
<p class="legend">Tracker-free detection: HSV masks + contours only. <b style="color:#e05252">Red circle</b> = ball-like (round, 5–48 px, circularity labeled) · <b style="color:#4a9fe0">Blue box</b> = club-like (large/elongated) · <b style="color:#5abf5a">green outline</b> = other foreground. Frames run impact−{a.pre} → impact+{a.post}.</p>
{''.join(sections)}
</main>"""
    with open(a.out, 'w') as f:
        f.write(html)
    print(f'wrote {a.out} ({os.path.getsize(a.out)//1024} KB, {len(shots)} shots)')
    if a.open:
        os.system(f'open "{a.out}"')


if __name__ == '__main__':
    main()
