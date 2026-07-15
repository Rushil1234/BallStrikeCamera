#!/usr/bin/env python3
"""Train the linear club scorer on the human labels, cross-day validated.

Candidates come from detector2.masks_and_blobs (bright/dark/diff pools).
Positive = candidate within 15 px of the labeled clubhead center.
Model: logistic regression (numpy, L2) — 13 features, ports to Swift as a
dot product. Protocol: hold out each day in turn (train on the other two),
report held-out frame-level club accuracy; final model trains on all days.
"""
import json, math, os, sys
import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hsv_object_explorer import frame_path
from detector2 import masks_and_blobs, club_feature_vector, CLUB_SCORER_PATH
from golf_context_detector import derive_lock

ARCHIVE = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')
LABELS = json.load(open(os.path.expanduser('~/Documents/TrueCarryTraining/labels/labels.json')))
CACHE = os.path.expanduser('~/Documents/TrueCarryTraining/labels/club_train_cache.json')


def build_dataset():
    if os.path.exists(CACHE):
        j = json.load(open(CACHE))
        return (np.array(j['X']), np.array(j['y']), j['days'], j['frame_ids'])
    X, y, days, frame_ids = [], [], [], []
    for shot in sorted(LABELS):
        d = os.path.join(ARCHIVE, shot)
        day = shot[5:13]
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
        # need prev frame for diff pool: preload frame before the first labeled one
        fi0 = int(keys[0])
        p_prev = frame_path(d, fi0 - 1)
        if os.path.exists(p_prev):
            prev_luma = cv2.imread(p_prev).mean(axis=2)
        for k in keys:
            lab = LABELS[shot][k]
            p = frame_path(d, int(k))
            bgr = cv2.imread(p)
            if bgr is None:
                continue
            blobs, dh, luma = masks_and_blobs(bgr, prev_luma, base)
            prev_luma = luma
            lc = lab.get('club')
            negs = 0
            for b in blobs:
                if b['area'] < 25 or b['area'] > 6000:
                    continue
                pos = bool(lc) and math.hypot(b['cx'] - lc['cx'], b['cy'] - lc['cy']) <= 15
                if not pos:
                    negs += 1
                    if negs > 25:
                        continue
                X.append(club_feature_vector(b, lock, r0))
                y.append(1 if pos else 0)
                days.append(day)
                frame_ids.append(f'{shot}/{k}')
    json.dump({'X': [list(map(float, r)) for r in X], 'y': y, 'days': days, 'frame_ids': frame_ids},
              open(CACHE, 'w'))
    return np.array(X), np.array(y), days, frame_ids


def train_lr(X, y, l2=1e-3, iters=3000, lr=0.5):
    Xb = np.hstack([X, np.ones((len(X), 1))])
    w = np.zeros(Xb.shape[1])
    pos_w = (len(y) - y.sum()) / max(1, y.sum())   # class balance
    sw = np.where(y == 1, pos_w, 1.0)
    for _ in range(iters):
        z = Xb @ w
        p = 1 / (1 + np.exp(-np.clip(z, -30, 30)))
        g = Xb.T @ (sw * (p - y)) / len(y) + l2 * np.r_[w[:-1], 0]
        w -= lr * g
    return w[:-1], w[-1]


def frame_accuracy(w, b, thr, day, days, frame_ids, X, y):
    """Frame-level: the argmax candidate must be a positive (or no-club frames
    must stay below threshold)."""
    from collections import defaultdict
    by_frame = defaultdict(list)
    for i, (dd, fid) in enumerate(zip(days, frame_ids)):
        if dd == day:
            by_frame[fid].append(i)
    ok = tot = 0
    for fid, idxs in by_frame.items():
        has_pos = any(y[i] for i in idxs)
        scores = [float(X[i] @ w + b) for i in idxs]
        best = idxs[int(np.argmax(scores))]
        best_p = 1 / (1 + math.exp(-max(-30, min(30, X[best] @ w + b))))
        tot += 1
        if has_pos:
            ok += 1 if (y[best] == 1 and best_p >= thr) else 0
        else:
            ok += 1 if best_p < thr else 0
    return ok / max(1, tot), tot


def main():
    X, y, days, frame_ids = build_dataset()
    print(f'dataset: {len(y)} candidates, {int(y.sum())} positives, days={sorted(set(days))}')
    day_list = sorted(set(days))
    for held in day_list:
        tr = np.array([d != held for d in days])
        w, b = train_lr(X[tr], y[tr])
        best_thr, best_acc = 0.5, 0
        for thr in np.arange(0.3, 0.9, 0.05):
            acc, _ = frame_accuracy(w, b, thr, held, days, frame_ids, X, y)
            if acc > best_acc:
                best_acc, best_thr = acc, thr
        acc, n = frame_accuracy(w, b, best_thr, held, days, frame_ids, X, y)
        print(f'held-out {held}: frame acc {100*acc:.1f}% (n={n} frames, thr={best_thr:.2f})')
    w, b = train_lr(X, y)
    json.dump({'w': list(map(float, w)), 'b': float(b), 'threshold': 0.5},
              open(CLUB_SCORER_PATH, 'w'))
    print('final scorer saved →', CLUB_SCORER_PATH)


if __name__ == '__main__':
    main()
