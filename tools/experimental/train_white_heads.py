#!/usr/bin/env python3
"""Train WHITE speed/VLA heads on Swift feature dumps with TT-NORMALIZED Garmin
targets (Noah's cross-calibration): speed = Garmin (identity — sensors agree 0.67%),
launch_TT = 0.912*G - 3.88 (residual 5.97 -> 0.81 deg on 54 dual pairs).
Merges into v3_heads.json alongside the yellow heads.
"""
import json, glob, math, os, re
import numpy as np

SCRATCH = os.path.dirname(os.path.abspath(__file__))
TRAIN = os.path.expanduser('~/Documents/TrueCarryTraining')
CONT = open(os.path.join(SCRATCH, 'cont.txt')).read().strip()
RES = CONT + '/Documents/ReplayResults'
conv = json.load(open(os.path.join(TRAIN, 'garmin_to_tt.json')))
a_l, b_l = conv['launch']['a'], conv['launch']['b']

# launch truth via garmin_idx (pairs carry ball speed only). garmin_idx indexes
# garmin_small.csv THEN garmin_main.csv, date-filtered rows, concatenated \u2014
# verified 103/103 on ball speed July 20. The original main-only read here
# shifted every launch target by 9 rows (white VLA head trained on wrong truth).
import csv
grows = []
for _name in ('garmin_small.csv', 'garmin_main.csv'):
    _p = os.path.join(TRAIN, 'session_2026-07-12', _name)
    if not os.path.exists(_p):
        continue
    with open(_p) as f:
        for r in csv.DictReader(f):
            date = r.get('\ufeffDate') or r.get('Date')
            if not date or '/' not in date:
                continue
            try:
                grows.append(dict(ball=float(r['Ball Speed']), launch=float(r['Launch Angle'])))
            except (ValueError, KeyError):
                grows.append(dict(ball=None, launch=None))
truth = {}
for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-12/pairs.json'))):
    shot = p.get('shot')
    g = p.get('garmin_ball_mph')
    gi = p.get('garmin_idx')
    gl = grows[gi]['launch'] if gi is not None and gi < len(grows) else None
    if shot and g:
        truth[shot] = dict(v=g, vla=(a_l * gl + b_l) if gl is not None else None)

pat = re.compile(r'(\w+)=(-?\d+\.?\d*)')
rows = []
for f in sorted(glob.glob(RES + '/shot_2026071[012]*.json')):
    sid = os.path.basename(f)[:-5]
    if sid not in truth:
        continue
    d = json.load(open(f))
    notes = d.get('v2Notes') or []
    note = next((n for n in notes if n.startswith('v3feat:')), None)
    ball = next((n for n in notes if n.startswith('ball=')), '')
    if not note or 'ball=white' not in ball:
        continue
    feat = {k: float(v) for k, v in pat.findall(note)}
    vx, vy = feat['vx'], feat['vy']
    feat['pxang'] = math.degrees(math.atan2(-vy, -vx))
    feat['r_excess'] = feat['r_slope'] - (-abs(vx) * feat['r0'] / 360.0)
    feat['r_norm'] = feat['r_slope'] / max(abs(vx), 1.0) * 100.0
    feat['hla_proxy'] = abs(feat['r_slope']) / max(feat['v_px'], 1.0) * 100.0
    rows.append(dict(shot=sid, feat=feat, tt=truth[sid]))
print(f'white rows: {len(rows)}')

F_SPD = ['v_px', 'vx', 'vy', 'v_mps', 'r0', 'r1', 'r_slope', 'y0', 'npts', 'r0_sess', 'r0_rel']
F_VLA = ['v_px', 'vx', 'vy', 'pxang', 'r_slope', 'r_excess', 'r_norm', 'hla_proxy',
         'v_mps', 'r0', 'r1', 'y0', 'npts', 'r0_sess', 'r0_rel']


def cv_and_fit(feats, target, absolute=False):
    keep = [r for r in rows if r['tt'].get(target)]
    if len(keep) < 15:
        print(f'{target}: only {len(keep)} rows — skipping')
        return None, np.array([])
    X = np.array([[r['feat'].get(k, 0.0) for k in feats] for r in keep])
    y = np.array([r['tt'][target] for r in keep])
    rng = np.random.default_rng(0)
    errs = []
    for f in np.array_split(rng.permutation(len(y)), 5):
        te = np.array(sorted(f)); tr = np.array(sorted(set(range(len(y))) - set(f)))
        mu, sd = X[tr].mean(0), X[tr].std(0) + 1e-9
        w = np.linalg.solve(((X[tr]-mu)/sd).T @ ((X[tr]-mu)/sd) + np.eye(X.shape[1]),
                            ((X[tr]-mu)/sd).T @ (y[tr] - y[tr].mean()))
        pred = ((X[te]-mu)/sd) @ w + y[tr].mean()
        errs.extend(np.abs(pred - y[te]) if absolute else np.abs(pred - y[te]) / np.abs(y[te]) * 100)
    mu, sd = X.mean(0), X.std(0) + 1e-9
    w = np.linalg.solve(((X-mu)/sd).T @ ((X-mu)/sd) + np.eye(X.shape[1]),
                        ((X-mu)/sd).T @ (y - y.mean()))
    return dict(features=feats, mu=mu.tolist(), sd=sd.tolist(), w=w.tolist(),
                intercept=float(y.mean()), n=len(y)), np.array(errs)

sp, e = cv_and_fit(F_SPD, 'v')
if sp: print(f'WHITE speed CV (n={sp["n"]}): median {np.median(e):.1f}%  <=3%: {100*(e<=3).mean():.0f}%  <=5%: {100*(e<=5).mean():.0f}%')
vl, ev = cv_and_fit(F_VLA, 'vla', absolute=True)
if vl: print(f'WHITE VLA CV (n={vl["n"]}): median {np.median(ev):.1f} deg (TT-normalized)  <=1: {100*(ev<=1).mean():.0f}%  <=2: {100*(ev<=2).mean():.0f}%')

dst = '/Users/noahtobias/Downloads/BallStrikeCamera/BallStrikeCamera/Resources/Models/v3_heads.json'
heads = json.load(open(dst))
if sp: heads['speed_white'] = sp
if vl: heads['vla_white'] = vl
heads['version'] = 'v3heads-color-20260718'
json.dump(heads, open(dst, 'w'), indent=1)
print('merged white heads into', dst)
