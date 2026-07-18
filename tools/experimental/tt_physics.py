#!/usr/bin/env python3
"""Learn TT's flight ALGO as physics: 2D ballistic ODE with spin-dependent drag/lift,
parameters fit to TT rows using carry+peak+descent+hang as joint constraints."""
import csv, math
import numpy as np

CSVS = ["/Users/noahtobias/Downloads/BallStrikeCamera/swingsync-2026-07-12.csv",
        "/Users/noahtobias/Downloads/BallStrikeCamera/swingsync-2026-07-16.csv",
        "/Users/noahtobias/Downloads/BallStrikeCamera/swingsync-2026-07-17.csv"]
rows = []
for path in CSVS:
    for r in csv.DictReader(open(path)):
        def fv(k):
            try:
                v = float(r.get(k, ''))
                return None if v == -10000 else v
            except (TypeError, ValueError):
                return None
        d = dict(v=fv('ballSpeed'), vla=fv('launchAngle'), bs=fv('backSpin') or 0.0,
                 ss=fv('sideSpin') or 0.0, carry=fv('carry'), total=fv('total'),
                 peak=fv('peakHeight'), desc=fv('decentAngle'), hang=fv('hangTime'))
        if all(d[k] is not None for k in ('v', 'vla', 'carry')) and d['carry'] > 5 and d['v'] > 20:
            rows.append(d)
print(f'rows: {len(rows)}')

M = 0.04593
R = 0.02134
A = math.pi * R * R
RHO = 1.1875          # Garmin-reported air density for these sessions
G = 9.81
MPH = 0.44704
YD = 1.0936133
DT = 0.004
STEPS = 3000

V0 = np.array([d['v'] * MPH for d in rows])
VLA = np.array([math.radians(d['vla']) for d in rows])
W0 = np.array([d['bs'] * 2 * math.pi / 60 for d in rows])          # rad/s backspin
AXIS = np.array([math.atan2(abs(d['ss']), max(d['bs'], 1)) for d in rows])
CARRY = np.array([d['carry'] for d in rows])
PEAK = np.array([d['peak'] if d['peak'] else np.nan for d in rows])
HAS_PEAK = ~np.isnan(PEAK)


def simulate(theta, idx):
    cd0, cd1, cla, clcap, tau = theta
    n = len(idx)
    x = np.zeros(n); y = np.zeros(n)
    vx = V0[idx] * np.cos(VLA[idx]); vy = V0[idx] * np.sin(VLA[idx])
    w = W0[idx].copy()
    axis_cos = np.cos(AXIS[idx])
    alive = np.ones(n, bool)
    carry = np.zeros(n); peak = np.zeros(n)
    for _ in range(STEPS):
        v = np.sqrt(vx * vx + vy * vy) + 1e-9
        S = w * R / v
        cd = cd0 + cd1 * S
        cl = np.minimum(cla * S, clcap) * axis_cos
        q = 0.5 * RHO * A * v / M            # (× v gives dyn pressure / m)
        ax = -q * (cd * vx + cl * (-vy) * -1)      # lift ⟂: rotate v by +90° = (-vy, vx)
        ay = -q * (cd * vy - cl * vx) - G
        # lift direction: perpendicular left of velocity = (-vy, vx)/|v| → for backspin, up
        ax = -q * cd * vx + q * cl * (-vy)
        ay = -q * cd * vy + q * cl * (vx) - G
        vx = np.where(alive, vx + ax * DT, vx)
        vy = np.where(alive, vy + ay * DT, vy)
        x = np.where(alive, x + vx * DT, x)
        y = np.where(alive, y + vy * DT, y)
        peak = np.maximum(peak, y)
        w *= math.exp(-DT / tau)
        landed = alive & (y <= 0) & (vy < 0)
        carry = np.where(landed, x, carry)
        alive = alive & ~landed
        if not alive.any():
            break
    carry = np.where(alive, x, carry)        # cap unlanded
    return carry * YD, peak * YD


def objective(theta, idx):
    c, p = simulate(theta, idx)
    err = np.abs(c - CARRY[idx]).mean()
    hp = HAS_PEAK[idx]
    if hp.any():
        err += 0.5 * np.abs(p[hp] - PEAK[idx][hp]).mean()
    return err


def nelder_mead(f, x0, steps=120, scale=None):
    x0 = np.array(x0, float)
    scale = np.array(scale if scale is not None else np.abs(x0) * 0.3 + 1e-3)
    n = len(x0)
    simplex = [x0] + [x0 + scale * np.eye(n)[i] for i in range(n)]
    vals = [f(np.abs(s)) for s in simplex]
    for _ in range(steps):
        order = np.argsort(vals)
        simplex = [simplex[i] for i in order]
        vals = [vals[i] for i in order]
        centroid = np.mean(simplex[:-1], axis=0)
        refl = centroid + (centroid - simplex[-1])
        fr = f(np.abs(refl))
        if fr < vals[0]:
            exp = centroid + 2 * (centroid - simplex[-1])
            fe = f(np.abs(exp))
            simplex[-1], vals[-1] = (exp, fe) if fe < fr else (refl, fr)
        elif fr < vals[-2]:
            simplex[-1], vals[-1] = refl, fr
        else:
            con = centroid + 0.5 * (simplex[-1] - centroid)
            fc = f(np.abs(con))
            if fc < vals[-1]:
                simplex[-1], vals[-1] = con, fc
            else:
                simplex = [simplex[0] + 0.5 * (s - simplex[0]) for s in simplex]
                vals = [f(np.abs(s)) for s in simplex]
    order = np.argsort(vals)
    return np.abs(simplex[order[0]]), vals[order[0]]


rng = np.random.default_rng(0)
idx_all = rng.permutation(len(rows))
errs = []
theta0 = [0.22, 0.20, 1.20, 0.30, 30.0]
for f_ in np.array_split(idx_all, 5):
    te = np.array(sorted(f_))
    tr = np.array(sorted(set(range(len(rows))) - set(f_)))
    theta, tr_err = nelder_mead(lambda th: objective(th, tr), theta0)
    c, _ = simulate(theta, te)
    errs.extend(np.abs(c - CARRY[te]))
errs = np.array(errs)
print(f'PHYSICS carry CV: MAE {errs.mean():.1f} yd  median {np.median(errs):.1f}  '
      f'<=2yd: {100*(errs<=2).mean():.0f}%  <=4yd: {100*(errs<=4).mean():.0f}%')
theta, e = nelder_mead(lambda th: objective(th, np.arange(len(rows))), theta0, steps=150)
print(f'full-fit params (cd0, cd1, cl_a, cl_cap, tau): {[round(float(t),4) for t in theta]}  train-obj {e:.2f}')
import json
json.dump({'params': [float(t) for t in theta],
           'meaning': ['cd0', 'cd1_perS', 'cl_a_perS', 'cl_cap', 'spin_decay_tau_s'],
           'rho': RHO, 'dt': DT}, open('tt_physics_params.json', 'w'), indent=1)
