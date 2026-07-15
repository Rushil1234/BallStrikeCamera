#!/usr/bin/env python3
"""Hue-distance gallery — the winning channel from channel_explorer, at scale.

Renders ONLY the hue-distance separation (angular hue distance from each
frame's own dominant turf hue, achromatic override, shadow gate) for N shots,
with detection overlays drawn directly on the channel:

  red circle  — ball: roundest blob with area-radius 2.5..22 px (radius comes
                from area so merged bright neighbors can't inflate it)
  cyan dot    — clubhead center: centroid of the largest remaining blob

Usage:
  python3 hue_dist_gallery.py --archive <AllFramesArchive> [--replay <dir>]
      [--auto 50 | --shots a,b,...] [--pre 2] [--post 7] --out out.html [--open]
"""
import argparse, base64, os, sys
import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hsv_object_explorer import pick_diverse, impact_index  # noqa: E402


def hue_dist(bgr):
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    H = hsv[..., 0].astype(np.int16)
    S = hsv[..., 1].astype(np.int16)
    V = hsv[..., 2].astype(np.int16)
    turf_sel = (S >= 60) & (V >= 60)
    turf_hue = np.median(H[turf_sel]) if turf_sel.sum() > 500 else 60
    dh = np.abs(H - turf_hue)
    dh = np.minimum(dh, 180 - dh).astype(np.float32)
    dh = np.clip(dh * 4, 0, 255)
    dh[S < 40] = 255      # achromatic (ball paint, chrome) = maximally not-turf
    dh[V < 60] = 0        # shadow / black shaft stays dark
    return dh.astype(np.uint8), int(turf_hue)


def detect_on_channel(dh, motion=None):
    """Returns (ball (cx,cy,r) or None, club (cx,cy) or None).

    Hard cutoffs, not "best available" — a frame with no ball or club in it
    shows no marker. Ball: roundest compact not-turf blob. Club: compact,
    non-border blob that is MOVING (mean motion above cutoff) — the bag, mat
    markings, and edge strips are not-turf too, but only the clubhead moves.
    """
    Hh, Ww = dh.shape
    mask = (dh >= 160).astype(np.uint8) * 255
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    blobs = []
    for c in contours:
        area = cv2.contourArea(c)
        if area < 12:
            continue
        (ex, ey), er = cv2.minEnclosingCircle(c)
        circ = float(area / (np.pi * er * er + 1e-6))
        r_area = float(np.sqrt(area / np.pi))
        m = cv2.moments(c)
        if m['m00'] <= 0:
            continue
        cx, cy = m['m10'] / m['m00'], m['m01'] / m['m00']
        x, y, w, h = cv2.boundingRect(c)
        border = x <= 1 or y <= 1 or x + w >= Ww - 2 or y + h >= Hh - 2
        mot = 0.0
        if motion is not None:
            mot = float(motion[y:y + h, x:x + w].mean())
        blobs.append({'area': area, 'circ': circ, 'r': r_area, 'cx': cx, 'cy': cy,
                      'w': w, 'h': h, 'border': border, 'mot': mot})

    BALL_MIN_CIRC = 0.55
    BALL_MIN_AREA = 15
    CLUB_AREA = (120, 2500)
    CLUB_MAX_ASPECT = 3.0
    CLUB_MIN_MOTION = 18.0

    ball = None
    ball_cands = [b for b in blobs
                  if 2.5 <= b['r'] <= 22 and b['circ'] >= BALL_MIN_CIRC and b['area'] >= BALL_MIN_AREA
                  and not b['border']]   # border strips speckle into round-ish fragments
    if ball_cands:
        # roundest wins; prefer the smaller blob on a tie (clubheads run bigger)
        ball_cands.sort(key=lambda b: (-b['circ'], b['r']))
        ball = ball_cands[0]

    club = None
    club_cands = [b for b in blobs
                  if b is not ball and not b['border']
                  and CLUB_AREA[0] <= b['area'] <= CLUB_AREA[1]
                  and max(b['w'], b['h']) / max(1, min(b['w'], b['h'])) <= CLUB_MAX_ASPECT
                  and (motion is None or b['mot'] >= CLUB_MIN_MOTION)
                  and not (ball and abs(b['cx'] - ball['cx']) < ball['r'] * 2
                           and abs(b['cy'] - ball['cy']) < ball['r'] * 2)]
    if club_cands:
        club = max(club_cands, key=lambda b: b['mot'] if motion is not None else b['area'])
    return ball, club


def render_frame(bgr, tag, base_luma=None):
    dh, turf = hue_dist(bgr)
    motion = None
    if base_luma is not None:
        motion = np.abs(bgr.mean(axis=2) - base_luma)
    ball, club = detect_on_channel(dh, motion)
    out = cv2.cvtColor(dh, cv2.COLOR_GRAY2BGR)
    if ball:
        cv2.circle(out, (int(ball['cx']), int(ball['cy'])), int(ball['r']) + 3, (60, 60, 255), 2)
    if club:
        p = (int(club['cx']), int(club['cy']))
        cv2.circle(out, p, 4, (255, 220, 60), -1)
        cv2.line(out, (p[0] - 9, p[1]), (p[0] + 9, p[1]), (255, 220, 60), 1)
        cv2.line(out, (p[0], p[1] - 9), (p[0], p[1] + 9), (255, 220, 60), 1)
    cv2.rectangle(out, (0, 0), (12 + 9 * len(tag), 20), (0, 0, 0), -1)
    cv2.putText(out, tag, (5, 14), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (80, 235, 255), 1)
    return out


def b64jpg(img):
    ok, buf = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 66])
    return base64.b64encode(buf).decode()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--archive', required=True)
    ap.add_argument('--replay', default=None)
    ap.add_argument('--shots', default=None)
    ap.add_argument('--auto', type=int, default=50)
    ap.add_argument('--pre', type=int, default=2)
    ap.add_argument('--post', type=int, default=7)
    ap.add_argument('--out', required=True)
    ap.add_argument('--open', action='store_true')
    a = ap.parse_args()

    shots = a.shots.split(',') if a.shots else pick_diverse(a.archive, a.auto)
    sections = []
    for shot in shots:
        imp, src = impact_index(shot, a.archive, a.replay)
        # pre-impact median luma → motion map for the club's moving-blob gate
        pres = []
        for i in range(0, max(3, imp - 2), 3):
            p = os.path.join(a.archive, shot, f'frame_{i:03d}.png')
            if os.path.exists(p):
                pres.append(cv2.imread(p).mean(axis=2))
        base_luma = np.median(np.stack(pres), axis=0) if len(pres) >= 3 else None
        cells = []
        for fi in range(imp - a.pre, imp + a.post + 1):
            p = os.path.join(a.archive, shot, f'frame_{fi:03d}.png')
            if not os.path.exists(p):
                continue
            tag = f'f{fi}' + (' IMPACT' if fi == imp else '')
            out = render_frame(cv2.imread(p), tag, base_luma)
            cells.append(f'<div class="cell"><img src="data:image/jpeg;base64,{b64jpg(out)}"></div>')
        t = shot[5:]
        pretty = f'{t[4:6]}/{t[6:8]} {t[9:11]}:{t[11:13]}:{t[13:15]}'
        sections.append(
            f'<h2>{shot}</h2><p class="sub">captured {pretty} · impact f{imp} ({src})</p>'
            f'<div class="strip">{"".join(cells)}</div>')

    html = f"""<title>Hue-Distance Gallery — {len(shots)} shots, ball + clubhead marked</title>
<style>
:root {{ --bg:#111417; --panel:#1a1f24; --line:#2a3138; --text:#e8ebee; --mut:#98a2ab; }}
@media (prefers-color-scheme: light) {{ :root {{ --bg:#f2f4f6; --panel:#fff; --line:#d9dee3; --text:#1a2026; --mut:#5b6570; }} }}
:root[data-theme="dark"] {{ --bg:#111417; --panel:#1a1f24; --line:#2a3138; --text:#e8ebee; --mut:#98a2ab; }}
:root[data-theme="light"] {{ --bg:#f2f4f6; --panel:#fff; --line:#d9dee3; --text:#1a2026; --mut:#5b6570; }}
body {{ background:var(--bg); color:var(--text); font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; margin:0; padding:28px 18px 70px; }}
main {{ max-width:1280px; margin:0 auto; }}
h1 {{ font-size:24px; margin:0 0 2px; }}
h2 {{ font-size:14px; font-family:ui-monospace,Menlo,monospace; margin:30px 0 2px; }}
.sub {{ color:var(--mut); font-size:12px; margin:0 0 6px; }}
.legend {{ color:var(--mut); font-size:13.5px; margin:6px 0 10px; max-width:100ch; }}
.strip {{ display:flex; gap:6px; overflow-x:auto; padding:8px; background:var(--panel); border:1px solid var(--line); border-radius:8px; }}
.cell img {{ height:200px; display:block; border-radius:4px; }}
</style>
<main>
<h1>Hue-Distance Gallery</h1>
<p class="legend"><b style="color:#e05252">Red circle</b> = ball (roundest not-turf blob, radius from area) · <b style="color:#3fd4e0">cyan crosshair</b> = clubhead center (largest remaining blob). No circle/dot drawn when nothing qualifies — an empty frame is the honest answer once the ball is gone. Frames run impact−{a.pre} → impact+{a.post}; {len(shots)} shots spanning July 10–12.</p>
{''.join(sections)}
</main>"""
    with open(a.out, 'w') as f:
        f.write(html)
    print(f'wrote {a.out} ({os.path.getsize(a.out)//1024} KB, {len(shots)} shots)')
    if a.open:
        os.system(f'open "{a.out}"')


if __name__ == '__main__':
    main()
