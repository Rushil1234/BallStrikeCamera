#!/usr/bin/env python3
"""Club point-extraction experiment: which SINGLE point on the club head gives the
most consistent frame-to-frame velocity (and best TT club-speed agreement)?

Strategies, computed from the union-mask blob nearest each hand label:
  centroid   blob center of mass (current tracker behavior)
  lead_mid   leading-edge midpoint: extreme -x contour point at blob's vertical center band
  lead_top   top of the leading contour (approximates Noah's labeling convention)
  face_c     center of the leading FACE: mean of the front 25% of blob pixels
Judged on: velocity smoothness (per-shot std of frame deltas), and 2-frame club
speed vs TT club truth on jul17 pairs.
"""
import csv, glob, json, math, os, sys
import cv2
import numpy as np

sys.path.insert(0, '/Users/noahtobias/Downloads/BallStrikeCamera/tools/experimental')
from hsv_object_explorer import frame_path

TRAIN = os.path.expanduser('~/Documents/TrueCarryTraining')
LABELS = json.load(open(os.path.join(TRAIN, 'labels/labels.json')))
EXCLUDED = set(json.load(open(os.path.join(TRAIN, 'session_2026-07-17/excluded_shots.json'))))
ARCHIVES = [os.path.expanduser(a) for a in (
    '~/Documents/TrueCarryFramesArchive_20260717/AllFramesArchive',
    '~/Documents/TrueCarryFramesArchive_20260716/AllFramesArchive',
    '~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')]


def shot_dir(shot):
    for a in ARCHIVES:
        d = os.path.join(a, shot)
        if os.path.isdir(d):
            return d
    return None


def mo(m):
    k = np.ones((3, 3), np.uint8)
    return cv2.morphologyEx(cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_OPEN, k),
                            cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))


def club_blob(bgr, base, near):
    """Largest moving blob within 25px of the label point."""
    luma = bgr.mean(axis=2)
    mot = np.abs(luma - base)
    m = mo(mot >= 30)
    n, lab, stats, cents = cv2.connectedComponentsWithStats(m, 8)
    best = None
    for i in range(1, n):
        if stats[i, cv2.CC_STAT_AREA] < 40:
            continue
        d = math.hypot(cents[i][0] - near[0], cents[i][1] - near[1])
        if d > 40:
            continue
        if best is None or stats[i, cv2.CC_STAT_AREA] > stats[best, cv2.CC_STAT_AREA]:
            best = i
    if best is None:
        return None
    return lab == best


def points_from_blob(comp):
    ys, xs = np.nonzero(comp)
    cx, cy = xs.mean(), ys.mean()
    out = {'centroid': (cx, cy)}
    # leading edge = minimum x (play is right-to-left)
    x_lead = xs.min()
    band = xs <= x_lead + 3
    lead_ys = ys[band]
    out['lead_mid'] = (xs[band].mean(), lead_ys.mean())
    out['lead_top'] = (xs[band & (ys <= lead_ys.min() + 2)].mean(),
                       ys[band & (ys <= lead_ys.min() + 2)].mean())
    # leading face: front 25% of pixels by x
    q = np.quantile(xs, 0.25)
    face = xs <= q
    out['face_c'] = (xs[face].mean(), ys[face].mean())
    return out


def main():
    pairs = {}
    for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-17/pairs.json'))):
        tt = p.get('toptracer') or {}
        if tt.get('club_mph'):
            pairs[p['shot']] = tt['club_mph']

    smooth = {k: [] for k in ('centroid', 'lead_mid', 'lead_top', 'face_c')}
    spd_err = {k: [] for k in smooth}
    shots_used = 0
    for shot, labs in sorted(LABELS.items()):
        if shot in EXCLUDED:
            continue
        d = shot_dir(shot)
        if d is None:
            continue
        club_lab = sorted((int(f), e['club']) for f, e in labs.items()
                          if isinstance(e, dict) and e.get('reviewed') and e.get('club'))
        if len(club_lab) < 3:
            continue
        base_imgs = []
        for bi in (0, 2, 4):
            p = frame_path(d, bi)
            if p and os.path.exists(p):
                base_imgs.append(cv2.imread(p).astype(float).mean(axis=2))
        if len(base_imgs) < 2:
            continue
        base = np.median(np.stack(base_imgs), axis=0)
        ts_p = os.path.join(d, 'timestamps.json')
        ts = {}
        if os.path.exists(ts_p):
            ts = {e['frame_index']: e['timestamp']
                  for e in json.load(open(ts_p)).get('timestamps', [])}
        tracks = {k: [] for k in smooth}
        for fi, cl in club_lab[:5]:
            im = cv2.imread(frame_path(d, fi))
            if im is None:
                continue
            comp = club_blob(im, base, (cl['cx'], cl['cy']))
            if comp is None:
                continue
            pts = points_from_blob(comp)
            t = ts.get(fi, fi / 240.0)
            for k, (px, py) in pts.items():
                tracks[k].append((t, px, py))
        shots_used += 1
        for k, tr in tracks.items():
            if len(tr) < 3:
                continue
            deltas = []
            for a, b in zip(tr, tr[1:]):
                dt = b[0] - a[0]
                if dt <= 0:
                    continue
                deltas.append(math.hypot(b[1] - a[1], b[2] - a[2]) / dt)
            if len(deltas) >= 2:
                smooth[k].append(np.std(deltas) / (np.mean(deltas) + 1e-9))
            # speed vs TT: 2nd+3rd points (Noah's frames), px->mph via ball-scale proxy
            if shot in pairs and len(tr) >= 3:
                a, b = tr[1], tr[2]
                dt = b[0] - a[0]
                if dt > 0:
                    vpx = math.hypot(b[1] - a[1], b[2] - a[2]) / dt
                    # scale: use rest-ball r from labels if available
                    pts_b = {int(kk): v['ball'] for kk, v in labs.items()
                             if isinstance(v, dict) and v.get('ball')}
                    if pts_b:
                        r0 = max(4.0, pts_b[min(pts_b)].get('r', 6))
                        mph = vpx * 0.04267 / (2 * r0) * 2.23694
                        spd_err[k].append((mph - pairs[shot]) / pairs[shot] * 100)
    print(f'shots used: {shots_used}')
    print(f'{"strategy":<10} {"vel jitter (cv)":>16} {"club speed err%":>18}  n_speed')
    for k in smooth:
        j = np.median(smooth[k]) if smooth[k] else float("nan")
        arr = np.array(spd_err[k])
        e = np.median(arr) if len(arr) else float("nan")
        corrected = arr - np.median(arr)
        pc = np.median(np.abs(corrected)) if len(arr) else float("nan")
        print(f'{k:<10} jitter {j:.3f}  bias {e:+.1f}%  POST-CAL abs median {pc:.1f}%  n={len(arr)}')


if __name__ == '__main__':
    main()
