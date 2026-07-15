#!/usr/bin/env python3
"""Club scorer v2 — gradient-boosted stumps (depth-1, logistic loss).

Still JSON-portable to Swift: the model is a list of (feature, threshold,
left, right) plus a bias — evaluation is 120 comparisons and adds.

New features vs the linear scorer:
  prev_dist  — distance to the previous frame's club (teacher-forced from
               labels in training, self-forced at runtime): path continuity.
  w_r0/h_r0  — bbox extent in ball radii.
  cone_cos   — blob major axis alignment with the cone axis (shaft/head
               orientation runs along the swing).
Protocol: hold out each day (train on the other two), score INTEGRATED
frame accuracy on the held-out day via run_eval2's pipeline; final model
trains on all days.
"""
import json, math, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hsv_object_explorer import frame_path
import cv2
from detector2 import masks_and_blobs, club_feature_vector
from golf_context_detector import derive_lock

ARCHIVE = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')
LABELS = json.load(open(os.path.expanduser('~/Documents/TrueCarryTraining/labels/labels.json')))
CACHE = os.path.expanduser('~/Documents/TrueCarryTraining/labels/club_train_cache_v3.json')
OUT = os.path.expanduser('~/Documents/TrueCarryTraining/labels/club_gbt.json')


def club_feature_vector2(b, lock, r0, prev_club):
    base = club_feature_vector(b, lock, r0)
    if prev_club is not None:
        pd = min(math.hypot(b['cx'] - prev_club['cx'], b['cy'] - prev_club['cy']) / max(r0, 1) / 12.0, 1.5)
        has_prev = 1.0
    else:
        pd, has_prev = 1.0, 0.0
    dx, dy = b['cx'] - lock[0], b['cy'] - lock[1]
    n = math.hypot(dx, dy)
    axis = (math.cos(b.get('theta', 0)), math.sin(b.get('theta', 0)))
    radial = (dx / n, dy / n) if n > 1e-6 else (1.0, 0.0)
    cone_cos = abs(axis[0] * radial[0] + axis[1] * radial[1])
    return base + [pd, has_prev, b.get('w', 1) / max(r0, 1) / 10.0, b.get('h', 1) / max(r0, 1) / 10.0, cone_cos]


def build():
    if os.path.exists(CACHE):
        j = json.load(open(CACHE))
        return np.array(j['X']), np.array(j['y']), j['days'], j['frame_ids']
    X, y, days, fids = [], [], [], []
    for shot in sorted(LABELS):
        d = os.path.join(ARCHIVE, shot)
        first = cv2.imread(frame_path(d, 0))
        if first is None:
            continue
        Hh, Ww = first.shape[:2]
        meta_p = os.path.join(d, 'metadata.json')
        meta = json.load(open(meta_p)) if os.path.exists(meta_p) else {}
        lock_norm, _ = derive_lock(d, Ww, Hh, meta.get('locked_ball_rect'))
        lock = (lock_norm[0] * Ww, lock_norm[1] * Hh)
        r0 = max(4.0, lock_norm[2] * Ww / 2)
        pres = []
        for i in range(0, 14, 3):
            p = frame_path(d, i)
            if os.path.exists(p):
                pres.append(cv2.imread(p).mean(axis=2))
        base = np.median(np.stack(pres), axis=0) if len(pres) >= 3 else None
        keys = sorted(LABELS[shot], key=int)
        prev_luma = None
        prev_club_lab = None
        p_prev = frame_path(d, int(keys[0]) - 1)
        if os.path.exists(p_prev):
            prev_luma = cv2.imread(p_prev).mean(axis=2)
        for k in keys:
            lab = LABELS[shot][k]
            bgr = cv2.imread(frame_path(d, int(k)))
            if bgr is None:
                continue
            blobs, dh, luma = masks_and_blobs(bgr, prev_luma, base)
            prev_luma = luma
            lc = lab.get('club')
            negs = 0
            for b in blobs:
                if b['area'] < 12 or b['area'] > 6000:
                    continue
                pos = bool(lc) and math.hypot(b['cx'] - lc['cx'], b['cy'] - lc['cy']) <= 15
                if not pos:
                    negs += 1
                    if negs > 60:
                        continue
                X.append(club_feature_vector2(b, lock, r0, prev_club_lab))
                y.append(1 if pos else 0)
                days.append(shot[5:13])
                fids.append(f'{shot}/{k}')
            prev_club_lab = lc     # teacher forcing
    json.dump({'X': [list(map(float, r)) for r in X], 'y': y, 'days': days, 'frame_ids': fids},
              open(CACHE, 'w'))
    return np.array(X), np.array(y), days, fids


def train_gbt(X, y, rounds=120, shrink=0.3, n_thr=16):
    n, m = X.shape
    pos_w = (len(y) - y.sum()) / max(1, y.sum())
    sw = np.where(y == 1, pos_w, 1.0)
    p0 = np.clip(np.average(y, weights=sw), 1e-3, 1 - 1e-3)
    base = math.log(p0 / (1 - p0))
    F = np.full(n, base)
    stumps = []
    # precompute candidate thresholds per feature (quantiles)
    thr_grid = [np.unique(np.quantile(X[:, jj], np.linspace(0.05, 0.95, n_thr))) for jj in range(m)]
    for _ in range(rounds):
        p = 1 / (1 + np.exp(-np.clip(F, -30, 30)))
        g = sw * (p - y)             # gradient
        h = sw * p * (1 - p) + 1e-6  # hessian
        best = None
        for jj in range(m):
            xj = X[:, jj]
            for thr in thr_grid[jj]:
                left = xj <= thr
                gl, hl = g[left].sum(), h[left].sum()
                gr, hr = g.sum() - gl, h.sum() - hl
                gain = gl * gl / (hl + 1) + gr * gr / (hr + 1)
                if best is None or gain > best[0]:
                    best = (gain, jj, thr, -gl / (hl + 1), -gr / (hr + 1))
        _, jj, thr, vl, vr = best
        F += shrink * np.where(X[:, jj] <= thr, vl, vr)
        stumps.append((int(jj), float(thr), float(shrink * vl), float(shrink * vr)))
    return base, stumps


def gbt_prob(base, stumps, x):
    F = base
    for jj, thr, vl, vr in stumps:
        F += vl if x[jj] <= thr else vr
    return 1 / (1 + math.exp(-max(-30, min(30, F))))


def main():
    X, y, days, fids = build()
    print(f'club dataset v2: {len(y)} candidates, {int(y.sum())} positives')
    for held in sorted(set(days)):
        tr = np.array([d != held for d in days])
        base, stumps = train_gbt(X[tr], y[tr])
        # frame-level argmax accuracy on held-out day (full pools as cached)
        from collections import defaultdict
        by = defaultdict(list)
        for i, (dd, f) in enumerate(zip(days, fids)):
            if dd == held:
                by[f].append(i)
        for thr in (0.5, 0.65, 0.8):
            ok = tot = 0
            for f, idxs in by.items():
                has = any(y[i] for i in idxs)
                ps = [gbt_prob(base, stumps, X[i]) for i in idxs]
                bi = int(np.argmax(ps))
                tot += 1
                if has:
                    ok += 1 if (y[idxs[bi]] and ps[bi] >= thr) else 0
                else:
                    ok += 1 if ps[bi] < thr else 0
            print(f'held-out {held} thr={thr}: frame acc {100*ok/max(1,tot):.1f}% (n={tot})')
    base, stumps = train_gbt(X, y)
    json.dump({'base': base, 'stumps': stumps, 'threshold': 0.65}, open(OUT, 'w'))
    print('saved →', OUT)


if __name__ == '__main__':
    main()
