#!/usr/bin/env python3
"""Channel explorer — which representation makes ball + club pop against turf?

For each frame renders a 6-panel grid:

  A original      brightened copy, for reference
  B inv-sat       255 - Saturation, gated by V: achromatic things (ball paint,
                  chrome) glow white, colored turf goes dark — color-agnostic
  C lab-a         LAB green-red axis: turf is strongly green (low a), ball and
                  club sit near neutral — lighting-robust
  D hue-dist      angular hue distance from the frame's own dominant turf hue —
                  self-calibrating against time-of-day color shifts
  E motion        luma minus per-pixel median of pre-impact frames — anything
                  the strike set in motion glows, static glare vanishes
  F detections    contours of (inv-sat mask OR motion mask): red circle for
                  round ball-sized blobs (radius from area, so merged bright
                  neighbors can't inflate it), green outline for the rest

Usage mirrors hsv_object_explorer.py:
  python3 channel_explorer.py --archive <AllFramesArchive> [--replay <dir>]
      [--shots a,b | --auto 10] [--pre 2] [--post 7] --out out.html [--open]
"""
import argparse, base64, json, os, sys
import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hsv_object_explorer import list_shots, pick_diverse, impact_index  # noqa: E402


def label(img, text):
    cv2.rectangle(img, (0, 0), (10 + 8 * len(text), 18), (0, 0, 0), -1)
    cv2.putText(img, text, (4, 13), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (80, 235, 255), 1)
    return img


def gray3(g):
    return cv2.cvtColor(g.astype(np.uint8), cv2.COLOR_GRAY2BGR)


def panels(bgr, base_luma):
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    H, S, V = hsv[..., 0].astype(np.int16), hsv[..., 1].astype(np.int16), hsv[..., 2].astype(np.int16)
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB)
    luma = bgr.mean(axis=2)

    # A original
    A = label(cv2.convertScaleAbs(bgr, alpha=1.6, beta=0), 'A original')

    # B inverted saturation, gated by value so shadow doesn't glow
    inv_s = np.clip(255 - S, 0, 255)
    inv_s[V < 70] = 0
    B = label(gray3(inv_s), 'B inv-sat (achromatic pops)')

    # C LAB a-channel stretched: turf lowest, neutral objects brightest
    a = lab[..., 1].astype(np.float32)
    a = np.clip((a - a.min()) / max(1.0, a.max() - a.min()) * 255, 0, 255)
    C = label(gray3(a), 'C lab-a (green vs neutral)')

    # D hue distance from dominant turf hue (self-calibrating per frame)
    turf_sel = (S >= 60) & (V >= 60)
    turf_hue = np.median(H[turf_sel]) if turf_sel.sum() > 500 else 60
    dh = np.abs(H - turf_hue)
    dh = np.minimum(dh, 180 - dh).astype(np.float32)
    dh = np.clip(dh * 4, 0, 255)
    dh[(S < 40)] = 255  # achromatic = maximally "not turf"
    dh[V < 60] = 0
    D = label(gray3(dh), f'D hue-dist (turf h={int(turf_hue)})')

    # E motion vs pre-impact median
    mot = np.clip((luma - base_luma) * 3, 0, 255)
    E = label(gray3(mot), 'E motion (static glare gone)')

    # F detections from (inv-sat OR motion)
    fg = (((inv_s >= 150) & (V >= 110)) | (mot >= 80)).astype(np.uint8) * 255
    fg = cv2.morphologyEx(fg, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    fg = cv2.morphologyEx(fg, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    F = cv2.convertScaleAbs(bgr, alpha=1.2, beta=0)
    contours, _ = cv2.findContours(fg, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    for c in contours:
        area = cv2.contourArea(c)
        if area < 8:
            continue
        (ex, ey), er = cv2.minEnclosingCircle(c)
        circ = float(area / (np.pi * er * er + 1e-6))
        r_area = float(np.sqrt(area / np.pi))       # radius from AREA, immune to merged halos
        if 2.5 <= r_area <= 24 and circ >= 0.5:
            cv2.circle(F, (int(ex), int(ey)), int(r_area) + 2, (60, 60, 255), 2)
        else:
            cv2.drawContours(F, [c], -1, (90, 220, 90), 1)
    F = label(F, 'F detections (B+E contours)')

    top = cv2.hconcat([A, B, C])
    bot = cv2.hconcat([D, E, F])
    return cv2.vconcat([top, bot])


def b64jpg(img):
    ok, buf = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 70])
    return base64.b64encode(buf).decode()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--archive', required=True)
    ap.add_argument('--replay', default=None)
    ap.add_argument('--shots', default=None)
    ap.add_argument('--auto', type=int, default=10)
    ap.add_argument('--pre', type=int, default=2)
    ap.add_argument('--post', type=int, default=7)
    ap.add_argument('--out', required=True)
    ap.add_argument('--open', action='store_true')
    a = ap.parse_args()

    shots = a.shots.split(',') if a.shots else pick_diverse(a.archive, a.auto)
    sections = []
    for shot in shots:
        imp, src = impact_index(shot, a.archive, a.replay)
        # pre-impact median luma for the motion channel
        pre_idx = [i for i in range(0, max(3, imp - 2), 3)][:6]
        pres = []
        for i in pre_idx:
            p = os.path.join(a.archive, shot, f'frame_{i:03d}.png')
            if os.path.exists(p):
                pres.append(cv2.imread(p).mean(axis=2))
        if len(pres) < 3:
            continue
        base_luma = np.median(np.stack(pres), axis=0)

        cells = []
        for fi in range(imp - a.pre, imp + a.post + 1):
            p = os.path.join(a.archive, shot, f'frame_{fi:03d}.png')
            if not os.path.exists(p):
                continue
            grid = panels(cv2.imread(p), base_luma)
            tag = f'f{fi}' + ('  IMPACT' if fi == imp else '')
            cv2.rectangle(grid, (0, grid.shape[0] - 22), (12 + 10 * len(tag), grid.shape[0]), (0, 0, 0), -1)
            cv2.putText(grid, tag, (6, grid.shape[0] - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 235, 90), 1)
            cells.append(f'<div class="cell"><img src="data:image/jpeg;base64,{b64jpg(grid)}"></div>')
        t = shot[5:]
        pretty = f'{t[4:6]}/{t[6:8]} {t[9:11]}:{t[11:13]}:{t[13:15]}'
        sections.append(
            f'<h2>{shot}</h2><p class="sub">captured {pretty} · impact f{imp} ({src}) · scroll → through frames</p>'
            f'<div class="strip">{"".join(cells)}</div>')

    html = f"""<title>Channel Explorer — ball/club separation, 10 shots</title>
<style>
:root {{ --bg:#111417; --panel:#1a1f24; --line:#2a3138; --text:#e8ebee; --mut:#98a2ab; }}
@media (prefers-color-scheme: light) {{ :root {{ --bg:#f2f4f6; --panel:#fff; --line:#d9dee3; --text:#1a2026; --mut:#5b6570; }} }}
:root[data-theme="dark"] {{ --bg:#111417; --panel:#1a1f24; --line:#2a3138; --text:#e8ebee; --mut:#98a2ab; }}
:root[data-theme="light"] {{ --bg:#f2f4f6; --panel:#fff; --line:#d9dee3; --text:#1a2026; --mut:#5b6570; }}
body {{ background:var(--bg); color:var(--text); font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; margin:0; padding:28px 18px 70px; }}
main {{ max-width:1280px; margin:0 auto; }}
h1 {{ font-size:24px; margin:0 0 2px; }}
h2 {{ font-size:15px; font-family:ui-monospace,Menlo,monospace; margin:34px 0 2px; }}
.sub {{ color:var(--mut); font-size:12.5px; margin:0 0 8px; }}
.legend {{ color:var(--mut); font-size:13.5px; margin:6px 0 10px; max-width:100ch; }}
.strip {{ display:flex; gap:8px; overflow-x:auto; padding:8px; background:var(--panel); border:1px solid var(--line); border-radius:8px; }}
.cell img {{ height:300px; display:block; border-radius:4px; }}
</style>
<main>
<h1>Channel Explorer</h1>
<p class="legend">Each frame is a 6-panel grid. <b>A</b> original · <b>B</b> inverted saturation — anything colorless (ball, chrome) glows, turf goes dark · <b>C</b> LAB green↔neutral axis · <b>D</b> hue distance from that frame's own turf color (self-calibrates to time of day) · <b>E</b> motion vs pre-impact median — static glare disappears, only struck things glow · <b>F</b> detections from B∪E: red = round ball-sized (radius from area, so bright neighbors can't inflate the circle), green = other foreground. Compare panels to pick the winning separation.</p>
{''.join(sections)}
</main>"""
    with open(a.out, 'w') as f:
        f.write(html)
    print(f'wrote {a.out} ({os.path.getsize(a.out)//1024} KB)')
    if a.open:
        os.system(f'open "{a.out}"')


if __name__ == '__main__':
    main()
