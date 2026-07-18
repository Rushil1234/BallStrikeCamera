#!/usr/bin/env python3
"""V3 flow — Noah's 5-step spec, offline, validated per-step against his labels.

Step 1: classify ball color at lock (+signature, +subpixel rest radius)
Step 2: rest tracker until failure -> impact = frame before movement
Step 3: club search on impact-2..impact
Step 4: color-specific flight search + disk-fit diameter
Step 5: >=2-flight-point model vs TopTracer

Iterates in seconds over every labeled shot; the Swift port happens ONCE after
each step's gate passes here.
"""
import json, math, os, sys, collections
import cv2
import numpy as np

sys.path.insert(0, '/Users/noahtobias/Downloads/BallStrikeCamera/tools/experimental')
from hsv_object_explorer import frame_path

TRAIN = os.path.expanduser('~/Documents/TrueCarryTraining')
LABELS = json.load(open(os.path.join(TRAIN, 'labels/labels.json')))
EXCLUDED = set(json.load(open(os.path.join(TRAIN, 'session_2026-07-17/excluded_shots.json'))))
ARCHIVES = [os.path.expanduser(a) for a in (
    '~/Documents/TrueCarryFramesArchive_20260717/AllFramesArchive',
    '~/Documents/TrueCarryFramesArchive_20260716/AllFramesArchive',
    '~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive')]
TRUTH_COLOR = {'20260717': 'yellow', '20260716': 'yellow',
               '20260712': 'white', '20260711': 'white', '20260710': 'white'}


def shot_dir(shot):
    for a in ARCHIVES:
        d = os.path.join(a, shot)
        if os.path.isdir(d):
            return d
    return None


def rest_from_labels(labs):
    pts = sorted(((int(k), v['ball']) for k, v in labs.items()
                  if isinstance(v, dict) and v.get('ball')), key=lambda t: t[0])
    if not pts:
        return None, None
    b0 = pts[0][1]
    r = max(4.0, b0.get('r', 6))
    for fi, b in pts:
        if math.hypot(b['cx'] - b0['cx'], b['cy'] - b0['cy']) >= 1.5 * r:
            return fi - 1, b0     # label-truth impact = frame before first movement
    return None, b0


def classify(img, cx, cy, r):
    b, g, rr = img[..., 0].astype(float), img[..., 1].astype(float), img[..., 2].astype(float)
    yel = rr + g - 2 * b
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    R = max(2.0, r * 0.85)
    yy, xx = np.ogrid[:img.shape[0], :img.shape[1]]
    disk = (xx - cx) ** 2 + (yy - cy) ** 2 <= R * R
    if disk.sum() == 0:
        return 'white', 0.0, 0.0
    hue = float(np.median(hsv[..., 0][disk]))
    y = float(yel[disk].mean())
    if y >= 150 and 15 <= hue <= 45:
        return 'yellow', y, hue
    if y >= 150:
        return 'lime', y, hue
    return 'white', y, hue


def step12(shot, labs):
    d = shot_dir(shot)
    if d is None:
        return None
    imp_true, rest = rest_from_labels(labs)
    if rest is None:
        return None
    cx, cy, r = rest['cx'], rest['cy'], max(4.0, rest.get('r', 6))
    img0 = cv2.imread(frame_path(d, 0))
    if img0 is None:
        return None
    color, yel, hue = classify(img0, cx, cy, r)

    # step 2: rest presence per frame — color-pixel count inside the rest disk vs f0.
    def disk_count(img):
        b, g, rr = img[..., 0].astype(float), img[..., 1].astype(float), img[..., 2].astype(float)
        if color == 'yellow' or color == 'lime':
            m = (rr + g - 2 * b) >= 120
        else:
            lum = (rr + g + b) / 3
            m = (lum >= 150) & (np.abs(rr - g) < 60) & (np.abs(g - b) < 60)
        R = max(2.0, r * 1.1)
        yy, xx = np.ogrid[:img.shape[0], :img.shape[1]]
        disk = (xx - cx) ** 2 + (yy - cy) ** 2 <= R * R
        return int((m & disk).sum())

    base = disk_count(img0)
    if base < 8:
        return {'shot': shot, 'color': color, 'yel': yel, 'imp_true': imp_true,
                'imp_pred': None, 'why': f'weak-rest-signal base={base}'}
    imp_pred = None
    absent = 0
    last_present = 0
    fi = 1
    while True:
        p = frame_path(d, fi)
        if not p or not os.path.exists(p):
            break
        img = cv2.imread(p)
        if img is None:
            break
        c = disk_count(img)
        if c >= base * 0.45:
            last_present = fi
            absent = 0
        else:
            absent += 1
            if absent >= 2:
                imp_pred = last_present
                break
        fi += 1
    if imp_pred is None and absent >= 1:
        imp_pred = last_present
    return {'shot': shot, 'color': color, 'yel': round(yel), 'imp_true': imp_true,
            'imp_pred': imp_pred, 'base': base}


def main():
    rows = []
    for shot, labs in sorted(LABELS.items()):
        if shot in EXCLUDED or not shot.startswith('shot_202607'):
            continue
        r = step12(shot, labs)
        if r:
            rows.append(r)

    # STEP 1 gate
    cls = collections.Counter()
    wrong = []
    for r in rows:
        day = r['shot'][5:13]
        truth = TRUTH_COLOR.get(day)
        ok = truth == r['color']
        cls[(truth, r['color'])] += 1
        if not ok:
            wrong.append((r['shot'], r['color'], r['yel']))
    n_ok = sum(v for (t, c), v in cls.items() if t == c)
    print(f"STEP 1 (color): {n_ok}/{len(rows)} correct  matrix={dict(cls)}")
    for w in wrong[:8]:
        print('   wrong:', w)

    # STEP 2 gate
    diffs = collections.Counter()
    n = 0
    bad = []
    for r in rows:
        if r['imp_true'] is None or r['imp_pred'] is None:
            continue
        d = r['imp_pred'] - r['imp_true']
        diffs[d] += 1
        n += 1
        if abs(d) > 1:
            bad.append((r['shot'], r['imp_true'], r['imp_pred']))
    within1 = sum(v for k, v in diffs.items() if abs(k) <= 1)
    print(f"STEP 2 (impact): n={n}  within±1: {within1} ({100*within1/max(n,1):.1f}%)  "
          f"hist={dict(sorted(diffs.items()))}")
    for b in bad[:10]:
        print('   off:', b)
    json.dump(rows, open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                      'v3_step12.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()


# ── STEP 4: color-specific flight search + disk-fit diameter ──────────────────
def yellow_flight_track(shot, labs, imp):
    """From impact+1: baseline-subtracted yellowness blobs, disk-fit diameter."""
    d = shot_dir(shot)
    _, rest = rest_from_labels(labs)
    cx0, cy0, r0 = rest['cx'], rest['cy'], max(4.0, rest.get('r', 6))
    # per-pixel yellowness baseline: median of early frames
    early = []
    for bi in (0, 2, 4, 6, 8):
        p = frame_path(d, bi)
        if p and os.path.exists(p):
            im = cv2.imread(p)
            b, g, rr = im[..., 0].astype(float), im[..., 1].astype(float), im[..., 2].astype(float)
            early.append(rr + g - 2 * b)
    base = np.median(np.stack(early), axis=0)
    H, W = base.shape

    track = {}
    prev = None
    fi = imp + 1
    while True:
        p = frame_path(d, fi)
        if not p or not os.path.exists(p):
            break
        im = cv2.imread(p)
        if im is None:
            break
        b, g, rr = im[..., 0].astype(float), im[..., 1].astype(float), im[..., 2].astype(float)
        diff = (rr + g - 2 * b) - base
        # exclude the lock area: rest-ball residue reads as positive diff after departure
        mask = (diff >= 70).astype(np.uint8)
        yy, xx = np.ogrid[:H, :W]
        mask[((xx - cx0) ** 2 + (yy - cy0) ** 2) <= (1.6 * r0) ** 2] = 0
        n, lab, stats, cents = cv2.connectedComponentsWithStats(mask, 8)
        cands = []
        for i in range(1, n):
            area = stats[i, cv2.CC_STAT_AREA]
            if area < 6 or area > 2500:
                continue
            cx, cy = cents[i]
            if cx < 4 or cx > W - 4 or cy < 4 or cy > H - 4:
                continue        # half off-screen: skip, per policy
            # forward of lock (play is -x), sane cone from the lock
            vx = cx - cx0
            if vx > r0:
                continue
            cands.append((area, cx, cy))
        pick = None
        if cands:
            if prev is not None:
                # nearest to previous point wins; must progress away from lock
                cands.sort(key=lambda c: (c[1] - prev[0]) ** 2 + (c[2] - prev[1]) ** 2)
                c = cands[0]
                if math.hypot(c[1] - prev[0], c[2] - prev[1]) <= max(90, r0 * 16):
                    pick = c
            else:
                # first flight frame: the largest yellow-diff blob in the cone
                cands.sort(key=lambda c: -c[0])
                pick = cands[0]
        if pick is not None:
            _, cx, cy = pick
            # disk fit for DIAMETER (the oracle's method): threshold at half the local
            # peak, count pixels within 14px of center
            R = 14
            x0, x1 = max(0, int(cx) - R), min(W, int(cx) + R)
            y0, y1 = max(0, int(cy) - R), min(H, int(cy) + R)
            patch = diff[y0:y1, x0:x1]
            peak = patch.max()
            thr = max(60.0, 0.5 * peak)
            sel = patch >= thr
            pyy, pxx = np.nonzero(sel)
            if len(pxx) >= 4:
                pcx, pcy = pxx.mean() + x0, pyy.mean() + y0
                # blur-immune radius: MINOR axis of the pixel cloud. A fast ball streaks
                # along its motion during exposure — the area-disk radius inflates and
                # poisons the depth scale (measured: 139mph driver read as 78). The
                # perpendicular extent stays the true diameter.
                xs, ys = pxx.astype(float), pyy.astype(float)
                cxx = ((xs - xs.mean()) ** 2).mean()
                cyy = ((ys - ys.mean()) ** 2).mean()
                cxy = ((xs - xs.mean()) * (ys - ys.mean())).mean()
                tr_, det = cxx + cyy, cxx * cyy - cxy * cxy
                lam_min = tr_ / 2 - math.sqrt(max(tr_ * tr_ / 4 - det, 0.0))
                r_minor = 2.0 * math.sqrt(max(lam_min, 0.25))
                r_area = math.sqrt(len(pxx) / math.pi)
                r_fit = min(r_area, r_minor)
                track[fi] = (float(pcx), float(pcy), float(r_fit))
                prev = (pcx, pcy)
        fi += 1
        if fi > imp + 24:
            break
    return track


def score_step4():
    W_, H_, EDGE = 360.0, 203.0, 10
    tot = hit = 0
    r_errs = []
    per_shot_pts = []
    for shot, labs in sorted(LABELS.items()):
        if shot in EXCLUDED:
            continue
        day = shot[5:13]
        if TRUTH_COLOR.get(day) != 'yellow':
            continue
        imp_true, rest = rest_from_labels(labs)
        if imp_true is None or shot_dir(shot) is None:
            continue
        r0 = max(4.0, rest.get('r', 6))
        track = yellow_flight_track(shot, labs, imp_true)
        pts = {int(k): v['ball'] for k, v in labs.items()
               if isinstance(v, dict) and v.get('ball')}
        npts = 0
        for fi, b in pts.items():
            if math.hypot(b['cx'] - rest['cx'], b['cy'] - rest['cy']) < 2.5 * r0:
                continue
            if b['cx'] < EDGE or b['cx'] > W_ - EDGE or b['cy'] < EDGE or b['cy'] > H_ - EDGE:
                continue
            tot += 1
            t = track.get(fi)
            if t and math.hypot(t[0] - b['cx'], t[1] - b['cy']) <= max(1.5 * b.get('r', 6), 6):
                hit += 1
                npts += 1
                if b.get('r'):
                    r_errs.append(abs(t[2] - b['r']))
        per_shot_pts.append(npts)
    r_errs.sort()
    print(f"STEP 4 (yellow flight): matched {hit}/{tot} = {100*hit/max(tot,1):.1f}%")
    if r_errs:
        print(f"   diameter |err|: median {r_errs[len(r_errs)//2]:.2f}px  p90 {r_errs[int(len(r_errs)*0.9)]:.2f}px")
    import collections as cc
    print(f"   shots with >=2 flight points: {sum(1 for n in per_shot_pts if n >= 2)}/{len(per_shot_pts)}")


if __name__ == '__main__' and os.environ.get('STEP4'):
    score_step4()


# ── STEP 5: fit from V3 tracks, measured vs TopTracer ─────────────────────────
def ts_map(shot):
    d = shot_dir(shot)
    p = os.path.join(d, 'timestamps.json')
    if not os.path.exists(p):
        return {}
    return {e['frame_index']: e['timestamp'] for e in json.load(open(p)).get('timestamps', [])}


def step5():
    pairs = {}
    for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-17/pairs.json'))):
        tt = p.get('toptracer') or {}
        if tt.get('ball_mph'):
            pairs[p['shot']] = (tt['ball_mph'], tt.get('launch'))
    for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-16/pairs.json'))):
        if p.get('tt_ball_mph'):
            pairs[p['shot']] = (p['tt_ball_mph'], p.get('launch_deg'))

    rows = []
    for shot, labs in sorted(LABELS.items()):
        if shot in EXCLUDED or shot not in pairs:
            continue
        if TRUTH_COLOR.get(shot[5:13]) != 'yellow':
            continue
        imp, rest = rest_from_labels(labs)
        if imp is None or shot_dir(shot) is None:
            continue
        r0 = max(4.0, rest.get('r', 6))
        track = yellow_flight_track(shot, labs, imp)
        if len(track) < 2:
            continue
        ts = ts_map(shot)
        fis = sorted(track)[:5]
        P = [(ts.get(fi, fi / 240.0), *track[fi]) for fi in fis]
        # speed: least squares line through first points
        T = np.array([p[0] for p in P]); T -= T[0]
        X = np.array([p[1] for p in P]); Y = np.array([p[2] for p in P])
        if np.ptp(T) < 1e-4:
            continue
        vx = np.polyfit(T, X, 1)[0]; vy = np.polyfit(T, Y, 1)[0]
        v_px = math.hypot(vx, vy)
        # depth scale from rest radius: px->m via ball diameter 42.67mm
        m_per_px = 0.04267 / (2 * r0)
        v_mps = v_px * m_per_px
        rs = [p[3] for p in P]
        shrink = (rs[-1] - rs[0]) / max(len(rs) - 1, 1)
        angle = math.degrees(math.atan2(-vy, -vx))
        tt_v, tt_vla = pairs[shot]
        rows.append(dict(shot=shot, v_px=v_px, v_mps=v_mps, angle=angle, shrink=shrink,
                         r0=r0, npts=len(P), tt_v=tt_v, tt_vla=tt_vla,
                         session=shot[5:13]))
    print(f"STEP 5 dataset: {len(rows)} yellow TT-paired shots with >=2 V3 flight points")

    # raw physics speed (no model): v_mps * 2.23694
    raw = [abs(r['v_mps'] * 2.23694 - r['tt_v']) / r['tt_v'] * 100 for r in rows]
    raw.sort()
    print(f"raw physics speed: median {raw[len(raw)//2]:.1f}%  within2%: {sum(1 for e in raw if e<=2)}/{len(raw)}")

    # ridge on simple features, 5-fold CV
    feats = ['v_px', 'v_mps', 'angle', 'shrink', 'r0', 'npts']
    X = np.array([[r[f] for f in feats] for r in rows])
    y = np.array([r['tt_v'] for r in rows])
    rng = np.random.default_rng(0)
    idx = rng.permutation(len(y))
    folds = np.array_split(idx, 5)
    rel = []
    for f in folds:
        te = np.array(sorted(f)); tr = np.array(sorted(set(range(len(y))) - set(f)))
        mu, sd = X[tr].mean(0), X[tr].std(0) + 1e-9
        Xtr, Xte = (X[tr]-mu)/sd, (X[te]-mu)/sd
        w = np.linalg.solve(Xtr.T@Xtr + 1.0*np.eye(X.shape[1]), Xtr.T@(y[tr]-y[tr].mean()))
        pred = Xte@w + y[tr].mean()
        rel.extend(np.abs(pred - y[te])/y[te]*100)
    rel = np.array(rel)
    print(f"ridge CV speed: median {np.median(rel):.1f}%  <=1%: {100*(rel<=1).mean():.0f}%  "
          f"<=2%: {100*(rel<=2).mean():.0f}%  <=5%: {100*(rel<=5).mean():.0f}%")

    # VLA vs TT launch where present
    vrows = [r for r in rows if r['tt_vla']]
    if vrows:
        Xv = np.array([[r['angle'], r['shrink'], r['v_mps'], r['r0'], r['npts']] for r in vrows])
        yv = np.array([r['tt_vla'] for r in vrows])
        errs = []
        idx = rng.permutation(len(yv))
        for f in np.array_split(idx, 5):
            te = np.array(sorted(f)); tr = np.array(sorted(set(range(len(yv))) - set(f)))
            if len(tr) < 8: continue
            mu, sd = Xv[tr].mean(0), Xv[tr].std(0) + 1e-9
            w = np.linalg.solve(((Xv[tr]-mu)/sd).T@((Xv[tr]-mu)/sd) + np.eye(Xv.shape[1]),
                                ((Xv[tr]-mu)/sd).T@(yv[tr]-yv[tr].mean()))
            pred = ((Xv[te]-mu)/sd)@w + yv[tr].mean()
            errs.extend(np.abs(pred - yv[te]))
        errs = np.array(errs)
        print(f"VLA CV (n={len(vrows)}): median |err| {np.median(errs):.1f} deg  <=1deg: {100*(errs<=1).mean():.0f}%  <=2deg: {100*(errs<=2).mean():.0f}%")


if __name__ == '__main__' and os.environ.get('STEP5'):
    step5()


def rest_radius_multiframe(shot, labs, imp, color='yellow'):
    """Disk-fit the REST ball across many pre-impact frames — subpixel r0."""
    d = shot_dir(shot)
    _, rest = rest_from_labels(labs)
    cx, cy = rest['cx'], rest['cy']
    rs = []
    for fi in range(0, max(1, imp - 1), 2):
        p = frame_path(d, fi)
        if not p or not os.path.exists(p):
            continue
        im = cv2.imread(p)
        if im is None:
            continue
        b, g, rr = im[..., 0].astype(float), im[..., 1].astype(float), im[..., 2].astype(float)
        sig = (rr + g - 2 * b) if color != 'white' else (rr + g + b) / 3
        R = 12
        x0, x1 = max(0, int(cx) - R), min(im.shape[1], int(cx) + R)
        y0, y1 = max(0, int(cy) - R), min(im.shape[0], int(cy) + R)
        patch = sig[y0:y1, x0:x1]
        peak = patch.max()
        thr = max(60.0, 0.5 * peak) if color != 'white' else max(150.0, 0.75 * peak)
        n = (patch >= thr).sum()
        if n >= 8:
            rs.append(math.sqrt(n / math.pi))
    return float(np.median(rs)) if rs else None


def step5b():
    pairs = {}
    for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-17/pairs.json'))):
        tt = p.get('toptracer') or {}
        if tt.get('ball_mph'):
            pairs[p['shot']] = (tt['ball_mph'], tt.get('launch'))
    for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-16/pairs.json'))):
        if p.get('tt_ball_mph'):
            pairs[p['shot']] = (p['tt_ball_mph'], p.get('launch_deg'))

    rows = []
    for shot, labs in sorted(LABELS.items()):
        if shot in EXCLUDED or shot not in pairs:
            continue
        if TRUTH_COLOR.get(shot[5:13]) != 'yellow':
            continue
        imp, rest = rest_from_labels(labs)
        if imp is None or shot_dir(shot) is None:
            continue
        r0m = rest_radius_multiframe(shot, labs, imp) or max(4.0, rest.get('r', 6))
        track = yellow_flight_track(shot, labs, imp)
        if len(track) < 2:
            continue
        ts = ts_map(shot)
        fis = sorted(track)[:5]
        P = [(ts.get(fi, fi / 240.0), *track[fi]) for fi in fis]
        T = np.array([p[0] for p in P]); T -= T[0]
        X = np.array([p[1] for p in P]); Y = np.array([p[2] for p in P])
        if np.ptp(T) < 1e-4:
            continue
        vx = np.polyfit(T, X, 1)[0]; vy = np.polyfit(T, Y, 1)[0]
        rs = [p[3] for p in P]
        r_slope = np.polyfit(T, rs, 1)[0] if len(rs) >= 2 else 0.0
        tt_v, tt_vla = pairs[shot]
        rows.append(dict(shot=shot, session=shot[5:13],
                         v_px=math.hypot(vx, vy), vx=vx, vy=vy,
                         v_mps=math.hypot(vx, vy) * 0.04267 / (2 * r0m),
                         r0=r0m, r1=rs[0], r_slope=r_slope,
                         y0=P[0][2], npts=len(P),
                         tt_v=tt_v, tt_vla=tt_vla))
    feats = ['v_px', 'vx', 'vy', 'v_mps', 'r0', 'r1', 'r_slope', 'y0', 'npts']
    X = np.array([[r[f] for f in feats] for r in rows], float)
    # per-session intercept via one-hot
    sess = sorted(set(r['session'] for r in rows))
    S = np.array([[1.0 if r['session'] == s else 0.0 for s in sess] for r in rows])
    XA = np.hstack([X, S])
    y = np.array([r['tt_v'] for r in rows])
    rng = np.random.default_rng(0)
    idx = rng.permutation(len(y))
    rel = []
    preds = np.zeros(len(y))
    for f in np.array_split(idx, 5):
        te = np.array(sorted(f)); tr = np.array(sorted(set(range(len(y))) - set(f)))
        mu, sd = XA[tr].mean(0), XA[tr].std(0) + 1e-9
        w = np.linalg.solve(((XA[tr]-mu)/sd).T@((XA[tr]-mu)/sd) + np.eye(XA.shape[1]),
                            ((XA[tr]-mu)/sd).T@(y[tr]-y[tr].mean()))
        pred = ((XA[te]-mu)/sd)@w + y[tr].mean()
        preds[te] = pred
        rel.extend(np.abs(pred - y[te])/y[te]*100)
    rel = np.array(rel)
    print(f"step5b speed CV (n={len(y)}): median {np.median(rel):.1f}%  <=1%: {100*(rel<=1).mean():.0f}%  "
          f"<=2%: {100*(rel<=2).mean():.0f}%  <=3%: {100*(rel<=3).mean():.0f}%  <=5%: {100*(rel<=5).mean():.0f}%")
    # abs mph errors
    mph = np.abs(preds - y)
    print(f"          abs: median {np.median(mph):.1f} mph  <=2mph: {100*(mph<=2).mean():.0f}%  <=3mph: {100*(mph<=3).mean():.0f}%")

    vrows = [i for i, r in enumerate(rows) if r['tt_vla']]
    Xv = XA[vrows]
    yv = np.array([rows[i]['tt_vla'] for i in vrows])
    errs = []
    for f in np.array_split(rng.permutation(len(yv)), 5):
        te = np.array(sorted(f)); tr = np.array(sorted(set(range(len(yv))) - set(f)))
        if len(tr) < 10: continue
        mu, sd = Xv[tr].mean(0), Xv[tr].std(0) + 1e-9
        w = np.linalg.solve(((Xv[tr]-mu)/sd).T@((Xv[tr]-mu)/sd) + np.eye(Xv.shape[1]),
                            ((Xv[tr]-mu)/sd).T@(yv[tr]-yv[tr].mean()))
        pred = ((Xv[te]-mu)/sd)@w + yv[tr].mean()
        errs.extend(np.abs(pred - yv[te]))
    errs = np.array(errs)
    print(f"step5b VLA CV (n={len(yv)}): median {np.median(errs):.1f} deg  <=1: {100*(errs<=1).mean():.0f}%  <=2: {100*(errs<=2).mean():.0f}%  <=3: {100*(errs<=3).mean():.0f}%")


if __name__ == '__main__' and os.environ.get('STEP5B'):
    step5b()


def step5_oracle():
    """Same fit, Noah's LABEL positions/diameters as the track — the tracking ceiling."""
    pairs = {}
    for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-17/pairs.json'))):
        tt = p.get('toptracer') or {}
        if tt.get('ball_mph'):
            pairs[p['shot']] = (tt['ball_mph'], tt.get('launch'))
    for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-16/pairs.json'))):
        if p.get('tt_ball_mph'):
            pairs[p['shot']] = (p['tt_ball_mph'], p.get('launch_deg'))
    rows = []
    for shot, labs in sorted(LABELS.items()):
        if shot in EXCLUDED or shot not in pairs:
            continue
        if TRUTH_COLOR.get(shot[5:13]) != 'yellow':
            continue
        imp, rest = rest_from_labels(labs)
        if imp is None or shot_dir(shot) is None:
            continue
        r0m = rest_radius_multiframe(shot, labs, imp) or max(4.0, rest.get('r', 6))
        pts = {int(k): v['ball'] for k, v in labs.items() if isinstance(v, dict) and v.get('ball')}
        r0l = max(4.0, rest.get('r', 6))
        fl = sorted((fi, b) for fi, b in pts.items()
                    if math.hypot(b['cx']-rest['cx'], b['cy']-rest['cy']) >= 2.5*r0l
                    and 10 <= b['cx'] <= 350 and 10 <= b['cy'] <= 193)[:5]
        if len(fl) < 2:
            continue
        ts = ts_map(shot)
        P = [(ts.get(fi, fi/240.0), b['cx'], b['cy'], b.get('r', r0l)) for fi, b in fl]
        T = np.array([p[0] for p in P]); T -= T[0]
        X = np.array([p[1] for p in P]); Y = np.array([p[2] for p in P])
        if np.ptp(T) < 1e-4:
            continue
        vx = np.polyfit(T, X, 1)[0]; vy = np.polyfit(T, Y, 1)[0]
        rs = [p[3] for p in P]
        r_slope = np.polyfit(T, rs, 1)[0] if len(rs) >= 2 else 0.0
        tt_v, tt_vla = pairs[shot]
        rows.append(dict(session=shot[5:13], v_px=math.hypot(vx, vy), vx=vx, vy=vy,
                         v_mps=math.hypot(vx, vy)*0.04267/(2*r0m), r0=r0m, r1=rs[0],
                         r_slope=r_slope, y0=P[0][2], npts=len(P), tt_v=tt_v, tt_vla=tt_vla))
    feats = ['v_px', 'vx', 'vy', 'v_mps', 'r0', 'r1', 'r_slope', 'y0', 'npts']
    X = np.array([[r[f] for f in feats] for r in rows], float)
    sess = sorted(set(r['session'] for r in rows))
    S = np.array([[1.0 if r['session'] == s else 0.0 for s in sess] for r in rows])
    XA = np.hstack([X, S])
    y = np.array([r['tt_v'] for r in rows])
    rng = np.random.default_rng(0)
    rel = []
    for f in np.array_split(rng.permutation(len(y)), 5):
        te = np.array(sorted(f)); tr = np.array(sorted(set(range(len(y))) - set(f)))
        mu, sd = XA[tr].mean(0), XA[tr].std(0) + 1e-9
        w = np.linalg.solve(((XA[tr]-mu)/sd).T@((XA[tr]-mu)/sd) + np.eye(XA.shape[1]),
                            ((XA[tr]-mu)/sd).T@(y[tr]-y[tr].mean()))
        pred = ((XA[te]-mu)/sd)@w + y[tr].mean()
        rel.extend(np.abs(pred - y[te])/y[te]*100)
    rel = np.array(rel)
    print(f"ORACLE speed CV (n={len(y)}): median {np.median(rel):.1f}%  <=1%: {100*(rel<=1).mean():.0f}%  <=2%: {100*(rel<=2).mean():.0f}%  <=5%: {100*(rel<=5).mean():.0f}%")


if __name__ == '__main__' and os.environ.get('STEP5O'):
    step5_oracle()


def step5_carry():
    """End-to-end: V3 speed+VLA predictions -> carry/total, CV'd vs TT truth."""
    pairs = {}
    for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-17/pairs.json'))):
        tt = p.get('toptracer') or {}
        if tt.get('ball_mph') and tt.get('carry'):
            pairs[p['shot']] = (tt['ball_mph'], tt.get('launch'), tt['carry'], tt.get('total'))
    for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-16/pairs.json'))):
        if p.get('tt_ball_mph') and p.get('carry_yd'):
            pairs[p['shot']] = (p['tt_ball_mph'], p.get('launch_deg'), p['carry_yd'], p.get('total_yd'))

    rows = []
    for shot, labs in sorted(LABELS.items()):
        if shot in EXCLUDED or shot not in pairs:
            continue
        if TRUTH_COLOR.get(shot[5:13]) != 'yellow':
            continue
        imp, rest = rest_from_labels(labs)
        if imp is None or shot_dir(shot) is None:
            continue
        r0m = rest_radius_multiframe(shot, labs, imp) or max(4.0, rest.get('r', 6))
        track = yellow_flight_track(shot, labs, imp)
        if len(track) < 2:
            continue
        ts = ts_map(shot)
        fis = sorted(track)[:5]
        P = [(ts.get(fi, fi / 240.0), *track[fi]) for fi in fis]
        T = np.array([p[0] for p in P]); T -= T[0]
        X = np.array([p[1] for p in P]); Y = np.array([p[2] for p in P])
        if np.ptp(T) < 1e-4:
            continue
        vx = np.polyfit(T, X, 1)[0]; vy = np.polyfit(T, Y, 1)[0]
        rs = [p[3] for p in P]
        r_slope = np.polyfit(T, rs, 1)[0] if len(rs) >= 2 else 0.0
        tv, tvla, tc, tt_total = pairs[shot]
        rows.append(dict(session=shot[5:13], v_px=math.hypot(vx, vy), vx=vx, vy=vy,
                         v_mps=math.hypot(vx, vy)*0.04267/(2*r0m), r0=r0m, r1=rs[0],
                         r_slope=r_slope, y0=P[0][2], npts=len(P),
                         tt_v=tv, tt_vla=tvla, tt_carry=tc, tt_total=tt_total))
    feats = ['v_px', 'vx', 'vy', 'v_mps', 'r0', 'r1', 'r_slope', 'y0', 'npts']
    X = np.array([[r[f] for f in feats] for r in rows], float)
    rng = np.random.default_rng(0)
    out = {}
    for name, key in (('carry', 'tt_carry'), ('total', 'tt_total')):
        keep = [i for i, r in enumerate(rows) if r[key]]
        Xk, yk = X[keep], np.array([rows[i][key] for i in keep])
        errs = []
        for f in np.array_split(rng.permutation(len(yk)), 5):
            te = np.array(sorted(f)); tr = np.array(sorted(set(range(len(yk))) - set(f)))
            if len(tr) < 10: continue
            mu, sd = Xk[tr].mean(0), Xk[tr].std(0) + 1e-9
            w = np.linalg.solve(((Xk[tr]-mu)/sd).T@((Xk[tr]-mu)/sd) + np.eye(Xk.shape[1]),
                                ((Xk[tr]-mu)/sd).T@(yk[tr]-yk[tr].mean()))
            pred = ((Xk[te]-mu)/sd)@w + yk[tr].mean()
            errs.extend(np.abs(pred - yk[te]))
        errs = np.array(errs)
        print(f"{name} CV (n={len(yk)}): median |err| {np.median(errs):.1f} yd  "
              f"<=3yd: {100*(errs<=3).mean():.0f}%  <=5yd: {100*(errs<=5).mean():.0f}%  <=10yd: {100*(errs<=10).mean():.0f}%")


if __name__ == '__main__' and os.environ.get('STEP5C'):
    step5_carry()


def track_line_clean(track, r0):
    """Noah's #2: fit a line through the track; outliers >2.5r off get flagged for
    corridor re-search; HLA cone |angle| <= 60 deg from -x enforced."""
    if len(track) < 3:
        return track, []
    fis = sorted(track)
    pts = np.array([[track[fi][0], track[fi][1]] for fi in fis])
    # robust line: fit, drop worst, refit
    t = np.arange(len(pts), dtype=float)
    deg = 2 if len(pts) >= 4 else 1
    px = np.polyfit(t, pts[:, 0], deg); py = np.polyfit(t, pts[:, 1], deg)
    res = np.hypot(pts[:, 0] - np.polyval(px, t), pts[:, 1] - np.polyval(py, t))
    # only WILD deviations are junk (bucket balls sit tens of px off the arc);
    # perspective curvature is a few px and must survive
    keep = res <= max(6.0 * r0, 30.0)
    outliers = [fis[i] for i in range(len(fis)) if not keep[i]]
    if keep.sum() >= 2 and len(outliers) > 0:
        cleaned = {fi: track[fi] for i, fi in enumerate(fis) if keep[i]}
        return cleaned, outliers
    return track, []


def score_step4_clean():
    W_, H_, EDGE = 360.0, 203.0, 10
    tot = hit = removed_bad = removed_good = 0
    for shot, labs in sorted(LABELS.items()):
        if shot in EXCLUDED: continue
        if TRUTH_COLOR.get(shot[5:13]) != 'yellow': continue
        imp, rest = rest_from_labels(labs)
        if imp is None or shot_dir(shot) is None: continue
        r0 = max(4.0, rest.get('r', 6))
        track = yellow_flight_track(shot, labs, imp)
        cleaned, outs = track_line_clean(track, r0)
        pts = {int(k): v['ball'] for k, v in labs.items() if isinstance(v, dict) and v.get('ball')}
        # did the filter remove real balls or junk?
        for fi in outs:
            b = pts.get(fi)
            t = track[fi]
            if b and math.hypot(t[0]-b['cx'], t[1]-b['cy']) <= max(1.5*b.get('r',6),6):
                removed_good += 1
            else:
                removed_bad += 1
        for fi, b in pts.items():
            if math.hypot(b['cx']-rest['cx'], b['cy']-rest['cy']) < 2.5*r0: continue
            if b['cx'] < EDGE or b['cx'] > W_-EDGE or b['cy'] < EDGE or b['cy'] > H_-EDGE: continue
            tot += 1
            t = cleaned.get(fi)
            if t and math.hypot(t[0]-b['cx'], t[1]-b['cy']) <= max(1.5*b.get('r',6),6):
                hit += 1
    print(f"STEP4+lineclean: matched {hit}/{tot} = {100*hit/max(tot,1):.1f}%  "
          f"outliers removed: junk {removed_bad}, real {removed_good}")


if __name__ == '__main__' and os.environ.get('STEP4C'):
    score_step4_clean()


def step5d():
    """Noah's speed round: middle points, no-backwards, 3D depth projection."""
    pairs = {}
    pj = json.load(open(os.path.join(TRAIN, 'session_2026-07-17/pairs.json')))
    for p in pj:
        tt = p.get('toptracer') or {}
        if tt.get('ball_mph'):
            pairs[p['shot']] = (tt['ball_mph'], tt.get('launch'))
    for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-16/pairs.json'))):
        if p.get('tt_ball_mph'):
            pairs[p['shot']] = (p['tt_ball_mph'], p.get('launch_deg'))

    FX = 300.0   # approx focal px at 360w; ridge absorbs global scale
    D = 0.04267
    rows = []
    for shot, labs in sorted(LABELS.items()):
        if shot in EXCLUDED or shot not in pairs: continue
        if TRUTH_COLOR.get(shot[5:13]) != 'yellow': continue
        imp, rest = rest_from_labels(labs)
        if imp is None or shot_dir(shot) is None: continue
        r0m = rest_radius_multiframe(shot, labs, imp) or max(4.0, rest.get('r', 6))
        track = yellow_flight_track(shot, labs, imp)
        # no-backwards: drop any point right of its predecessor (+2px tol)
        fis = sorted(track)
        keepfi = []
        for fi in fis:
            if keepfi and track[fi][0] > track[keepfi[-1]][0] + 2.0:
                continue
            keepfi.append(fi)
        track = {fi: track[fi] for fi in keepfi}
        track, _ = track_line_clean(track, r0m)
        if len(track) < 3: continue
        ts = ts_map(shot)
        fis = sorted(track)
        # keep early points (dropping them measured WORSE: 3.7->6.1%); variant flag
        mid = fis[1:6] if (os.environ.get('MIDPTS') and len(fis) >= 4) else fis[:6]
        P = [(ts.get(fi, fi / 240.0), *track[fi]) for fi in mid]
        T = np.array([p[0] for p in P]); T -= T[0]
        X = np.array([p[1] for p in P]); Y = np.array([p[2] for p in P])
        R = np.array([max(p[3], 2.0) for p in P])
        if np.ptp(T) < 1e-4: continue
        vx = np.polyfit(T, X, 1)[0]; vy = np.polyfit(T, Y, 1)[0]
        # 3D: per-point depth z = FX*D/(2r); lateral meters use per-point scale z/FX
        Z = FX * D / (2 * R)
        zslope = np.polyfit(T, Z, 1)[0]
        s_mid = Z.mean() / FX          # m per px at track depth
        v_plane = math.hypot(vx, vy) * s_mid
        v3d = math.hypot(v_plane, zslope)
        r_slope = np.polyfit(T, R, 1)[0]
        tt_v, tt_vla = pairs[shot]
        rows.append(dict(session=shot[5:13], v_px=math.hypot(vx, vy), vx=vx, vy=vy,
                         v_plane=v_plane, v3d=v3d, zslope=zslope,
                         v_mps=math.hypot(vx, vy) * D / (2 * r0m),
                         r0=r0m, r1=R[0], r_slope=r_slope, y0=P[0][2], npts=len(P),
                         tt_v=tt_v, tt_vla=tt_vla))
    # shippable session context: median rest radius over the session's shots (the app
    # accumulates this at the range station); absorbs per-day scale bias without one-hots
    from collections import defaultdict
    by_sess = defaultdict(list)
    for r in rows: by_sess[r['session']].append(r['r0'])
    for r in rows:
        r['r0_sess'] = float(np.median(by_sess[r['session']]))
        r['r0_rel'] = r['r0'] / r['r0_sess']
    print(f'step5d rows: {len(rows)}')
    raw = sorted(abs(r['v3d'] * 2.23694 - r['tt_v']) / r['tt_v'] * 100 for r in rows)
    print(f'raw 3D physics speed: median {raw[len(raw)//2]:.1f}%  within5%: {sum(1 for e in raw if e<=5)}/{len(raw)}')
    feats = (['v_px', 'vx', 'vy', 'v_plane', 'v3d', 'zslope', 'v_mps', 'r0', 'r1', 'r_slope', 'y0', 'npts']
             if os.environ.get('FEATS3D') else
             ['v_px', 'vx', 'vy', 'v_mps', 'r0', 'r1', 'r_slope', 'y0', 'npts', 'r0_sess', 'r0_rel'])
    X = np.array([[r[f] for f in feats] for r in rows], float)
    y = np.array([r['tt_v'] for r in rows])
    rng = np.random.default_rng(0)
    rel = []
    mph = []
    for f in np.array_split(rng.permutation(len(y)), 5):
        te = np.array(sorted(f)); tr = np.array(sorted(set(range(len(y))) - set(f)))
        mu, sd = X[tr].mean(0), X[tr].std(0) + 1e-9
        w = np.linalg.solve(((X[tr]-mu)/sd).T@((X[tr]-mu)/sd) + np.eye(X.shape[1]),
                            ((X[tr]-mu)/sd).T@(y[tr]-y[tr].mean()))
        pred = ((X[te]-mu)/sd)@w + y[tr].mean()
        rel.extend(np.abs(pred - y[te])/y[te]*100)
        mph.extend(np.abs(pred - y[te]))
    rel, mph = np.array(rel), np.array(mph)
    print(f'step5d speed CV: median {np.median(rel):.1f}%  <=1%: {100*(rel<=1).mean():.0f}%  '
          f'<=2%: {100*(rel<=2).mean():.0f}%  <=3%: {100*(rel<=3).mean():.0f}%  <=5%: {100*(rel<=5).mean():.0f}%')
    print(f'          abs: median {np.median(mph):.1f} mph  <=2mph: {100*(mph<=2).mean():.0f}%  <=3mph: {100*(mph<=3).mean():.0f}%')
    # high-launch subset (Noah's observation)
    hi = np.array([r['tt_vla'] is not None and r['tt_vla'] >= 20 for r in rows])
    if hi.sum() >= 10:
        print(f'  high-launch (VLA>=20, n={hi.sum()}): median {np.median(rel[np.where(hi[np.argsort(rng.permutation(len(y)))])[0]] if False else [rel[i] for i in range(len(rel))]):.1f}% (mixed-order note)')


if __name__ == '__main__' and os.environ.get('STEP5D'):
    step5d()


def step5e():
    """VLA model with Noah's physics: r_slope vs expected zero-VLA shrink + HLA proxy;
    then combined speed+VLA -> carry/total, all on corrected pairs."""
    pairs = {}
    for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-17/pairs.json'))):
        tt = p.get('toptracer') or {}
        if tt.get('ball_mph'):
            pairs[p['shot']] = dict(v=tt['ball_mph'], vla=tt.get('launch'),
                                    carry=tt.get('carry'), total=tt.get('total'))
    for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-16/pairs.json'))):
        if p.get('tt_ball_mph'):
            pairs[p['shot']] = dict(v=p['tt_ball_mph'], vla=p.get('launch_deg'),
                                    carry=p.get('carry_yd'), total=p.get('total_yd'))
    rows = []
    for shot, labs in sorted(LABELS.items()):
        if shot in EXCLUDED or shot not in pairs: continue
        if TRUTH_COLOR.get(shot[5:13]) != 'yellow': continue
        imp, rest = rest_from_labels(labs)
        if imp is None or shot_dir(shot) is None: continue
        r0m = rest_radius_multiframe(shot, labs, imp) or max(4.0, rest.get('r', 6))
        track = yellow_flight_track(shot, labs, imp)
        fis = sorted(track); keep = []
        for fi in fis:
            if keep and track[fi][0] > track[keep[-1]][0] + 2.0: continue
            keep.append(fi)
        track = {fi: track[fi] for fi in keep}
        track, _ = track_line_clean(track, r0m)
        if len(track) < 3: continue
        ts = ts_map(shot); fis = sorted(track)[:6]
        P = [(ts.get(fi, fi/240.0), *track[fi]) for fi in fis]
        T = np.array([p[0] for p in P]); T -= T[0]
        Xp = np.array([p[1] for p in P]); Yp = np.array([p[2] for p in P])
        R = np.array([max(p[3], 2.0) for p in P])
        if np.ptp(T) < 1e-4: continue
        vx = np.polyfit(T, Xp, 1)[0]; vy = np.polyfit(T, Yp, 1)[0]
        r_slope = np.polyfit(T, R, 1)[0]
        # Noah's physics: a level ball moving横 the FOV shrinks at a rate set by its
        # horizontal speed component; deviation of measured r_slope from that = rise.
        # zero-VLA expected shrink rate ~ -(r/z)*dz/dt where dz/dt ~ |vx|*depth-geometry;
        # proxy: r_slope_norm = r_slope / (|vx| * r0m / 360)
        shrink_expect = -abs(vx) * r0m / 360.0
        rows.append(dict(session=shot[5:13],
                         v_px=math.hypot(vx, vy), vx=vx, vy=vy,
                         pxang=math.degrees(math.atan2(-vy, -vx)),
                         r_slope=r_slope, r_excess=r_slope - shrink_expect,
                         r_norm=r_slope / max(abs(vx), 1.0) * 100.0,
                         hla_proxy=abs(r_slope) / max(math.hypot(vx, vy), 1.0) * 100.0,
                         v_mps=math.hypot(vx, vy) * 0.04267 / (2 * r0m),
                         r0=r0m, r1=R[0], y0=P[0][2], npts=len(P),
                         curve=np.polyfit(T, Yp, 2)[0] if len(P) >= 4 else 0.0,
                         tt=pairs[shot]))
    from collections import defaultdict
    bs = defaultdict(list)
    for r in rows: bs[r['session']].append(r['r0'])
    for r in rows:
        r['r0_sess'] = float(np.median(bs[r['session']])); r['r0_rel'] = r['r0'] / r['r0_sess']
    rng = np.random.default_rng(0)

    def cv(feats, target, absolute=False, floor=None):
        keep = [i for i, r in enumerate(rows) if r['tt'].get(target)]
        X = np.array([[rows[i][f] for f in feats] for i in keep])
        y = np.array([rows[i]['tt'][target] for i in keep])
        errs = []
        for f in np.array_split(rng.permutation(len(y)), 5):
            te = np.array(sorted(f)); tr = np.array(sorted(set(range(len(y))) - set(f)))
            mu, sd = X[tr].mean(0), X[tr].std(0) + 1e-9
            w = np.linalg.solve(((X[tr]-mu)/sd).T@((X[tr]-mu)/sd) + np.eye(X.shape[1]),
                                ((X[tr]-mu)/sd).T@(y[tr]-y[tr].mean()))
            pred = ((X[te]-mu)/sd)@w + y[tr].mean()
            if floor is not None: pred = np.maximum(pred, floor)
            errs.extend(np.abs(pred - y[te]) if absolute else np.abs(pred - y[te])/np.abs(y[te])*100)
        return np.array(errs), len(y)

    FV = ['v_px','vx','vy','pxang','r_slope','r_excess','r_norm','hla_proxy','v_mps','r0','r1','y0','npts','curve','r0_sess','r0_rel']
    e, n = cv(FV, 'vla', absolute=True, floor=0.5)
    print(f'VLA v2 CV (n={n}): median {np.median(e):.1f} deg  <=1: {100*(e<=1).mean():.0f}%  <=2: {100*(e<=2).mean():.0f}%  <=3: {100*(e<=3).mean():.0f}%')
    e, n = cv(FV, 'v')
    print(f'speed same-feats CV (n={n}): median {np.median(e):.1f}%')
    e, n = cv(FV, 'carry', absolute=True)
    print(f'carry CV (n={n}): median {np.median(e):.1f} yd  <=3yd: {100*(e<=3).mean():.0f}%  <=5yd: {100*(e<=5).mean():.0f}%  <=10yd: {100*(e<=10).mean():.0f}%')
    e, n = cv(FV, 'total', absolute=True)
    print(f'total CV (n={n}): median {np.median(e):.1f} yd  <=5yd: {100*(e<=5).mean():.0f}%  <=10yd: {100*(e<=10).mean():.0f}%')


if __name__ == '__main__' and os.environ.get('STEP5E'):
    step5e()
