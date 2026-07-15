#!/usr/bin/env python3
"""Score a detector configuration against the human labels.

- Junk shots (never a real strike: no labeled ball ever leaves the lock area)
  are excluded from headline numbers — tracking quality there doesn't matter.
- Per-day breakdown, because generalization = training on some days and
  holding out others, never tuning on the day being scored.

Usage: python3 eval_detector.py [--full]   (--full includes junk shots)
"""
import json, math, os, sys
import numpy as np

LABELS = os.path.expanduser('~/Documents/TrueCarryTraining/labels/labels.json')
ARCHIVE = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')


def load_labels():
    return json.load(open(LABELS))


def shot_lock(frames_lab):
    """Approximate lock = ball position in the earliest labeled frame."""
    for k in sorted(frames_lab, key=int):
        b = frames_lab[k].get('ball')
        if b:
            return b
    return None


def is_junk(frames_lab):
    """No labeled ball ever moves >= 2.5 radii from the earliest ball position
    → reposition / false trigger / non-strike. Excluded from headline accuracy."""
    lock = shot_lock(frames_lab)
    if lock is None:
        return True
    r = max(4.0, lock.get('r', 8))
    for f in frames_lab.values():
        b = f.get('ball')
        if b and math.hypot(b['cx'] - lock['cx'], b['cy'] - lock['cy']) >= 2.5 * r:
            return False
    return True


def score(predict_fn, include_junk=False, days=None, progress=False):
    """predict_fn(shot, fi) -> (ball dict|None, club dict|None).
    Returns metrics dict + per-shot miss inventory."""
    labels = load_labels()
    agg = {}
    misses = []
    shots = sorted(labels)
    for si, shot in enumerate(shots):
        frames_lab = labels[shot]
        day = shot[5:13]
        if days and day not in days:
            continue
        if not include_junk and is_junk(frames_lab):
            continue
        li = None
        _lock0 = shot_lock(frames_lab)
        if _lock0:
            _r = max(4, _lock0.get('r', 8))
            for _k in sorted(frames_lab, key=int):
                _b = frames_lab[_k].get('ball')
                if _b and math.hypot(_b['cx'] - _lock0['cx'], _b['cy'] - _lock0['cy']) >= 1.5 * _r:
                    li = int(_k) - 1
                    break
        for k, lab in frames_lab.items():
            pred_ball, pred_club = predict_fn(shot, int(k))
            if li is not None and int(k) > li:
                lab = dict(lab)
                lab['club'] = None          # club is only scored up to impact (user spec)
            d = agg.setdefault(day, dict(b_tp=0, b_wrong=0, b_fn=0, b_fp=0, b_tn=0,
                                         c_tp=0, c_wrong=0, c_fn=0, c_fp=0, c_tn=0))
            lb, lc = lab.get('ball'), lab.get('club')
            if lb and pred_ball:
                tol = max(6, lb.get('r', 8))
                if math.hypot(lb['cx'] - pred_ball['cx'], lb['cy'] - pred_ball['cy']) <= tol:
                    d['b_tp'] += 1
                else:
                    d['b_wrong'] += 1
                    misses.append((shot, k, 'ball_wrong'))
            elif lb:
                d['b_fn'] += 1
                misses.append((shot, k, 'ball_missed'))
            elif pred_ball:
                d['b_fp'] += 1
                misses.append((shot, k, 'ball_false'))
            else:
                d['b_tn'] += 1
            if lc and pred_club:
                if math.hypot(lc['cx'] - pred_club['cx'], lc['cy'] - pred_club['cy']) <= 15:
                    d['c_tp'] += 1
                else:
                    d['c_wrong'] += 1
                    misses.append((shot, k, 'club_wrong'))
            elif lc:
                d['c_fn'] += 1
                misses.append((shot, k, 'club_missed'))
            elif pred_club:
                d['c_fp'] += 1
                misses.append((shot, k, 'club_false'))
            else:
                d['c_tn'] += 1
        if progress and (si + 1) % 40 == 0:
            print(f'  scored {si+1}/{len(shots)}', file=sys.stderr)
    return agg, misses


def report(agg, title=''):
    tb = {k: sum(d[k] for d in agg.values()) for k in next(iter(agg.values()))}
    bn = tb['b_tp'] + tb['b_wrong'] + tb['b_fn']
    cn = tb['c_tp'] + tb['c_wrong'] + tb['c_fn']
    print(f"== {title} ==")
    print(f"BALL n={bn}: acc {100*tb['b_tp']/max(1,bn):.1f}%  wrong {tb['b_wrong']}  miss {tb['b_fn']}  false+ {tb['b_fp']}")
    print(f"CLUB n={cn}: acc {100*tb['c_tp']/max(1,cn):.1f}%  wrong {tb['c_wrong']}  miss {tb['c_fn']}  false+ {tb['c_fp']}")
    for day in sorted(agg):
        d = agg[day]
        bn = d['b_tp'] + d['b_wrong'] + d['b_fn']
        cn = d['c_tp'] + d['c_wrong'] + d['c_fn']
        print(f"  {day}: ball {100*d['b_tp']/max(1,bn):.1f}% ({bn})   club {100*d['c_tp']/max(1,cn):.1f}% ({cn})   ballFP {d['b_fp']}  clubFP {d['c_fp']}")


if __name__ == '__main__':
    # score the cached prelabels (the detector as the user reviewed it)
    pre = json.load(open(os.path.expanduser('~/Documents/TrueCarryTraining/labels/prelabels.json')))

    def from_prelabels(shot, fi):
        e = pre.get(shot, {}).get('per_frame', {}).get(str(fi), {})
        return e.get('ball'), e.get('club')

    include_junk = '--full' in sys.argv
    agg, misses = score(from_prelabels, include_junk=include_junk)
    report(agg, 'prelabel detector vs human labels' + (' (ALL shots)' if include_junk else ' (junk excluded)'))
    from collections import Counter
    print('\nmiss types:', Counter(m[2] for m in misses))
    json.dump(misses, open(os.path.expanduser('~/Documents/TrueCarryTraining/labels/miss_inventory.json'), 'w'))
