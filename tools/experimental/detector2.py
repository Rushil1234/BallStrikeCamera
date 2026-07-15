#!/usr/bin/env python3
"""Detector v2 — label-driven rebuild of the golf-context detector.

Changes from v1, each tied to a measured miss bucket (labels/miss_inventory):
  BALL
  - dt-aware state machine: velocities in px/SECOND from timestamps.json;
    exit projection uses real elapsed time (7/12 dropped frames made
    per-frame velocities lie by 2-8x).
  - motion-blur acceptance: post-impact, an elongated blob whose major axis
    aligns with the flight direction (within 25°) is the smeared ball —
    circularity gate drops to 0.25 for aligned blobs (25 misses were this).
  - border acceptance post-impact: a blob touching the frame edge on the
    flight line is the ball leaving (18 misses) — accepted, flagged 'exiting'.
  - rescue pass: when the strict mask finds nothing near the dt-predicted
    position, rescan that neighborhood at dh>=140 (6 fragmentation misses).
  CLUB
  - one unified candidate pool from three masks (bright hue-dist, dark, and
    consecutive-frame differencing), every candidate carrying features; a
    trained linear scorer (train_club_scorer.py, cross-day validated) ranks
    them; below score threshold = no club that frame (106 of 184 club misses
    were pool recall, 76 were ranking).
"""
import json, math, os, sys
import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hue_dist_gallery import hue_dist  # noqa: E402

FLIGHT_DIR = -1.0
CONE_HALF_DEG = 60.0

CLUB_SCORER_PATH = os.path.expanduser('~/Documents/TrueCarryTraining/labels/club_scorer.json')


def _blob_features(c, mask_src, W, H, motion, dh, V):
    area = cv2.contourArea(c)
    if area < 8:
        return None
    (ex, ey), er = cv2.minEnclosingCircle(c)
    m = cv2.moments(c)
    if m['m00'] <= 0:
        return None
    x, y, w, h = cv2.boundingRect(c)
    cx, cy = m['m10'] / m['m00'], m['m01'] / m['m00']
    # orientation of the blob (major axis angle) from central moments
    mu20, mu02, mu11 = m['mu20'] / m['m00'], m['mu02'] / m['m00'], m['mu11'] / m['m00']
    theta = 0.5 * math.atan2(2 * mu11, (mu20 - mu02)) if (mu20 != mu02 or mu11) else 0.0
    ecc_num = math.hypot(mu20 - mu02, 2 * mu11)
    ecc_den = mu20 + mu02 + 1e-9
    elong = ecc_num / ecc_den          # 0 = round, →1 = line
    b = {
        'src': mask_src, 'area': float(area),
        'circ': float(area / (np.pi * er * er + 1e-6)),
        'r': float(np.sqrt(area / np.pi)),
        'cx': float(cx), 'cy': float(cy), 'w': w, 'h': h,
        'theta': float(theta), 'elong': float(elong),
        'border': x <= 1 or y <= 1 or x + w >= W - 2 or y + h >= H - 2,
        'mot': float(motion[y:y+h, x:x+w].mean()) if motion is not None else 0.0,
        'dh_mean': float(dh[y:y+h, x:x+w].mean()),
        'v_mean': float(V[y:y+h, x:x+w].mean()),
    }
    return b


def masks_and_blobs(bgr, prev_luma, base_luma):
    dh, _ = hue_dist(bgr)
    luma = bgr.mean(axis=2)
    motion = np.abs(luma - base_luma) if base_luma is not None else None
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    V, S = hsv[..., 2], hsv[..., 1]
    H, W = dh.shape

    out = []
    def collect(mask, src):
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        for c in contours:
            b = _blob_features(c, src, W, H, motion, dh, V)
            if b:
                out.append(b)

    bm = cv2.morphologyEx((dh >= 160).astype(np.uint8) * 255, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    bm = cv2.morphologyEx(bm, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    collect(bm, 'bright')

    dm = ((V <= 78) & (S <= 130)).astype(np.uint8) * 255
    if motion is not None:
        dm[motion < 12] = 0
    dm = cv2.morphologyEx(dm, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    dm = cv2.morphologyEx(dm, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    collect(dm, 'dark')

    if prev_luma is not None:
        fd = np.abs(luma - prev_luma)
        thr = max(15.0, float(np.median(fd)) * 4 + 8)
        fm = (fd >= thr).astype(np.uint8) * 255
        fm = cv2.morphologyEx(fm, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
        fm = cv2.morphologyEx(fm, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
        collect(fm, 'diff')

    return out, dh, luma


def rescue_ball_at(dh, px, py, r_hint):
    """Loose-threshold rescan around a dt-predicted position (fragmented ball)."""
    H, W = dh.shape
    R = int(max(18, r_hint * 4))
    x0, x1 = max(0, int(px - R)), min(W, int(px + R))
    y0, y1 = max(0, int(py - R)), min(H, int(py + R))
    if x1 - x0 < 6 or y1 - y0 < 6:
        return None
    sub = (dh[y0:y1, x0:x1] >= 140).astype(np.uint8) * 255
    sub = cv2.morphologyEx(sub, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    contours, _ = cv2.findContours(sub, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    best = None
    for c in contours:
        area = cv2.contourArea(c)
        if area < 10:
            continue
        m = cv2.moments(c)
        if m['m00'] <= 0:
            continue
        cx, cy = m['m10'] / m['m00'] + x0, m['m01'] / m['m00'] + y0
        d = math.hypot(cx - px, cy - py)
        r = float(np.sqrt(area / np.pi))
        if 2.0 <= r <= 24 and (best is None or d < best[0]):
            best = (d, {'cx': cx, 'cy': cy, 'r': r, 'src': 'rescue',
                        'circ': 0.5, 'elong': 0.5, 'border': False, 'area': area})
    return best[1] if best and best[0] <= r_hint * 2.5 else None


BALL_SCORER_PATH = os.path.expanduser('~/Documents/TrueCarryTraining/labels/ball_scorer.json')


class BallScorer:
    def __init__(self, path=BALL_SCORER_PATH):
        self.wb = None
        if os.path.exists(path):
            j = json.load(open(path))
            self.wb = (np.array(j['w']), j['b'], j.get('threshold', 0.5))

    def prob(self, feats):
        w, b, _ = self.wb
        z = max(-30, min(30, float(np.dot(w, feats) + b)))
        return 1.0 / (1.0 + math.exp(-z))

    @property
    def threshold(self):
        return self.wb[2] if self.wb else 0.5


class BallTracker:
    """dt-aware golf-prior ball state machine."""

    def __init__(self, lock_px, ball_r, W, H, scorer=None):
        self.lock = lock_px
        self.r0 = ball_r
        self.W, self.H = W, H
        self.progress = 0.0
        self.direction = None
        self.last = None            # (t, cx, cy)
        self.vel = None             # px/s
        self.exited = False
        self.scorer = scorer
        self.flight_points = 0
        self.misses_in_flight = 0

    def predict(self, t):
        if self.vel is None or self.last is None:
            return None
        dt = t - self.last[0]
        return (self.last[1] + self.vel[0] * dt, self.last[2] + self.vel[1] * dt)

    def _state_dict(self, t):
        return {'lock': self.lock, 'pred': self.predict(t) if t is not None else None,
                'dir': self.direction, 'progress': self.progress}

    def pick(self, blobs, impacted, t):
        if self.exited:
            return None
        pred = self.predict(t) if t is not None else None
        if pred is not None:
            m = self.r0 * 1.5
            if not (-m <= pred[0] <= self.W + m and -m <= pred[1] <= self.H + m):
                self.exited = True
                return None

        st = self._state_dict(t)
        cands = []
        for b in blobs:
            if b['src'] != 'bright':
                continue
            if not (2.0 <= b['r'] <= 24) or b['area'] < 12:
                continue
            # HARD physics gates only — the learned scorer handles the rest.
            vx, vy = b['cx'] - self.lock[0], b['cy'] - self.lock[1]
            dist = math.hypot(vx, vy)
            if impacted:
                if dist >= self.r0 and vx * FLIGHT_DIR < 0:
                    continue                      # backwards = never the ball
                if dist < self.progress - self.r0 * 1.5:
                    continue                      # monotone forward
            else:
                if dist > self.r0 * 2.2:
                    continue                      # pre-impact: at the lock
            if impacted and self.last is not None and pred is not None:
                # static junk: the pick sits where the ball WAS while physics says
                # the ball must be far downrange by now
                d_last = math.hypot(b['cx'] - self.last[1], b['cy'] - self.last[2])
                d_pred = math.hypot(pred[0] - self.last[1], pred[1] - self.last[2])
                if d_last < self.r0 and d_pred > self.r0 * 2.5:
                    continue
            if self.scorer is not None:
                from train_ball_scorer import ball_feature_vector
                p = self.scorer.prob(ball_feature_vector(b, st, self.r0, impacted))
                if p >= self.scorer.threshold:
                    cands.append((p, b))
            else:
                cands.append((b['circ'], b))

        chosen = max(cands, key=lambda x: x[0])[1] if cands else None
        if impacted:
            if chosen is not None:
                self._advance(chosen, t)
            elif self.flight_points >= 1:
                # flight has started; sustained silence = the ball is gone
                self.misses_in_flight += 1
                if self.misses_in_flight >= 2:
                    self.exited = True
        return chosen

    def accept_rescue(self, b, t):
        self._advance(b, t)

    def _advance(self, b, t):
        vx, vy = b['cx'] - self.lock[0], b['cy'] - self.lock[1]
        dist = math.hypot(vx, vy)
        self.misses_in_flight = 0
        if dist >= self.r0:
            self.flight_points += 1
        self.progress = max(self.progress, dist)
        if dist >= self.r0 * 2:
            self.direction = (vx / dist, vy / dist)
        if t is not None:
            if self.last is not None and t > self.last[0]:
                dt = t - self.last[0]
                self.vel = ((b['cx'] - self.last[1]) / dt, (b['cy'] - self.last[2]) / dt)
            self.last = (t, b['cx'], b['cy'])


CLUB_FEATURES = ['log_area', 'aspect', 'elong', 'mot', 'dh_mean', 'v_mean',
                 'dist_lock_r', 'cone_ang', 'is_bright', 'is_dark', 'is_diff',
                 'border', 'circ']


def club_feature_vector(b, lock, r0):
    dx, dy = b['cx'] - lock[0], b['cy'] - lock[1]
    dist = math.hypot(dx, dy)
    backward = dx * (-FLIGHT_DIR)
    cone_ang = math.degrees(math.atan2(abs(dy), backward)) if backward > 0 else 180.0
    return [
        math.log(max(b['area'], 1)),
        max(b['w'], b['h']) / max(1, min(b['w'], b['h'])) if b.get('w') else 1.0,
        b['elong'], min(b['mot'], 80) / 80.0, b['dh_mean'] / 255.0, b['v_mean'] / 255.0,
        min(dist / max(r0, 1) / 20.0, 1.5), min(cone_ang, 180) / 180.0,
        1.0 if b['src'] == 'bright' else 0.0,
        1.0 if b['src'] == 'dark' else 0.0,
        1.0 if b['src'] == 'diff' else 0.0,
        1.0 if b['border'] else 0.0,
        b['circ'],
    ]


class ClubScorer:
    def __init__(self, path=CLUB_SCORER_PATH):
        self.wb = None
        if os.path.exists(path):
            j = json.load(open(path))
            self.wb = (np.array(j['w']), j['b'], j.get('threshold', 0.5))

    def score(self, b, lock, r0):
        if self.wb is None:
            return None
        w, bias, _ = self.wb
        z = float(np.dot(w, club_feature_vector(b, lock, r0)) + bias)
        return 1.0 / (1.0 + math.exp(-z))

    @property
    def threshold(self):
        return self.wb[2] if self.wb else 0.5


def pick_club(blobs, lock, r0, ball, scorer, prev_club=None):
    cands = []
    for b in blobs:
        if b['area'] < 25 or b['area'] > 6000:
            continue
        if ball and math.hypot(b['cx'] - ball['cx'], b['cy'] - ball['cy']) <= max(ball.get('r', 8), r0) * 0.9:
            continue
        s = scorer.score(b, lock, r0)
        if s is None:
            continue
        cands.append((s, b))
    if not cands:
        return None
    cands.sort(key=lambda x: -x[0])
    s, b = cands[0]
    if s < scorer.threshold:
        return None
    return dict(b, score=s)


CLUB_GBT_PATH = os.path.expanduser('~/Documents/TrueCarryTraining/labels/club_gbt.json')


class GBTClubScorer:
    """Boosted-stump club scorer (train_club_gbt.py). JSON: base + stumps."""

    def __init__(self, path=CLUB_GBT_PATH):
        self.model = None
        if os.path.exists(path):
            j = json.load(open(path))
            self.model = (j['base'], j['stumps'], j.get('threshold', 0.65))

    @property
    def threshold(self):
        return self.model[2] if self.model else 0.65

    def prob(self, x):
        base, stumps, _ = self.model
        F = base
        for jj, thr, vl, vr in stumps:
            F += vl if x[jj] <= thr else vr
        return 1.0 / (1.0 + math.exp(-max(-30, min(30, F))))


def pick_club_gbt(blobs, lock, r0, ball, scorer, prev_club=None):
    from train_club_gbt import club_feature_vector2
    cands = []
    for b in blobs:
        if b['area'] < 12 or b['area'] > 6000:
            continue
        if ball and math.hypot(b['cx'] - ball['cx'], b['cy'] - ball['cy']) <= max(ball.get('r', 8), r0) * 0.9:
            continue
        s = scorer.prob(club_feature_vector2(b, lock, r0, prev_club))
        cands.append((s, b))
    if not cands:
        return None
    cands.sort(key=lambda x: -x[0])
    s, b = cands[0]
    if s < scorer.threshold:
        return None
    return dict(b, score=s)


def rescue_ball_at_lock(dh, lock, r0):
    """Ball merged with club chrome at the strike: re-threshold the lock
    neighborhood at escalating cutoffs until a ball-sized round core splits out
    (same idea as the live pipeline's merged-blob rescue)."""
    H, W = dh.shape
    R = int(r0 * 3)
    x0, x1 = max(0, int(lock[0] - R)), min(W, int(lock[0] + R))
    y0, y1 = max(0, int(lock[1] - R)), min(H, int(lock[1] + R))
    if x1 - x0 < 6 or y1 - y0 < 6:
        return None
    for thr in (185, 205, 225, 242):
        sub = (dh[y0:y1, x0:x1] >= thr).astype(np.uint8) * 255
        contours, _ = cv2.findContours(sub, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        best = None
        for c in contours:
            area = cv2.contourArea(c)
            if area < 10:
                continue
            (ex, ey), er = cv2.minEnclosingCircle(c)
            circ = float(area / (np.pi * er * er + 1e-6))
            r = float(np.sqrt(area / np.pi))
            if not (2.0 <= r <= r0 * 1.8) or circ < 0.5:
                continue
            cx, cy = ex + x0, ey + y0
            d = math.hypot(cx - lock[0], cy - lock[1])
            if d <= r0 * 2.0 and (best is None or d < best[0]):
                best = (d, {'cx': cx, 'cy': cy, 'r': r, 'src': 'rescue', 'circ': circ,
                            'elong': 0.3, 'border': False, 'area': area})
        if best:
            return best[1]
    return None
