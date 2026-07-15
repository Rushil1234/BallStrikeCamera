#!/usr/bin/env python3
"""Detector v3 eval: global ballistic path search over per-frame candidates."""
import json, math, os, sys
import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hsv_object_explorer import frame_path
from detector2 import (masks_and_blobs, BallScorer, GBTClubScorer, pick_club_gbt,
                       rescue_ball_at_lock)
from train_ball_scorer import ball_feature_vector, label_impact
from track_optimizer import best_ball_path
from golf_context_detector import derive_lock, derive_impact
from eval_detector import score, report

FRAMES = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')
LABELS = json.load(open(os.path.expanduser('~/Documents/TrueCarryTraining/labels/labels.json')))
OUT = os.path.expanduser('~/Documents/TrueCarryTraining/labels/predictions_v3.json')


def load_ts(d):
    p = os.path.join(d, 'timestamps.json')
    if not os.path.exists(p):
        return {}
    return {e['frame_index']: e['timestamp'] for e in json.load(open(p)).get('timestamps', [])}


def run_all():
    club_scorer = GBTClubScorer()
    ball_scorer = BallScorer()
    preds = {}
    for si, shot in enumerate(sorted(LABELS)):
        d = os.path.join(FRAMES, shot)
        first = cv2.imread(frame_path(d, 0))
        if first is None:
            continue
        Hh, Ww = first.shape[:2]
        meta_p = os.path.join(d, 'metadata.json')
        meta = json.load(open(meta_p)) if os.path.exists(meta_p) else {}
        lock_norm, _ = derive_lock(d, Ww, Hh, meta.get('locked_ball_rect'))
        lock = (lock_norm[0] * Ww, lock_norm[1] * Hh)
        r0 = max(4.0, lock_norm[2] * Ww / 2)
        ts = load_ts(d)
        pres = []
        for i in range(0, 14, 3):
            p = frame_path(d, i)
            if os.path.exists(p):
                pres.append(cv2.imread(p).mean(axis=2))
        base = np.median(np.stack(pres), axis=0) if len(pres) >= 3 else None
        imp, _ = derive_impact(d, lock, r0, base, 20, Ww, Hh)
        li = label_impact(LABELS[shot])
        club_cut = (li if li is not None else imp) + 1

        keys = sorted(LABELS[shot], key=int)
        state0 = {'lock': lock, 'pred': None, 'dir': None, 'progress': 0.0}
        per_frame_blobs = {}
        prev_luma = None
        pp = frame_path(d, int(keys[0]) - 1)
        if os.path.exists(pp):
            prev_luma = cv2.imread(pp).mean(axis=2)
        dhs = {}
        for k in keys:
            fi = int(k)
            bgr = cv2.imread(frame_path(d, fi))
            if bgr is None:
                per_frame_blobs[fi] = ([], None)
                continue
            blobs, dh, luma = masks_and_blobs(bgr, prev_luma, base)
            prev_luma = luma
            dhs[fi] = dh
            per_frame_blobs[fi] = (blobs, dh)

        # ── pre-impact ball: rest pick (+ merge rescue), unchanged from v2
        shot_pred = {}
        for k in keys:
            fi = int(k)
            blobs, dh = per_frame_blobs.get(fi, ([], None))
            ball = None
            if fi <= imp:
                cands = [b for b in blobs if b['src'] == 'bright' and 2.0 <= b['r'] <= 24
                         and b['area'] >= 12 and not b['border'] and b['circ'] >= 0.5
                         and math.hypot(b['cx'] - lock[0], b['cy'] - lock[1]) <= r0 * 2.2]
                if cands:
                    ball = max(cands, key=lambda b: b['circ'])
                elif dh is not None:
                    ball = rescue_ball_at_lock(dh, lock, r0)
            shot_pred[str(fi)] = {'ball': ({'cx': ball['cx'], 'cy': ball['cy'], 'r': ball['r']}
                                           if ball else None), 'club': None}

        # ── post-impact ball: GLOBAL ballistic path over candidates
        frame_cands = []
        for k in keys:
            fi = int(k)
            if fi <= imp:
                continue
            t = ts.get(fi)
            if t is None:
                continue
            blobs, dh = per_frame_blobs.get(fi, ([], None))
            cs = []
            for b in blobs:
                if b['src'] != 'bright' or not (2.0 <= b['r'] <= 24) or b['area'] < 12:
                    continue
                vx = b['cx'] - lock[0]
                dist = math.hypot(vx, b['cy'] - lock[1])
                if dist >= r0 * 1.5 and vx > 0:   # backwards (flight is -x here)
                    continue
                bb = dict(b)
                bb['prob'] = ball_scorer.prob(ball_feature_vector(b, state0, r0, True))
                if bb['prob'] >= 0.25:
                    cs.append(bb)
            frame_cands.append((t, cs))
            frame_cands_fis = None
        fis_post = [int(k) for k in keys if int(k) > imp and ts.get(int(k)) is not None]
        path = best_ball_path(frame_cands, lock, r0)
        t_to_fi = {ts[fi]: fi for fi in fis_post}
        for t, c in path:
            fi = t_to_fi.get(t)
            if fi is not None:
                shot_pred[str(fi)]['ball'] = {'cx': c['cx'], 'cy': c['cy'], 'r': c['r']}

        # ── club: per-frame GBT with self-forced continuity (window: label impact)
        prev_club = None
        for k in keys:
            fi = int(k)
            if fi > club_cut:
                break
            blobs, dh = per_frame_blobs.get(fi, ([], None))
            ball_here = shot_pred[str(fi)]['ball']
            club = pick_club_gbt(blobs, lock, r0, ball_here, club_scorer, prev_club)
            if club is not None:
                prev_club = club
                shot_pred[str(fi)]['club'] = {'cx': club['cx'], 'cy': club['cy'], 'score': club['score']}
        preds[shot] = shot_pred
        if (si + 1) % 40 == 0:
            print(f'{si+1}/223', file=sys.stderr)
    json.dump(preds, open(OUT, 'w'))
    return preds


def main():
    preds = run_all()

    def predict_fn(shot, fi):
        e = preds.get(shot, {}).get(str(fi), {})
        return e.get('ball'), e.get('club')

    agg, misses = score(predict_fn)
    report(agg, 'detector v3 (global ballistic path) vs labels')
    from collections import Counter
    print('miss types:', Counter(m[2] for m in misses))


if __name__ == '__main__':
    main()
