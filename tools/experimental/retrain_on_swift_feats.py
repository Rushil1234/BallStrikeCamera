#!/usr/bin/env python3
"""Retrain V3 heads on the SWIFT-computed feature vectors (v3feat notes) so the
model sees exactly what the app computes — implementation parity by construction.
Derived VLA features (pxang, r_excess, r_norm, hla_proxy) reconstructed from the
dumped primitives; curve dropped (not derivable, minor contributor).
"""
import json, glob, math, os, re, sys
import numpy as np

SCRATCH = os.path.dirname(os.path.abspath(__file__))
TRAIN = os.path.expanduser('~/Documents/TrueCarryTraining')
CONT = ''
try:
    CONT = open(os.path.join(SCRATCH, 'cont.txt')).read().strip()
except OSError:
    pass
# TC_RESULTS overrides the sim container (container UUIDs rotate; snapshots don't)
RES = os.environ.get('TC_RESULTS') or (CONT + '/Documents/ReplayResults')

truth = {}
for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-17/pairs.json'))):
    tt = p.get('toptracer') or {}
    if tt.get('ball_mph'):
        truth[p['shot']] = dict(v=tt['ball_mph'], vla=tt.get('launch'))
for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-16/pairs.json'))):
    if p.get('tt_ball_mph'):
        truth[p['shot']] = dict(v=p['tt_ball_mph'], vla=p.get('launch_deg'))
EXCLUDED = set(json.load(open(os.path.join(TRAIN, 'session_2026-07-17/excluded_shots.json'))))

pat = re.compile(r'(\w+)=(-?\d+\.?\d*)')
rows = []
for f in sorted(glob.glob(RES + '/shot_2026071[67]*.json')):
    sid = os.path.basename(f)[:-5]
    if sid in EXCLUDED or sid not in truth:
        continue
    d = json.load(open(f))
    note = next((n for n in (d.get('v2Notes') or []) if n.startswith('v3feat:')), None)
    if not note:
        continue
    feat = {k: float(v) for k, v in pat.findall(note)}
    vx, vy = feat['vx'], feat['vy']
    feat['pxang'] = math.degrees(math.atan2(-vy, -vx))
    feat['r_excess'] = feat['r_slope'] - (-abs(vx) * feat['r0'] / 360.0)
    feat['r_norm'] = feat['r_slope'] / max(abs(vx), 1.0) * 100.0
    feat['hla_proxy'] = abs(feat['r_slope']) / max(feat['v_px'], 1.0) * 100.0
    rows.append(dict(shot=sid, feat=feat, tt=truth[sid]))
print(f'rows with swift features + TT truth: {len(rows)}')

F_SPD = ['v_px', 'vx', 'vy', 'v_mps', 'r0', 'r1', 'r_slope', 'y0', 'npts', 'r0_sess', 'r0_rel']
F_VLA = ['v_px', 'vx', 'vy', 'pxang', 'r_slope', 'r_excess', 'r_norm', 'hla_proxy',
         'v_mps', 'r0', 'r1', 'y0', 'npts', 'r0_sess', 'r0_rel']


def cv_and_fit(feats, target):
    keep = [r for r in rows if r['tt'].get(target)]
    X = np.array([[r['feat'].get(k, 0.0) for k in feats] for r in keep])
    y = np.array([r['tt'][target] for r in keep])
    rng = np.random.default_rng(0)
    errs_rel, errs_abs = [], []
    for f in np.array_split(rng.permutation(len(y)), 5):
        te = np.array(sorted(f)); tr = np.array(sorted(set(range(len(y))) - set(f)))
        mu, sd = X[tr].mean(0), X[tr].std(0) + 1e-9
        w = np.linalg.solve(((X[tr]-mu)/sd).T @ ((X[tr]-mu)/sd) + np.eye(X.shape[1]),
                            ((X[tr]-mu)/sd).T @ (y[tr] - y[tr].mean()))
        pred = ((X[te]-mu)/sd) @ w + y[tr].mean()
        errs_rel.extend(np.abs(pred - y[te]) / np.abs(y[te]) * 100)
        errs_abs.extend(np.abs(pred - y[te]))
    mu, sd = X.mean(0), X.std(0) + 1e-9
    w = np.linalg.solve(((X-mu)/sd).T @ ((X-mu)/sd) + np.eye(X.shape[1]),
                        ((X-mu)/sd).T @ (y - y.mean()))
    head = dict(features=feats, mu=mu.tolist(), sd=sd.tolist(), w=w.tolist(),
                intercept=float(y.mean()), n=len(y))
    return head, np.array(errs_rel), np.array(errs_abs)

sp, rel, ab = cv_and_fit(F_SPD, 'v')
print(f'SPEED on swift-feats CV (n={sp["n"]}): median {np.median(rel):.1f}%  '
      f'<=2%: {100*(rel<=2).mean():.0f}%  <=5%: {100*(rel<=5).mean():.0f}%  | abs median {np.median(ab):.1f} mph')
vl, relv, abv = cv_and_fit(F_VLA, 'vla')
print(f'VLA   on swift-feats CV (n={vl["n"]}): median {np.median(abv):.1f} deg  '
      f'<=1deg: {100*(abv<=1).mean():.0f}%  <=2deg: {100*(abv<=2).mean():.0f}%')

out = dict(version='v3heads-swiftfeat-20260718', speed=sp, vla=vl,
           vla_floor=0.5, speed_clamp=[10.0, 210.0], vla_clamp=[0.5, 55.0])
dst = '/Users/noahtobias/Downloads/BallStrikeCamera/BallStrikeCamera/Resources/Models/v3_heads.json'
json.dump(out, open(dst, 'w'), indent=1)
print('exported', dst)
