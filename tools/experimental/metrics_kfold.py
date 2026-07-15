#!/usr/bin/env python3
"""Metric model, k-fold validated: detector/oracle track features → Garmin.

Feature extraction is dt-exact (timestamps.json). Speeds come from a robust
straight-line fit over the flight points (the flight is a line at this
horizon): least-squares over t→(x,y), refit after dropping the worst residual
when 4+ points. 'Oracle' features use the human-labeled ball positions —
that's the tracking-perfection ceiling; the detector column is what ships.

Model per target: ridge regression on [v_px_s, 1/r_px, v*(0.02134/r), angle,
first_step, n_pts, club_v] with 5-fold CV stratified by club, plus a
GBT-stumps variant; report median/mean absolute relative error per fold.
"""
import json, math, os, sys
import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hsv_object_explorer import frame_path
from hue_dist_gallery import hue_dist
from track_optimizer import weighted_fit, impact_time, arc_club_speed, smash_gate

SESSION = os.path.expanduser('~/Documents/TrueCarryTraining/session_2026-07-12')
LABELS = json.load(open(os.path.expanduser('~/Documents/TrueCarryTraining/labels/labels.json')))
PREDS = json.load(open(os.path.expanduser('~/Documents/TrueCarryTraining/labels/predictions_v2.json')))
ARCHIVE = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')
BALL_M = 0.04267


def ts_of(shot):
    p = os.path.join(ARCHIVE, shot, 'timestamps.json')
    if not os.path.exists(p):
        return {}
    return {e['frame_index']: e['timestamp'] for e in json.load(open(p)).get('timestamps', [])}


def label_impact(frames):
    lock = None
    for k in sorted(frames, key=int):
        b = frames[k].get('ball')
        if b:
            lock = b
            break
    if not lock:
        return None, None
    r = max(4, lock.get('r', 8))
    for k in sorted(frames, key=int):
        b = frames[k].get('ball')
        if b and math.hypot(b['cx'] - lock['cx'], b['cy'] - lock['cy']) >= 1.5 * r:
            return int(k) - 1, lock
    return None, lock


def robust_speed(pts):
    """pts: [(t, x, y)] → (v_px_s, angle_deg) via LSQ line, one-residual trim."""
    if len(pts) < 2:
        return None, None
    def fit(P):
        T = np.array([p[0] for p in P]); T = T - T[0]
        X = np.array([p[1] for p in P]); Y = np.array([p[2] for p in P])
        if np.ptp(T) < 1e-4:
            return None
        vx = np.polyfit(T, X, 1)[0]; vy = np.polyfit(T, Y, 1)[0]
        rx = X - np.polyval(np.polyfit(T, X, 1), T)
        ry = Y - np.polyval(np.polyfit(T, Y, 1), T)
        res = np.hypot(rx, ry)
        return vx, vy, res
    out = fit(pts)
    if out is None:
        return None, None
    vx, vy, res = out
    if len(pts) >= 4 and res.max() > 4:
        pts2 = [p for i, p in enumerate(pts) if i != int(np.argmax(res))]
        out2 = fit(pts2)
        if out2 is not None:
            vx, vy, _ = out2
    return float(math.hypot(vx, vy)), float(math.degrees(math.atan2(-vy, -vx)))


_dh_cache = {}

def dh_frame(shot, fi):
    key = (shot, fi)
    if key not in _dh_cache:
        bgr = cv2.imread(frame_path(os.path.join(ARCHIVE, shot), fi))
        _dh_cache[key] = hue_dist(bgr)[0] if bgr is not None else None
        if len(_dh_cache) > 400:
            _dh_cache.pop(next(iter(_dh_cache)))
    return _dh_cache[key]


def refine_subpixel(shot, fi, cx, cy, r_hint):
    """Weighted-centroid subpixel center + effective radius from the dh patch."""
    dh = dh_frame(shot, fi)
    if dh is None:
        return cx, cy, r_hint
    H, W = dh.shape
    R = int(max(6, r_hint * 2.2))
    x0, x1 = max(0, int(cx - R)), min(W, int(cx + R))
    y0, y1 = max(0, int(cy - R)), min(H, int(cy + R))
    patch = dh[y0:y1, x0:x1].astype(np.float64)
    wgt = np.clip(patch - 120, 0, None)
    tot = wgt.sum()
    if tot < 1:
        return cx, cy, r_hint
    ys, xs = np.mgrid[y0:y1, x0:x1]
    scx = float((xs * wgt).sum() / tot)
    scy = float((ys * wgt).sum() / tot)
    area = float((wgt > 30).sum())
    sr = math.sqrt(area / math.pi) if area >= 6 else r_hint
    return scx, scy, sr


def lock_radius_precise(shot, frames_lab, lock, r0, imp):
    """Median subpixel radius of the resting ball over pre-impact frames."""
    rs = []
    for k in sorted(frames_lab, key=int):
        fi = int(k)
        if fi > imp:
            break
        b = frames_lab[k].get('ball')
        if not b:
            continue
        _, _, sr = refine_subpixel(shot, fi, b['cx'], b['cy'], b.get('r', r0))
        rs.append(sr)
    return float(np.median(rs)) if rs else r0


def features_from_track(ball_pts, club_pts, lock, r0, ts, imp, shot=None, r_lock_sub=None):
    """ball_pts: {fi: (cx,cy,r)}; flight = points ≥1 r0 from lock after imp."""
    flight = []
    radii = []
    for fi in sorted(ball_pts):
        cx, cy, r = ball_pts[fi]
        t = ts.get(fi)
        if t is None or fi <= imp:
            continue
        d = math.hypot(cx - lock[0], cy - lock[1])
        if d < r0:
            continue
        if shot is not None:
            cx, cy, r = refine_subpixel(shot, fi, cx, cy, r)
        flight.append((t, cx, cy))
        radii.append(r)
    flight = flight[:5]
    radii = radii[:5]
    # PHYSICS: a ball in flight never reads BIGGER than its rest self — oversized
    # far-field points are the clubhead riding the track. Filter from the FIT
    # (tracking picks stay untouched); withholding beats fitting a club point.
    if r_lock_sub:
        keep_i = [i for i in range(len(flight))
                  if radii[i] <= r_lock_sub * 1.35
                  or math.hypot(flight[i][1] - lock[0], flight[i][2] - lock[1]) <= r_lock_sub * 6]
        flight = [flight[i] for i in keep_i]
        radii = [radii[i] for i in keep_i]
    # PHYSICS: a launched ball never descends steeply in its first visible frames —
    # a segment plunging >60° below horizontal is the clubhead on follow-through.
    while len(flight) >= 2:
        dx = flight[1][1] - flight[0][1]
        dy = flight[1][2] - flight[0][2]
        if dy > abs(dx) * 1.732:      # tan(60°)
            flight.pop(1)
            if len(radii) >= 2:
                radii.pop(1)
        else:
            break
    v, ang = robust_speed(flight)
    if v is None:
        return None
    r_px = float(np.median(radii)) if radii else r0
    first_step = None
    ti = ts.get(imp)
    if ti is not None and flight and flight[0][0] > ti:
        d0 = math.hypot(flight[0][1] - lock[0], flight[0][2] - lock[1])
        first_step = d0 / (flight[0][0] - ti)
    cl = []
    for fi in sorted(club_pts):
        t = ts.get(fi)
        if t is not None and imp - 6 <= fi <= imp:
            cl.append((t, club_pts[fi][0], club_pts[fi][1]))
    cv, _ = robust_speed(cl[-4:]) if len(cl) >= 2 else (None, None)
    # two-point exact-dt speed (both endpoints measured; drop-proof)
    v2pt = None
    if len(flight) >= 2:
        (t1, x1, y1), (t2, x2, y2) = flight[0], flight[1]
        if t2 > t1:
            v2pt = math.hypot(x2 - x1, y2 - y1) / (t2 - t1)
    # physical impact instant: back-extrapolate the flight line to the lock —
    # frame timestamps bound it only to ±one (possibly dropped) frame interval
    wfit = weighted_fit([(t, x, y, 0.6) for t, x, y in flight]) if len(flight) >= 2 else None
    t_contact = impact_time(wfit[2], lock) if wfit else None
    if t_contact is not None and flight and flight[0][0] > t_contact:
        d0 = math.hypot(flight[0][1] - lock[0], flight[0][2] - lock[1])
        dt0 = flight[0][0] - t_contact
        # extrapolated contact within <2ms of the first point is a degenerate-line
        # artifact — division there manufactures absurd speeds (seen: 500k px/s)
        if dt0 > 2e-3:
            first_step = d0 / dt0
    # arc-fit club speed at the contact instant (falls back to 2-point)
    if len(cl) >= 2:
        cv_arc = arc_club_speed(cl, t_contact)
        if cv_arc:
            cv = cv_arc
    # scale-free physical consistency — but only distrust the club when the BALL
    # track is itself trustworthy; on junk-ball shots the ratio test would throw
    # away a good club measurement
    ball_trustworthy = (wfit is not None and len(flight) >= 2 and float(wfit[3].max()) <= 2.5)
    if cv and v and ball_trustworthy and not (0.95 <= v / cv <= 1.62):
        cv = 0.0
    shrink = 0.0
    if len(radii) >= 2 and len(flight) >= 2 and flight[-1][0] > flight[0][0]:
        shrink = (radii[0] - radii[-1]) / (flight[-1][0] - flight[0][0])
    r_scale = r_lock_sub or r_px
    v_phys_mps = v * (BALL_M / 2 / max(r_scale, 2))
    if not (3.0 <= v_phys_mps <= 105.0):   # ~7..235 mph — outside is not a golf ball
        return None
    return {
        'v_px_s': v, 'angle': ang, 'r_px': r_px, 'n_pts': len(flight),
        'first_step': first_step or v, 'club_v': cv or 0.0,
        'v_mps_phys': v * (BALL_M / 2 / max(r_scale, 2)),
        'v2pt': v2pt or v, 'shrink_rate': shrink,
        'r_lock_sub': r_scale,
        'v2pt_phys': (v2pt or v) * (BALL_M / 2 / max(r_scale, 2)),
        'sin_ang': math.sin(math.radians(ang)), 'cos_ang': math.cos(math.radians(ang)),
        '_chi_max': float(wfit[3].max()) if wfit is not None else 9.9,
        '_n_flight': len(flight),
        '_2pt_agree': (abs((v2pt or v) - (first_step or v)) / max(v2pt or v, 1e-6)),
    }


def build_rows():
    pairs = json.load(open(os.path.join(SESSION, 'pairs.json')))
    rows = []
    for p in pairs:
        shot = p.get('shot')
        if not shot or shot not in LABELS:
            continue
        frames = LABELS[shot]
        imp, lock_b = label_impact(frames)
        if imp is None:
            continue
        lock = (lock_b['cx'], lock_b['cy'])
        r0 = max(4.0, lock_b.get('r', 8))
        ts = ts_of(shot)

        oracle_ball = {int(k): (f['ball']['cx'], f['ball']['cy'], f['ball'].get('r', r0))
                       for k, f in frames.items() if f.get('ball')}
        oracle_club = {int(k): (f['club']['cx'], f['club']['cy'])
                       for k, f in frames.items() if f.get('club')}
        det = PREDS.get(shot, {})
        det_ball = {int(k): (e['ball']['cx'], e['ball']['cy'], e['ball'].get('r', r0))
                    for k, e in det.items() if e.get('ball')}
        det_club = {int(k): (e['club']['cx'], e['club']['cy'])
                    for k, e in det.items() if e.get('club')}

        r_lock_sub = lock_radius_precise(shot, frames, lock, r0, imp)
        fo = features_from_track(oracle_ball, oracle_club, lock, r0, ts, imp, shot=shot, r_lock_sub=r_lock_sub)
        fd = features_from_track(det_ball, det_club, lock, r0, ts, imp, shot=shot, r_lock_sub=r_lock_sub)
        rows.append({'shot': shot, 'club_type': p.get('club'),
                     'garmin_ball': p.get('garmin_ball_mph'),
                     'garmin_row': None,
                     'oracle': fo, 'detector': fd})
    return rows


FEATS = ['v_px_s', 'angle', 'r_px', 'n_pts', 'first_step', 'club_v', 'v_mps_phys',
         'v2pt', 'shrink_rate', 'r_lock_sub', 'v2pt_phys', 'sin_ang', 'cos_ang']


def xmat(rows, kind):
    X, y, keep = [], [], []
    for r in rows:
        f = r[kind]
        if f is None or not r['garmin_ball']:
            continue
        X.append([f[k] if f[k] is not None else 0.0 for k in FEATS])
        y.append(r['garmin_ball'])
        keep.append(r)
    return np.array(X), np.array(y), keep


def ridge_cv(X, y, clubs, k=5, alpha=1.0, seed=0):
    rng = np.random.default_rng(seed)
    idx = np.arange(len(y))
    # stratify by club type
    folds = [[] for _ in range(k)]
    for ct in sorted(set(clubs)):
        sub = idx[np.array(clubs) == ct]
        rng.shuffle(sub)
        for i, j in enumerate(sub):
            folds[i % k].append(j)
    rels = []
    for f in folds:
        te = np.array(sorted(f))
        tr = np.array(sorted(set(idx) - set(f)))
        mu, sd = X[tr].mean(0), X[tr].std(0) + 1e-9
        Xtr = (X[tr] - mu) / sd
        Xte = (X[te] - mu) / sd
        A = Xtr.T @ Xtr + alpha * np.eye(X.shape[1])
        w = np.linalg.solve(A, Xtr.T @ (y[tr] - y[tr].mean()))
        pred = Xte @ w + y[tr].mean()
        rels.extend(np.abs(pred - y[te]) / y[te] * 100)
    return np.array(rels)


def gbt_reg_cv(X, y, clubs, k=5, rounds=150, shrink=0.15, seed=0):
    rng = np.random.default_rng(seed)
    idx = np.arange(len(y))
    folds = [[] for _ in range(k)]
    for ct in sorted(set(clubs)):
        sub = idx[np.array(clubs) == ct]
        rng.shuffle(sub)
        for i, j in enumerate(sub):
            folds[i % k].append(j)
    rels = []
    thr_grid = None
    for f in folds:
        te = np.array(sorted(f)); tr = np.array(sorted(set(idx) - set(f)))
        Xtr, ytr = X[tr], y[tr]
        F = np.full(len(tr), ytr.mean())
        stumps = []
        grids = [np.unique(np.quantile(Xtr[:, jj], np.linspace(0.1, 0.9, 12))) for jj in range(X.shape[1])]
        for _ in range(rounds):
            g = F - ytr
            best = None
            for jj in range(X.shape[1]):
                xj = Xtr[:, jj]
                for thr in grids[jj]:
                    l = xj <= thr
                    nl, nr = l.sum(), (~l).sum()
                    if nl < 4 or nr < 4:
                        continue
                    gl, gr = g[l].mean(), g[~l].mean()
                    gain = nl * gl * gl + nr * gr * gr
                    if best is None or gain > best[0]:
                        best = (gain, jj, thr, -gl, -gr)
            _, jj, thr, vl, vr = best
            F += shrink * np.where(Xtr[:, jj] <= thr, vl, vr)
            stumps.append((jj, thr, shrink * vl, shrink * vr))
        pred = np.full(len(te), ytr.mean())
        for jj, thr, vl, vr in stumps:
            pred += np.where(X[te, jj] <= thr, vl, vr)
        rels.extend(np.abs(pred - y[te]) / y[te] * 100)
    return np.array(rels)


def main():
    rows = build_rows()
    print(f'rows: {len(rows)}')
    for kind in ('oracle', 'detector'):
        X, y, keep = xmat(rows, kind)
        clubs = [r['club_type'] for r in keep]
        for name, fn in (('ridge', ridge_cv), ('gbt', gbt_reg_cv)):
            rel = fn(X, y, clubs)
            print(f"\n{kind.upper()} {name} (n={len(y)}):  median {np.median(rel):.1f}%  mean {rel.mean():.1f}%  "
                  f"≤2%: {100*(rel<=2).mean():.0f}%  ≤3%: {100*(rel<=3).mean():.0f}%  ≤5%: {100*(rel<=5).mean():.0f}%")
        # quality tier: 2+ measured flight points
        sel = np.array([r[kind]['n_pts'] >= 2 for r in keep])
        if sel.sum() >= 20:
            rel = ridge_cv(X[sel], y[sel], [c for c, m in zip(clubs, sel) if m])
            print(f"  {kind} ridge, ≥2 flight pts (n={sel.sum()}): median {np.median(rel):.1f}%  ≤3%: {100*(rel<=3).mean():.0f}%  ≤5%: {100*(rel<=5).mean():.0f}%")
        # CONFIDENCE GATE (noise model): fit residuals within 2.5 sigma and 3+ points —
        # the live app would show these and withhold the rest
        conf = np.array([
            (r[kind]['_n_flight'] >= 3 and r[kind]['_chi_max'] <= 2.5) or
            (r[kind]['_n_flight'] == 2 and r[kind]['_2pt_agree'] <= 0.25)
            for r in keep])
        if conf.sum() >= 15:
            rel = ridge_cv(X[conf], y[conf], [c for c, m in zip(clubs, conf) if m])
            print(f"  {kind} CONFIDENT tracks (n={conf.sum()}, coverage {100*conf.mean():.0f}%): "
                  f"median {np.median(rel):.1f}%  ≤2%: {100*(rel<=2).mean():.0f}%  ≤3%: {100*(rel<=3).mean():.0f}%  ≤5%: {100*(rel<=5).mean():.0f}%")
    json.dump([{k: (v if k in ('shot','club_type','garmin_ball') else v) for k, v in r.items()}
               for r in rows], open(os.path.join(SESSION, 'metric_rows.json'), 'w'), default=str)


if __name__ == '__main__':
    main()
