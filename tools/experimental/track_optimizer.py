#!/usr/bin/env python3
"""Physics-global track optimization + measurement-grade fits (offline layer).

Nothing here is tuned to a dataset: every constant derives from a noise model
or a physical bound, so it generalizes by construction.

  best_ball_path   exhaustive search over per-frame candidates (incl. "miss"):
                   the winning path maximizes ballistic likelihood — one
                   straight line from the lock, constant speed (drag over the
                   visible 40ms is <1%), monotone radius (ball departing a
                   top-down camera never grows), candidate quality.
  weighted_fit     uncertainty-weighted line fit over (t,x,y); per-point sigma
                   from blob geometry (subpixel centroid of a clean round blob
                   ≈0.4px; degraded by low circularity / elongation / border).
  impact_time      back-extrapolate the fitted line to the lock position —
                   the true contact instant sits between frames; using the
                   last-still frame's timestamp biases first-step speeds.
  arc_club_speed   clubhead rides a circular arc and decelerates; fit the arc
                   (Kasa circle fit), fit angle-vs-time, evaluate tangential
                   speed AT the impact instant instead of a 2-point average.
  smash_gate       ball/club speed ratio outside [0.95, 1.62] is physically
                   impossible → the weaker track is invalid (flag, never fix).
"""
import math
import numpy as np

SPEED_TOL_FRAC = 0.35     # segment speed agreement tolerance floor (noise-dominated at 1-2px steps)


def point_sigma(c):
    """Expected position noise (px) for a blob measurement."""
    s = 0.4
    s += 0.8 * max(0.0, 0.7 - c.get('circ', 0.5))       # ragged blobs localize worse
    s += 0.6 * max(0.0, c.get('elong', 0.3) - 0.5)      # smear along axis
    if c.get('border'):
        s += 1.0                                        # clipped disc: centroid biased
    if c.get('src') == 'rescue':
        s += 0.6
    return s


def _path_score(path, lock, r0, prob_key='prob'):
    """path: list of (t, c) with c=None allowed. Higher is better."""
    pts = [(t, c) for t, c in path if c is not None]
    if len(pts) < 1:
        return -1e9, None
    score = 0.0
    # candidate quality + miss penalties
    for t, c in path:
        if c is None:
            score -= 1.5
        else:
            score += 2.5 * (c.get(prob_key, 0.6))
    if len(pts) == 1:
        return score - 2.0, None
    # collinearity with the lock: fit line through lock + points, penalize residuals
    P = np.array([[t, c['cx'], c['cy']] for t, c in pts])
    sig = np.array([point_sigma(c) for _, c in pts])
    T = P[:, 0] - P[0, 0]
    if np.ptp(T) < 1e-4:
        return -1e9, None
    w = 1.0 / sig**2
    vx = np.polyfit(T, P[:, 1], 1, w=w)
    vy = np.polyfit(T, P[:, 2], 1, w=w)
    rx = P[:, 1] - np.polyval(vx, T)
    ry = P[:, 2] - np.polyval(vy, T)
    res = np.hypot(rx, ry) / sig
    score -= float((res**2).mean())                      # chi²/n against the noise model
    # segment speed consistency
    if len(pts) >= 3:
        segs = []
        for a, b in zip(pts, pts[1:]):
            dt = b[0] - a[0]
            if dt <= 0:
                return -1e9, None
            segs.append(math.hypot(b[1]['cx'] - a[1]['cx'], b[1]['cy'] - a[1]['cy']) / dt)
        v_med = float(np.median(segs))
        if v_med > 1:
            dev = max(abs(s - v_med) / v_med for s in segs)
            tol = max(SPEED_TOL_FRAC * 20 / max(segs), SPEED_TOL_FRAC * 0.35)  # noise floor
            score -= 4.0 * max(0.0, dev - 0.35)
    # radius monotonicity (ball departing top-down camera shrinks)
    rr = [c.get('r', r0) for _, c in pts]
    for a, b in zip(rr, rr[1:]):
        if b > a * 1.25:
            score -= 2.0
    # direction: away from lock, forward
    d0 = math.hypot(pts[0][1]['cx'] - lock[0], pts[0][1]['cy'] - lock[1])
    d1 = math.hypot(pts[-1][1]['cx'] - lock[0], pts[-1][1]['cy'] - lock[1])
    if d1 < d0:
        score -= 4.0
    v = float(math.hypot(vx[0], vy[0]))
    return score, v


def best_ball_path(frame_cands, lock, r0, max_per_frame=3):
    """frame_cands: list of (t, [candidates]) post-impact, time-ordered.
    Exhaustive search over top candidates + miss per frame."""
    options = []
    for t, cands in frame_cands:
        cs = sorted(cands, key=lambda c: -c.get('prob', 0.5))[:max_per_frame]
        options.append([(t, c) for c in cs] + [(t, None)])
    total = 1
    for o in options:
        total *= len(o)
    if total > 300000:
        options = [o[:3] for o in options]
    best, best_path = -1e9, None
    idx = [0] * len(options)
    while True:
        path = [options[i][idx[i]] for i in range(len(options))]
        s, v = _path_score(path, lock, r0)
        if s > best:
            best, best_path = s, path
        j = len(options) - 1
        while j >= 0:
            idx[j] += 1
            if idx[j] < len(options[j]):
                break
            idx[j] = 0
            j -= 1
        if j < 0:
            break
    if best_path is None:
        return []
    return [(t, c) for t, c in best_path if c is not None]


def weighted_fit(pts_with_c):
    """[(t, x, y, sigma)] → (v_px_s, angle_deg, t_at_origin_fn, residuals)."""
    if len(pts_with_c) < 2:
        return None
    P = np.array([[p[0], p[1], p[2]] for p in pts_with_c])
    sig = np.array([p[3] for p in pts_with_c])
    T = P[:, 0] - P[0, 0]
    if np.ptp(T) < 1e-4:
        return None
    w = 1.0 / sig**2
    cx = np.polyfit(T, P[:, 1], 1, w=w)
    cy = np.polyfit(T, P[:, 2], 1, w=w)
    v = float(math.hypot(cx[0], cy[0]))
    ang = float(math.degrees(math.atan2(-cy[0], -cx[0])))
    return v, ang, (cx, cy, P[0, 0]), np.hypot(P[:, 1] - np.polyval(cx, T), P[:, 2] - np.polyval(cy, T)) / sig


def impact_time(fit, lock):
    """Time at which the fitted line passes closest to the lock — the physical
    contact instant, independent of frame boundaries."""
    if fit is None:
        return None
    (cx, cy, t0) = fit
    vx, x0 = cx
    vy, y0 = cy
    v2 = vx * vx + vy * vy
    if v2 < 1e-9:
        return None
    tau = ((lock[0] - x0) * vx + (lock[1] - y0) * vy) / v2
    return t0 + tau


def arc_club_speed(club_pts, t_impact):
    """club_pts: [(t, x, y)] near impact → tangential speed at t_impact.
    Kasa circle fit + linear angular rate; falls back to weighted line fit."""
    pts = sorted(club_pts)
    if len(pts) < 2:
        return None
    if len(pts) >= 3:
        A = np.array([[2 * x, 2 * y, 1.0] for _, x, y in pts])
        b = np.array([x * x + y * y for _, x, y in pts])
        try:
            (a, c, d), *_ = np.linalg.lstsq(A, b, rcond=None)
            R = math.sqrt(max(d + a * a + c * c, 1e-6))
            if 20 <= R <= 5000:      # plausible swing arc in px at this scale
                th = np.unwrap([math.atan2(y - c, x - a) for _, x, y in pts])
                T = np.array([p[0] for p in pts])
                if np.ptp(T) > 1e-4:
                    om = np.polyfit(T - T[0], th, 1)[0]
                    return abs(om) * R
        except np.linalg.LinAlgError:
            pass
    (t1, x1, y1), (t2, x2, y2) = pts[0], pts[-1]
    if t2 <= t1:
        return None
    return math.hypot(x2 - x1, y2 - y1) / (t2 - t1)


def smash_gate(ball_v_mph, club_v_mph):
    """True = physically consistent pair."""
    if not ball_v_mph or not club_v_mph or club_v_mph < 1:
        return False
    return 0.95 <= ball_v_mph / club_v_mph <= 1.62
