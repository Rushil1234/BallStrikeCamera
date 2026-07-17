#!/usr/bin/env python3
"""Train the linear ball scorer on human labels (teacher-forced state).

Candidates: bright-pool blobs (plus loose-threshold rescue blobs near the
label-state prediction). State features (prediction distance, direction
deviation, progress) are computed from the LABELED track up to the previous
frame — teacher forcing — so the scorer learns selection given honest state.
Cross-day validation like the club scorer; exports JSON weights.
"""
import json, math, os, sys
import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hsv_object_explorer import frame_path
from detector2 import masks_and_blobs
from golf_context_detector import derive_lock

ARCHIVE = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')
ARCHIVE_0716 = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260716/AllFramesArchive')
LABELS = json.load(open(os.path.expanduser('~/Documents/TrueCarryTraining/labels/labels.json')))
CACHE = os.path.expanduser('~/Documents/TrueCarryTraining/labels/ball_train_cache_v6.json')


def shot_dir(shot):
    d = os.path.join(ARCHIVE, shot)
    return d if os.path.isdir(d) else os.path.join(ARCHIVE_0716, shot)
OUT = os.path.expanduser('~/Documents/TrueCarryTraining/labels/ball_scorer.json')

# mot_norm added July 16: a real range field is littered with static balls that score
# 0.95+ on shape; motion-vs-pre-impact-baseline is what separates them from the flying
# ball (clutter 2-15, real flight 56-98).
# hue_sim/sat_sim (July 16 night): identity match to the LOCKED ball's color — a yellow
# ball can never be confused with the (gray) clubhead or white clutter, and white balls
# get a free consistency check. Lock color = the rest-ball blob's bbox-mean HSV.
BALL_FEATURES = ['circ', 'elong', 'r_ratio', 'dh_norm', 'border', 'dist_pred', 'dev_dir',
                 'progress_step', 'aligned_cos', 'impacted', 'is_rescue', 'mot_norm',
                 'hue_sim', 'sat_sim']


def color_sims(b, lock_hs):
    if not lock_hs:
        return 0.5, 0.5
    dh0 = abs(b.get('h_mean', 0) - lock_hs[0])
    dh0 = min(dh0, 180 - dh0)
    hue_sim = 1.0 - min(dh0, 45.0) / 45.0
    sat_sim = 1.0 - min(abs(b.get('s_mean', 0) - lock_hs[1]), 128.0) / 128.0
    return hue_sim, sat_sim


def ball_feature_vector(b, state, r0, impacted):
    pred = state.get('pred')
    dist_pred = min(math.hypot(b['cx'] - pred[0], b['cy'] - pred[1]) / max(r0, 1), 8.0) / 8.0 if pred else 0.5
    dirn = state.get('dir')
    lock = state['lock']
    vx, vy = b['cx'] - lock[0], b['cy'] - lock[1]
    dist = math.hypot(vx, vy)
    dev = 0.5
    aligned = 0.5
    if dirn and dist > 1e-6:
        du = (vx / dist, vy / dist)
        dev = math.degrees(math.acos(max(-1, min(1, du[0]*dirn[0] + du[1]*dirn[1])))) / 180.0
        axis = (math.cos(b.get('theta', 0)), math.sin(b.get('theta', 0)))
        aligned = abs(axis[0]*dirn[0] + axis[1]*dirn[1])
    prog = state.get('progress', 0.0)
    step = (dist - prog) / max(r0, 1)
    return [
        b['circ'], b['elong'], min(b['r'] / max(r0, 1), 3.0) / 3.0,
        b.get('dh_mean', 200) / 255.0, 1.0 if b['border'] else 0.0,
        dist_pred, dev, max(-2, min(step / 10.0, 2.0)), aligned,
        1.0 if impacted else 0.0, 1.0 if b.get('src') == 'rescue' else 0.0,
        min(b.get('mot', 0.0), 80.0) / 80.0,
        *color_sims(b, state.get('lock_hs')),
    ]


def label_state_sequence(shot, frames_lab, lock, r0):
    """Teacher-forced state before each frame, from labeled ball positions."""
    keys = sorted(frames_lab, key=int)
    ts_p = os.path.join(shot_dir(shot), 'timestamps.json')
    ts = {}
    if os.path.exists(ts_p):
        ts = {e['frame_index']: e['timestamp'] for e in json.load(open(ts_p)).get('timestamps', [])}
    states = {}
    prev = None      # (t, cx, cy)
    prev2 = None
    progress = 0.0
    dirn = None
    for k in keys:
        fi = int(k)
        t = ts.get(fi)
        pred = None
        if prev and prev2 and t and prev[0] > prev2[0]:
            vel = ((prev[1]-prev2[1])/(prev[0]-prev2[0]), (prev[2]-prev2[2])/(prev[0]-prev2[0]))
            if t > prev[0]:
                pred = (prev[1] + vel[0]*(t-prev[0]), prev[2] + vel[1]*(t-prev[0]))
        states[k] = {'lock': lock, 'pred': pred, 'dir': dirn, 'progress': progress}
        b = frames_lab[k].get('ball')
        if b:
            vx, vy = b['cx']-lock[0], b['cy']-lock[1]
            dist = math.hypot(vx, vy)
            progress = max(progress, dist)
            if dist >= r0*2:
                dirn = (vx/dist, vy/dist)
            if t:
                prev2, prev = prev, (t, b['cx'], b['cy'])
    return states


def label_impact(frames_lab):
    lock = None
    for k in sorted(frames_lab, key=int):
        b = frames_lab[k].get('ball')
        if b:
            lock = b
            break
    if not lock:
        return None
    r = max(4, lock.get('r', 8))
    for k in sorted(frames_lab, key=int):
        b = frames_lab[k].get('ball')
        if b and math.hypot(b['cx']-lock['cx'], b['cy']-lock['cy']) >= 1.5*r:
            return int(k) - 1
    return None


def build():
    if os.path.exists(CACHE):
        j = json.load(open(CACHE))
        return np.array(j['X']), np.array(j['y']), j['days'], j['frame_ids']
    X, y, days, fids = [], [], [], []
    for shot in sorted(LABELS):
        d = shot_dir(shot)
        first = cv2.imread(frame_path(d, 0))
        if first is None:
            continue
        Hh, Ww = first.shape[:2]
        meta_p = os.path.join(d, 'metadata.json')
        meta = json.load(open(meta_p)) if os.path.exists(meta_p) else {}
        lock_norm, _ = derive_lock(d, Ww, Hh, meta.get('locked_ball_rect'))
        lock = (lock_norm[0]*Ww, lock_norm[1]*Hh)
        r0 = max(4.0, lock_norm[2]*Ww/2)
        frames_lab = LABELS[shot]
        states = label_state_sequence(shot, frames_lab, lock, r0)
        li = label_impact(frames_lab)
        # lock color: blob matched to the FIRST labeled ball (the rest ball)
        lock_hs = None
        for k0 in sorted(frames_lab, key=int):
            lb0 = frames_lab[k0].get('ball')
            if not lb0:
                continue
            bgr0 = cv2.imread(frame_path(d, int(k0)))
            if bgr0 is None:
                break
            blobs0, _, _ = masks_and_blobs(bgr0, None, None)
            near0 = [b for b in blobs0 if b['src'] == 'bright'
                     and math.hypot(b['cx']-lb0['cx'], b['cy']-lb0['cy']) <= max(6, lb0.get('r', 8))]
            if near0:
                bb = max(near0, key=lambda b: b['area'])
                lock_hs = (bb.get('h_mean', 0), bb.get('s_mean', 0))
            break
        for st in states.values():
            st['lock_hs'] = lock_hs
        pres = []
        for i in range(0, 14, 3):
            p = frame_path(d, i)
            if os.path.exists(p):
                pres.append(cv2.imread(p).mean(axis=2))
        base = np.median(np.stack(pres), axis=0) if len(pres) >= 3 else None
        prev_luma = None
        for k in sorted(frames_lab, key=int):
            fi = int(k)
            bgr = cv2.imread(frame_path(d, fi))
            if bgr is None:
                continue
            blobs, dh, luma = masks_and_blobs(bgr, prev_luma, base)
            prev_luma = luma
            lb = frames_lab[k].get('ball')
            impacted = li is not None and fi > li
            st = states[k]
            negs = 0
            for b in blobs:
                if b['src'] != 'bright' or not (2.0 <= b['r'] <= 24):
                    continue
                pos = bool(lb) and math.hypot(b['cx']-lb['cx'], b['cy']-lb['cy']) <= max(6, lb.get('r', 8))
                # Edge rule (Noah, July 16): half-off-screen balls were deliberately NOT
                # labeled — a near-border blob on a label-less frame may be the real ball,
                # so it must never be a training negative.
                if not pos and (b['cx'] < 10 or b['cx'] > Ww - 10 or b['cy'] < 10 or b['cy'] > Hh - 10):
                    continue
                if not pos:
                    negs += 1
                    if negs > 20:
                        continue
                X.append(ball_feature_vector(b, st, r0, impacted))
                y.append(1 if pos else 0)
                days.append(shot[5:13])
                fids.append(f'{shot}/{k}')
    json.dump({'X': [list(map(float, r)) for r in X], 'y': y, 'days': days, 'frame_ids': fids},
              open(CACHE, 'w'))
    return np.array(X), np.array(y), days, fids


def train_lr(X, y, l2=1e-3, iters=4000, lr=0.5):
    Xb = np.hstack([X, np.ones((len(X), 1))])
    w = np.zeros(Xb.shape[1])
    pos_w = (len(y) - y.sum()) / max(1, y.sum())
    sw = np.where(y == 1, pos_w, 1.0)
    for _ in range(iters):
        z = np.clip(Xb @ w, -30, 30)
        p = 1/(1+np.exp(-z))
        g = Xb.T @ (sw*(p-y))/len(y) + l2*np.r_[w[:-1], 0]
        w -= lr*g
    return w[:-1], w[-1]


def main():
    X, y, days, fids = build()
    print(f'ball dataset: {len(y)} candidates, {int(y.sum())} positives')
    from collections import defaultdict
    for held in sorted(set(days)):
        tr = np.array([d != held for d in days])
        w, b = train_lr(X[tr], y[tr])
        by = defaultdict(list)
        for i, (dd, f) in enumerate(zip(days, fids)):
            if dd == held:
                by[f].append(i)
        ok = tot = 0
        for f, idxs in by.items():
            has = any(y[i] for i in idxs)
            sc = [float(X[i] @ w + b) for i in idxs]
            best = idxs[int(np.argmax(sc))]
            pbest = 1/(1+math.exp(-max(-30, min(30, sc[int(np.argmax(sc))]))))
            tot += 1
            if has:
                ok += 1 if (y[best] and pbest >= 0.5) else 0
            else:
                ok += 1 if pbest < 0.5 else 0
        print(f'held-out {held}: frame acc {100*ok/max(1,tot):.1f}% (n={tot})')
    w, b = train_lr(X, y)
    json.dump({'w': list(map(float, w)), 'b': float(b), 'threshold': 0.5, 'features': BALL_FEATURES},
              open(OUT, 'w'))
    print('saved →', OUT)


if __name__ == '__main__':
    main()
