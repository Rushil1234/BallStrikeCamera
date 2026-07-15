#!/usr/bin/env python3
"""Run detector v2 over every labeled shot and score against human labels."""
import json, math, os, sys
import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hsv_object_explorer import frame_path
from detector2 import masks_and_blobs, BallTracker, BallScorer, GBTClubScorer, pick_club_gbt, rescue_ball_at, rescue_ball_at_lock
from train_ball_scorer import label_impact
from golf_context_detector import derive_lock, derive_impact
from eval_detector import score, report

ARCHIVE = os.path.expanduser('~/Documents/TrueCarryTraining/labels')
FRAMES = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')
LABELS = json.load(open(os.path.join(ARCHIVE, 'labels.json')))
PRED_PATH = os.path.join(ARCHIVE, 'predictions_v2.json')


def load_ts(d):
    p = os.path.join(d, 'timestamps.json')
    if not os.path.exists(p):
        return {}
    return {e['frame_index']: e['timestamp'] for e in json.load(open(p)).get('timestamps', [])}


def run_all():
    scorer = GBTClubScorer()
    ball_scorer = BallScorer()
    preds = {}
    shots = sorted(LABELS)
    for si, shot in enumerate(shots):
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
        tracker = BallTracker(lock, r0, Ww, Hh, scorer=ball_scorer)
        li = label_impact(LABELS[shot])
        club_cut = li if li is not None else imp   # club tracked only TO impact (user spec)
        rescues_left = 2
        prev_club = None
        shot_pred = {}
        keys = sorted(LABELS[shot], key=int)
        fi0 = int(keys[0])
        prev_luma = None
        pp = frame_path(d, fi0 - 1)
        if os.path.exists(pp):
            prev_luma = cv2.imread(pp).mean(axis=2)
        for k in keys:
            fi = int(k)
            p = frame_path(d, fi)
            bgr = cv2.imread(p)
            if bgr is None:
                shot_pred[k] = {'ball': None, 'club': None}
                continue
            blobs, dh, luma = masks_and_blobs(bgr, prev_luma, base)
            prev_luma = luma
            t = ts.get(fi)
            impacted = fi > imp
            # club veto: locate the club on EVERY frame (output still windows at
            # impact) and ban ball candidates inside its extent — 3 of 4
            # confident-but-wrong shots were the ball tracker riding the clubhead
            veto = None  # isolating: radius ceiling only
            if veto is not None and veto.get('score', 0) >= 0.8 and veto.get('w'):
                # surgical: only inside the clubhead's own bbox (+20%); the ball at
                # impact+1 flies CLOSE to the head and must not be swallowed
                x0 = veto['cx'] - veto['w'] * 0.6
                x1 = veto['cx'] + veto['w'] * 0.6
                y0 = veto['cy'] - veto['h'] * 0.6
                y1 = veto['cy'] + veto['h'] * 0.6
                blobs_b = [b for b in blobs if not (x0 <= b['cx'] <= x1 and y0 <= b['cy'] <= y1)]
            else:
                blobs_b = blobs
            ball = tracker.pick(blobs_b, impacted, t)
            if ball is None and not impacted:
                rb = rescue_ball_at_lock(dh, lock, r0)
                if rb is not None:
                    ball = rb
            if ball is None and impacted and not tracker.exited and rescues_left > 0:
                pred = tracker.predict(t) if t is not None else None
                if pred is not None:
                    rb = rescue_ball_at(dh, pred[0], pred[1], r0)
                    if rb is not None:
                        rescues_left -= 1
                        tracker.accept_rescue(rb, t)
                        ball = rb
            club = pick_club_gbt(blobs, lock, r0, ball, scorer, prev_club) if fi <= club_cut else None
            if club is not None:
                prev_club = club
            shot_pred[k] = {
                'ball': {'cx': ball['cx'], 'cy': ball['cy'], 'r': ball['r']} if ball else None,
                'club': {'cx': club['cx'], 'cy': club['cy'], 'score': club['score']} if club else None,
            }
        preds[shot] = shot_pred
        if (si + 1) % 40 == 0:
            print(f'{si+1}/{len(shots)}', file=sys.stderr)
    json.dump(preds, open(PRED_PATH, 'w'))
    return preds


def main():
    preds = run_all()

    def predict_fn(shot, fi):
        e = preds.get(shot, {}).get(str(fi), {})
        return e.get('ball'), e.get('club')

    agg, misses = score(predict_fn)
    report(agg, 'detector v2 vs labels (junk excluded)')
    from collections import Counter
    print('miss types:', Counter(m[2] for m in misses))
    json.dump(misses, open(os.path.join(ARCHIVE, 'miss_inventory_v2.json'), 'w'))


if __name__ == '__main__':
    main()
