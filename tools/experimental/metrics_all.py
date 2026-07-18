#!/usr/bin/env python3
"""All-data metric head retrain — TT-primary (Noah, July 17).

Rows from every paired session: July-12 white (Garmin), July-16 yellow (TT),
July-17 yellow (TT + Garmin, exclusions applied). Target = TopTracer where
present, else Garmin. Detector tracks come from the v2.6 replay results.
Exports ball/vla/club heads in the tc_v2_models.json format.
"""
import json, math, os, sys
import numpy as np

sys.path.insert(0, '/Users/noahtobias/Downloads/BallStrikeCamera/tools/experimental')
import metrics_kfold as mk

SCRATCH = os.path.dirname(os.path.abspath(__file__))
TRAIN = os.path.expanduser('~/Documents/TrueCarryTraining')
LABELS = json.load(open(os.path.join(TRAIN, 'labels/labels.json')))
EXCLUDED = set(json.load(open(os.path.join(TRAIN, 'session_2026-07-17/excluded_shots.json'))))
D2R = 131.8678  # replay 'd' -> label-space radius px (empirical fit, July 17)

SESSIONS = [
    dict(name='jul12',
         archive=os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive'),
         pairs=os.path.join(TRAIN, 'session_2026-07-12/pairs.json'),
         results=None),  # uses predictions_v2.json via mk.PREDS
    dict(name='jul16',
         archive=os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260716/AllFramesArchive'),
         pairs=os.path.join(TRAIN, 'session_2026-07-16/pairs.json'),
         results=os.path.join(SCRATCH, 'yellow_v26')),
    dict(name='jul17',
         archive=os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260717/AllFramesArchive'),
         pairs=os.path.join(TRAIN, 'session_2026-07-17/pairs.json'),
         results=os.path.join(SCRATCH, 'jul17_v26')),
]


def targets_from_pair(p):
    """(ball_mph, vla_deg, club_mph, club_type) — TT primary, Garmin fallback."""
    if 'tt_ball_mph' in p:            # July-16 format
        return p.get('tt_ball_mph'), p.get('launch_deg'), None, p.get('club', '?')
    if 'toptracer' in p or 'garmin' in p:   # July-17 format
        tt, gm = p.get('toptracer') or {}, p.get('garmin') or {}
        ball = tt.get('ball_mph') or gm.get('ball_mph')
        vla = tt.get('launch') if tt.get('launch') is not None else gm.get('launch')
        club = tt.get('club_mph') or gm.get('club_mph')
        return ball, vla, club, p.get('club', '?')
    return p.get('garmin_ball_mph'), p.get('garmin_launch'), p.get('garmin_club_mph'), p.get('club', '?')


def det_tracks_from_replay(rp, r0):
    ball, club = {}, {}
    for f in rp.get('frames') or []:
        if f.get('cx') is None:
            continue
        rs = f.get('reason', '')
        if 'flight' in rs or 'gap_fill' in rs:
            r = f['d'] * D2R if f.get('d') else r0
            ball[f['i']] = (f['cx'] * 360.0, f['cy'] * 203.0, r)
    for c in rp.get('club') or []:
        if c.get('cx') is not None:
            club[c['i']] = (c['cx'] * 360.0, c['cy'] * 203.0)
    return ball, club


def build_all_rows():
    rows = []
    for sess in SESSIONS:
        mk.ARCHIVE = sess['archive']
        pairs = json.load(open(sess['pairs']))
        for p in pairs:
            shot = p.get('shot')
            if not shot or shot in EXCLUDED or shot not in LABELS:
                continue
            ball_t, vla_t, club_t, club_type = targets_from_pair(p)
            if not ball_t:
                continue
            frames = LABELS[shot]
            imp, lock_b = mk.label_impact(frames)
            if imp is None:
                continue
            lock = (lock_b['cx'], lock_b['cy'])
            r0 = max(4.0, lock_b.get('r', 8))
            ts = mk.ts_of(shot)
            oracle_ball = {int(k): (f['ball']['cx'], f['ball']['cy'], f['ball'].get('r', r0))
                           for k, f in frames.items() if f.get('ball')}
            oracle_club = {int(k): (f['club']['cx'], f['club']['cy'])
                           for k, f in frames.items() if f.get('club')}
            if sess['results']:
                rp_path = os.path.join(sess['results'], shot + '.json')
                if not os.path.exists(rp_path):
                    continue
                rp = json.load(open(rp_path))
                det_ball, det_club = det_tracks_from_replay(rp, r0)
                det_imp = rp.get('impactDetected', imp)
            else:
                det = mk.PREDS.get(shot, {})
                det_ball = {int(k): (e['ball']['cx'], e['ball']['cy'], e['ball'].get('r', r0))
                            for k, e in det.items() if e.get('ball')}
                det_club = {int(k): (e['club']['cx'], e['club']['cy'])
                            for k, e in det.items() if e.get('club')}
                det_imp = imp
            r_lock_sub = mk.lock_radius_precise(shot, frames, lock, r0, imp)
            fo = mk.features_from_track(oracle_ball, oracle_club, lock, r0, ts, imp,
                                        shot=shot, r_lock_sub=r_lock_sub)
            fd = mk.features_from_track(det_ball, det_club, lock, r0, ts, det_imp,
                                        shot=shot, r_lock_sub=r_lock_sub)
            rows.append({'shot': shot, 'session': sess['name'], 'club_type': club_type,
                         'y_ball': ball_t, 'y_vla': vla_t, 'y_club': club_t,
                         'oracle': fo, 'detector': fd})
    return rows


def matrix(rows, kind, target, feats):
    X, y, keep = [], [], []
    for r in rows:
        f = r[kind]
        if f is None or not r[target]:
            continue
        X.append([f.get(k, 0.0) or 0.0 for k in feats])
        y.append(r[target])
        keep.append(r)
    return np.array(X, float), np.array(y, float), keep


def fit_head(X, y, alpha=1.0):
    mu, sd = X.mean(0), X.std(0) + 1e-9
    Xn = (X - mu) / sd
    A = Xn.T @ Xn + alpha * np.eye(X.shape[1])
    w = np.linalg.solve(A, Xn.T @ (y - y.mean()))
    return dict(mu=mu.tolist(), sd=sd.tolist(), w=w.tolist(), intercept=float(y.mean()))


def main():
    rows = build_all_rows()
    n_by = {}
    for r in rows:
        n_by[r['session']] = n_by.get(r['session'], 0) + 1
    print(f'rows: {len(rows)}  by session: {n_by}')

    bundle_p = '/Users/noahtobias/Downloads/BallStrikeCamera/BallStrikeCamera/Resources/Models/tc_v2_models.json'
    bundle = json.load(open(bundle_p))
    F_BALL = bundle['ball_head']['features']
    F_VLA = bundle['vla_head']['features']
    F_CLUB = bundle['club_head']['features']

    for target, feats, head_key in (('y_ball', F_BALL, 'ball_head'),
                                    ('y_vla', F_VLA, 'vla_head'),
                                    ('y_club', F_CLUB, 'club_head')):
        for kind in ('detector',):
            X, y, keep = matrix(rows, kind, target, feats)
            if len(y) < 25:
                print(f'{head_key}: only {len(y)} rows — skipped')
                continue
            clubs = [r['club_type'] for r in keep]
            rel = mk.ridge_cv(X, y, clubs)
            print(f'{head_key} {kind} CV (n={len(y)}): median {np.median(rel):.1f}%  '
                  f'<=2%: {100*(rel<=2).mean():.0f}%  <=5%: {100*(rel<=5).mean():.0f}%')
            head = fit_head(X, y)
            head['features'] = feats
            if 'clamp' in bundle[head_key]:
                head['clamp'] = bundle[head_key]['clamp']
            bundle[head_key] = head
    bundle['version'] = 'v2.7-20260717'
    bundle['notes'] = (bundle.get('notes') or '') + ' | v2.7: metric heads refit on all paired sessions (jul12 Garmin, jul16 TT, jul17 TT+Garmin), TT primary'
    json.dump(bundle, open(bundle_p, 'w'), indent=1)
    print('bundle -> v2.7-20260717')
    json.dump([{k: v for k, v in r.items()} for r in rows],
              open(os.path.join(SCRATCH, 'metric_rows_all.json'), 'w'), default=str)


if __name__ == '__main__':
    main()
