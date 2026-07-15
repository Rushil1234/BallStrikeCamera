#!/usr/bin/env python3
"""Extract dt-aware ball/club trajectories for every paired shot using the
golf-context detector, and compute physics features for the metric models.

Output (tracks.json): per shot —
  lock (px), impact frame, ball flight points [(fi, t, cx, cy, r_px)],
  club path points [(fi, t, cx, cy, src)], plus derived features:
  ball speed (px/s via least-squares over real timestamps), flight angle,
  ball radius median, club speed near impact.

Speeds use REAL per-frame timestamps (timestamps.json) — dropped frames make
dt 2/240 instead of corrupting the velocity.
"""
import json, math, os, sys
import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hsv_object_explorer import frame_path
from hue_dist_gallery import hue_dist  # noqa: E402
from golf_context_detector import (  # noqa: E402
    blobs_from_mask, derive_lock, derive_impact, ShotState, FLIGHT_DIR)

ARCHIVE = os.path.expanduser('~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')
SESSION = os.path.expanduser('~/Documents/TrueCarryTraining/session_2026-07-12')


def load_timestamps(d):
    p = os.path.join(d, 'timestamps.json')
    if not os.path.exists(p):
        return {}
    j = json.load(open(p))
    return {e['frame_index']: e['timestamp'] for e in j.get('timestamps', [])}


def track_shot(shot, hint):
    d = os.path.join(ARCHIVE, shot)
    meta = json.load(open(os.path.join(d, 'metadata.json'))) if os.path.exists(os.path.join(d, 'metadata.json')) else {}
    first = cv2.imread(frame_path(d, 0))
    if first is None:
        return None
    Hh, Ww = first.shape[:2]
    ts = load_timestamps(d)

    lock_norm, lock_src = derive_lock(d, Ww, Hh, meta.get('locked_ball_rect'))

    pres = []
    for i in range(0, 14, 3):
        p = frame_path(d, i)
        if os.path.exists(p):
            pres.append(cv2.imread(p).mean(axis=2))
    base_luma = np.median(np.stack(pres), axis=0) if len(pres) >= 3 else None

    state = ShotState(lock_norm, (Ww, Hh))
    imp, imp_src = derive_impact(d, state.lock, state.ball_r, base_luma, hint, Ww, Hh)

    ball_pts, club_pts = [], []
    prev_luma = None
    for fi in range(max(0, imp - 5), imp + 11):
        p = frame_path(d, fi)
        if not os.path.exists(p):
            continue
        bgr = cv2.imread(p)
        dh, _ = hue_dist(bgr)
        luma = bgr.mean(axis=2)
        motion = np.abs(luma - base_luma) if base_luma is not None else None

        bm = cv2.morphologyEx((dh >= 160).astype(np.uint8) * 255, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        bm = cv2.morphologyEx(bm, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
        bright = blobs_from_mask(bm, motion)

        hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
        V, S = hsv[..., 2], hsv[..., 1]
        dm = ((V <= 70) & (S <= 120)).astype(np.uint8) * 255
        if motion is not None:
            dm[motion < 15] = 0
        dm = cv2.morphologyEx(dm, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        dm = cv2.morphologyEx(dm, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
        dark = blobs_from_mask(dm, motion, min_area=50)

        diff_cands = []
        if prev_luma is not None:
            fd = np.abs(luma - prev_luma)
            thr = max(18.0, float(np.median(fd)) * 4 + 10)
            dfm = (fd >= thr).astype(np.uint8) * 255
            dfm = cv2.morphologyEx(dfm, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
            dfm = cv2.morphologyEx(dfm, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
            diff_cands = blobs_from_mask(dfm, motion, min_area=30)
        prev_luma = luma

        ball = state.pick_ball(bright, impacted=(fi > imp), fi=fi)
        club, club_src = state.pick_club(bright, dark, diff_cands, ball=ball)
        t = ts.get(fi)
        if ball and fi > imp:
            ball_pts.append({'fi': fi, 't': t, 'cx': ball['cx'], 'cy': ball['cy'], 'r': ball['r']})
        if club and club_src != 'none':
            club_pts.append({'fi': fi, 't': t, 'cx': club['cx'], 'cy': club['cy'], 'src': club_src})

    # features
    feats = {}
    fl = [p for p in ball_pts if p['t']]
    if len(fl) >= 2:
        t0 = fl[0]['t']
        T = np.array([p['t'] - t0 for p in fl])
        X = np.array([p['cx'] for p in fl])
        Y = np.array([p['cy'] for p in fl])
        if np.ptp(T) > 1e-4:
            vx = np.polyfit(T, X, 1)[0]
            vy = np.polyfit(T, Y, 1)[0]
            feats['ball_v_px_s'] = float(math.hypot(vx, vy))
            feats['flight_angle_deg'] = float(math.degrees(math.atan2(-vy, vx * FLIGHT_DIR)))
            # first-step speed: lock -> first flight point (needs impact-frame time)
            ti = ts.get(imp)
            if ti and fl[0]['t'] > ti:
                d0 = math.hypot(fl[0]['cx'] - state.lock[0], fl[0]['cy'] - state.lock[1])
                feats['first_step_px_s'] = float(d0 / (fl[0]['t'] - ti))
    if ball_pts:
        feats['ball_r_px'] = float(np.median([p['r'] for p in ball_pts]))
    feats['lock_r_px'] = state.ball_r
    cl = [p for p in club_pts if p['t'] and abs(p['fi'] - imp) <= 3]
    if len(cl) >= 2:
        t0 = cl[0]['t']
        T = np.array([p['t'] - t0 for p in cl])
        X = np.array([p['cx'] for p in cl])
        Y = np.array([p['cy'] for p in cl])
        if np.ptp(T) > 1e-4:
            feats['club_v_px_s'] = float(math.hypot(np.polyfit(T, X, 1)[0], np.polyfit(T, Y, 1)[0]))

    return {'shot': shot, 'lock': state.lock, 'lock_src': lock_src, 'ball_r_lock': state.ball_r,
            'impact': imp, 'impact_src': imp_src, 'ball': ball_pts, 'club': club_pts,
            'features': feats, 'W': Ww, 'H': Hh}


def main():
    pairs = json.load(open(os.path.join(SESSION, 'pairs.json')))
    out = {}
    n_flight2 = 0
    for i, p in enumerate(pairs):
        shot = p.get('shot')
        if not shot:
            continue
        r = track_shot(shot, 20)
        if r is None:
            continue
        out[shot] = r
        if len(r['ball']) >= 2:
            n_flight2 += 1
        if (i + 1) % 20 == 0:
            print(f'{i+1}/{len(pairs)} done')
    json.dump(out, open(os.path.join(SESSION, 'tracks.json'), 'w'), indent=1)
    print(f"tracked {len(out)} shots; {n_flight2} with >=2 flight points")


if __name__ == '__main__':
    main()
