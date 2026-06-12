#!/usr/bin/env python3
"""
Club Tracking Lab — simplified frame-diff club head detector.

Methods:
  absDiff  — |frame[t] - frame[t-1]|  shows both current AND previous club positions
  posDiff  — max(0, frame[t] - frame[t-1])  pixels that got BRIGHTER → current pos for bright club
  negDiff  — max(0, frame[t-1] - frame[t])  pixels that got DARKER  → current pos for dark club

In posDiff/negDiff only ONE of the two ghost positions appears, so the closest blob to the ball
is always the current club head (not the background reveal from the old position).

Keyboard:
  ← / →   prev / next frame        [ / ]   prev / next shot
  i        jump to impact           r       run all club-window frames + compute metrics
  l        toggle label mode        s       save labels
  e        batch eval               p       dump current state to JSON (paste to Claude)

Usage:
  python3 club_lab.py /path/to/folder/with/ShotExport_dirs
"""
import sys, os, glob, json, math, subprocess
from collections import deque
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use("MacOSX")
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.widgets import Slider, Button, RadioButtons
from PIL import Image

# ─────────────────────────────────────────────────────────────────────────────
LABELS_FILE   = Path(__file__).parent / "club_labels.json"
STATE_FILE    = Path(__file__).parent / "club_lab_state.json"
WEIGHTS_FILE  = Path(__file__).parent / "ensemble_weights.json"
METHODS = ["absDiff", "posDiff", "negDiff", "baseline",
           "optFlow", "bgDiff", "streak", "streakBFS", "brightBFS", "newDiff",
           "ensembleBFS", "posStreak", "hsvDiff", "ransac", "ensemble"]

# BFS methods: map method name → underlying mask computation used for the
# mask display panel.  ensembleBFS shows the newDiff (bgDiff) map as primary.
_BFS_MASK_METHOD = {
    "streakBFS":   "streak",
    "brightBFS":   "baseline",
    "newDiff":     "bgDiff",
    "ensembleBFS": "bgDiff",   # display uses newDiff mask; detection blends both
}

# Per-method reliability weights learned by train_ensemble().
# Keys are method names; values are normalised inverse-error weights.
_method_weights: dict = {}

# Pre-swing background baselines cached per shot name.
# "baseline" method compares each frame against this instead of frame-t-1.
_baseline_cache: dict = {}

# Window-average background (all frames in the detection window).
# "bgDiff" method compares each frame against this.
_window_bg_cache: dict = {}

# Trail dot color per detection pass (0=current params, 1=small, 2=large)
# Trail dot colors by pass
_PASS_COLORS = {1: "#ff9900", 2: "#ff44aa", 3: "#44aaff", 4: "#44ff88"}

DEFAULT_P = dict(
    diff_thresh=7.731,
    min_area=123.1,
    max_area=7470.0,
    max_aspect=2.2,
    exclusion=1.003,
    roi_x=22.0,
    roi_y=6.0,
    dilate=2.512,
    # Temporal filter (applied after run_all)
    max_resid_px=62.4,
    skip_near_impact=1.98,
    # Calibration
    fov_x=70.0,
    fov_y=45.0,
    ball_diam_m=0.04276,
    zero_deg=0.0,
)

# ─────────────────────────────────────────────────────────────────────────────
# Shot loading
# ─────────────────────────────────────────────────────────────────────────────

def discover_shots(root):
    return sorted(f for f in glob.glob(os.path.join(root, "ShotExport_*")) if os.path.isdir(f))


def load_shot(folder):
    png_paths = sorted(glob.glob(os.path.join(folder, "frame_*.png")))
    if not png_paths: return None
    frames = [np.array(Image.open(p).convert("RGB")) for p in png_paths]
    H, W = frames[0].shape[:2]

    meta = {}
    mp = os.path.join(folder, "metadata.json")
    if os.path.exists(mp): meta = json.load(open(mp))
    impact = int(meta.get("impact_frame_index", 20))
    fps    = float(meta.get("fps_estimate", 240) or 240)

    ball_obs = {}
    tp = os.path.join(folder, "tracking.json")
    if os.path.exists(tp):
        for o in json.load(open(tp)).get("observations", []):
            fi = int(o.get("frame_index", o.get("frameIndex", 0)))
            if o.get("detected") or float(o.get("confidence", 0)) > 0:
                ball_obs[fi] = dict(
                    cx=float(o["center_x"]), cy=float(o["center_y"]),
                    dia=float(o["diameter"]), conf=float(o.get("confidence", 1.0)),
                )

    precomputed = None
    ball_depth_m = None   # 3D depth of ball at impact, when available
    ep = os.path.join(folder, "python_experimental_metrics.json")
    if os.path.exists(ep):
        precomputed = json.load(open(ep))
        if "detectedImpactFrameIndex" in precomputed:
            impact = int(precomputed["detectedImpactFrameIndex"])
        # Extract ball depth from 3D observations near impact — more accurate than
        # deriving depth from pixel diameter, which is sensitive to detection size.
        b3d = precomputed.get("ball3DObservations") or []
        if b3d:
            closest = min(b3d, key=lambda o: abs(o["frameIndex"] - impact))
            z = (closest.get("positionMeters") or {}).get("z")
            if z and z > 0.1:
                ball_depth_m = float(z)

    return dict(folder=folder, name=os.path.basename(folder),
                frames=frames, H=H, W=W, N=len(frames),
                impact=impact, fps=fps, ball_obs=ball_obs,
                ball_depth_m=ball_depth_m,
                precomputed=precomputed)


def _ball_for_frame(shot, fi):
    b = shot["ball_obs"].get(fi)
    if b is None:
        nearby = sorted(shot["ball_obs"].items(), key=lambda kv: abs(kv[0]-fi))
        if nearby: b = nearby[0][1]
    return b

# ─────────────────────────────────────────────────────────────────────────────
# Detection
# ─────────────────────────────────────────────────────────────────────────────

def _roi_rect(ball_cx, ball_cy, ball_dia, p):
    rw = ball_dia * p["roi_x"]; rh = ball_dia * p["roi_y"]
    cx = ball_cx - rw * 0.40   # search to the left/behind the ball
    x0 = max(0.0, cx - rw/2); y0 = max(0.0, ball_cy - rh/2)
    return (x0, y0,
            max(0.0, min(1.0, cx+rw/2) - x0),
            max(0.0, min(1.0, ball_cy+rh/2) - y0))


def _get_patch(frames, fi, roi, W, H):
    x0n, y0n, wn, hn = roi
    x0 = max(0, int(x0n*W)); x1 = min(W, int((x0n+wn)*W))
    y0 = max(0, int(y0n*H)); y1 = min(H, int((y0n+hn)*H))
    if x1 <= x0 or y1 <= y0: return None, x0, y0
    return frames[fi][y0:y1, x0:x1], x0, y0


def _dilate(mask, n):
    if n <= 0: return mask
    m = mask.copy()
    for _ in range(int(n)):
        m[1:] |= m[:-1]; m[:-1] |= m[1:]
        m[:,1:] |= m[:,:-1]; m[:,:-1] |= m[:,1:]
    return m

def _erode(mask, n):
    if n <= 0: return mask
    m = mask.copy()
    for _ in range(int(n)):
        m[1:] &= m[:-1]; m[:-1] &= m[1:]
        m[:,1:] &= m[:,:-1]; m[:,:-1] &= m[:,1:]
    return m


def apply_opening(mask_result, n):
    """Re-apply morphological opening with a different radius to an already-computed mask.

    The base mask_result must have been built by build_mask (which stores the raw
    post-exclusion, pre-opening binary mask in mask_result["raw"]).  Only the opening
    step changes — the expensive diff/threshold computation is not repeated.
    """
    if mask_result is None: return None
    n = max(1, int(n))
    opened = _dilate(_erode(mask_result["raw"], n), n)
    return dict(mask_result, active=opened)


def _erase_ball(patch, cx_roi, cy_roi, dia_px, scale):
    """Fill ball disc (radius = dia_px*scale/2) with surrounding ring mean.

    This removes the ball's own pixels from both frames BEFORE diffing, so that
    ball movement (especially post-impact) cannot create false-positive blobs.
    The 'Excl×' slider controls the erase radius — same parameter, better use.
    """
    result = patch.copy()
    r2 = (dia_px * max(scale, 0.0) / 2) ** 2
    if r2 < 1: return result
    rows, cols = patch.shape[:2]
    rs = np.arange(rows, dtype=float); cs = np.arange(cols, dtype=float)
    ys_g, xs_g = np.meshgrid(rs, cs, indexing="ij")
    d2 = (xs_g - cx_roi)**2 + (ys_g - cy_roi)**2
    in_ball = d2 <= r2
    if not in_ball.any(): return result
    ring = (d2 <= r2 * 4.0) & ~in_ball
    fill = patch[ring].mean(axis=0) if ring.any() else patch.mean(axis=(0, 1))
    result[in_ball] = np.clip(fill, 0, 255).astype(np.uint8)
    return result


def _rgb_to_gray(patch: np.ndarray) -> np.ndarray:
    """RGB (H×W×3) → float32 grayscale (H×W) using standard luminance weights."""
    return (0.2989 * patch[:, :, 0].astype(np.float32)
          + 0.5870 * patch[:, :, 1].astype(np.float32)
          + 0.1140 * patch[:, :, 2].astype(np.float32))


def _get_baseline_frame(shot) -> np.ndarray | None:
    """Return a cached full-frame grayscale average of the first few pre-swing frames.

    Uses frames 0…N-1 where N = min(5, impact-4).  These are the truly static
    background frames before any club motion, giving a clean reference for the
    production-style delta approach.
    """
    key = shot.get("name", id(shot))
    if key in _baseline_cache:
        return _baseline_cache[key]

    frames = shot["frames"]
    impact = shot["impact"]
    n = min(5, max(1, impact - 4))
    if n < 1:
        _baseline_cache[key] = None
        return None

    stack = np.stack([_rgb_to_gray(frames[i]) for i in range(n)], axis=0)
    baseline = stack.mean(axis=0)          # float32, full frame
    _baseline_cache[key] = baseline
    return baseline


def _get_window_bg(shot, start, end) -> np.ndarray | None:
    """Return cached mean of all frames in [start, end] as a float32 grayscale.

    Used by bgDiff: every frame in the detection window contributes to the
    background, so only pixels that differ from the *whole window average* light up.
    """
    key = (shot.get("name", id(shot)), start, end)
    if key in _window_bg_cache:
        return _window_bg_cache[key]
    frames = shot["frames"]
    indices = list(range(max(0, start), min(shot["N"], end + 1)))
    if not indices:
        _window_bg_cache[key] = None
        return None
    stack = np.stack([_rgb_to_gray(frames[i]) for i in indices], axis=0)
    bg = stack.mean(axis=0)
    _window_bg_cache[key] = bg
    return bg


def build_mask(shot, fi, method, p, win_start=None, win_end=None):
    if fi == 0: return None
    ball = _ball_for_frame(shot, fi)
    if ball is None: return None
    W, H = shot["W"], shot["H"]

    roi = _roi_rect(ball["cx"], ball["cy"], ball["dia"], p)
    patch,  x0, y0 = _get_patch(shot["frames"], fi,   roi, W, H)
    patchP, _,  _  = _get_patch(shot["frames"], fi-1, roi, W, H)
    if patch is None or patchP is None or patch.shape != patchP.shape: return None

    rows, cols = patch.shape[:2]
    bx_roi = ball["cx"]*W - x0; by_roi = ball["cy"]*H - y0
    ball_dia_px = ball["dia"] * W

    # Compute near_impact early — needed for both erase and fill decisions.
    skip_imp    = int(round(p.get("skip_near_impact", 2)))
    near_impact = abs(fi - shot["impact"]) <= skip_imp

    # For near-impact frames skip _erase_ball entirely.  The ball is white and
    # both patches would get the same bright fill → grey−grey = 0, destroying the
    # club face signal right where we need it most.  The stationary ball cancels
    # naturally in the raw diff (white − white = 0); the club arriving/departing
    # the ball disc creates real |club − ball| signal that we want to keep.
    # For frames far from impact, erase as normal to suppress ball-movement noise.
    if near_impact:
        patch_c  = patch
        patchP_c = patchP
    else:
        patch_c  = _erase_ball(patch,  bx_roi, by_roi, ball_dia_px, 1.0)
        patchP_c = _erase_ball(patchP, bx_roi, by_roi, ball_dia_px, 1.0)

    # Frame diff on ball-erased patches
    d = patch_c.astype(np.int32) - patchP_c.astype(np.int32)
    if   method == "absDiff": diff_map = np.abs(d).mean(axis=2)
    elif method == "posDiff": diff_map = np.clip(d,  0, None).mean(axis=2).astype(float)
    elif method == "negDiff": diff_map = np.clip(-d, 0, None).mean(axis=2).astype(float)
    elif method == "baseline":
        # Production-style: compare current frame against a static pre-swing baseline
        # instead of the previous frame.  Combines dark delta (club shadow) and bright
        # delta (club face reflection) so both iron and driver heads are detected.
        #
        # IMPORTANT: use the original `patch` (ball intact), NOT `patch_c` (ball erased).
        # The baseline was built from raw frames that still contain the white ball, so
        # comparing `patch_c` (ball replaced with grey fill) vs baseline (white ball)
        # creates a large dark delta at the ball position every time — it gets detected
        # as the club and wins over the real club head blob.  Using `patch` instead lets
        # the ball contribution cancel naturally (both sides have the same white disc).
        # The exclusion-zone mask below handles any residual ball signal.
        base = _get_baseline_frame(shot)
        diff_map = np.abs(d).mean(axis=2)   # fallback if baseline unavailable
        if base is not None:
            bh, bw_b = base.shape
            b_crop = base[y0:min(bh, y0 + rows), x0:min(bw_b, x0 + cols)]
            if b_crop.shape == (rows, cols):
                gray_c   = _rgb_to_gray(patch)        # original patch — ball cancels
                dark_d   = np.clip(b_crop - gray_c, 0.0, None)   # shadow / blur
                bright_d = np.clip(gray_c - b_crop, 0.0, None)   # reflection / face
                diff_map = np.maximum(dark_d, bright_d)
    elif method == "optFlow":
        # Dense optical flow (Farneback).  The club head is the fastest coherent
        # motion in the ROI; magnitude of the flow vector gives the diff_map.
        try:
            import cv2
            g_c = _rgb_to_gray(patch_c).astype(np.uint8)
            g_p = _rgb_to_gray(patchP_c).astype(np.uint8)
            flow = cv2.calcOpticalFlowFarneback(
                g_p, g_c, None, 0.5, 3, 15, 3, 5, 1.2, 0)
            diff_map = np.sqrt(flow[..., 0]**2 + flow[..., 1]**2).astype(float)
        except ImportError:
            diff_map = np.abs(d).mean(axis=2)   # cv2 not available — fall back

    elif method == "bgDiff":
        # Compare current frame against the mean of the whole detection window.
        # Everything that stayed the same across all frames disappears; only
        # per-frame unique objects (the club at this instant) remain.
        ws = win_start if win_start is not None else max(1, shot["impact"] - 3)
        we = win_end   if win_end   is not None else min(shot["N"] - 1, shot["impact"] + 1)
        bg = _get_window_bg(shot, ws, we)
        diff_map = np.abs(d).mean(axis=2)   # fallback
        if bg is not None:
            bh, bw_b = bg.shape
            b_crop = bg[y0:min(bh, y0 + rows), x0:min(bw_b, x0 + cols)]
            if b_crop.shape == (rows, cols):
                gray_c = _rgb_to_gray(patch_c)
                diff_map = np.abs(gray_c - b_crop)

    elif method == "streak":
        # Motion-streak detector.  A fast club creates an elongated bright/dark
        # streak in the diff image.  Weight each pixel by the local gradient
        # magnitude of the diff — streak edges score high, flat noise scores low.
        raw_diff = np.abs(d).mean(axis=2).astype(float)
        gy, gx = np.gradient(raw_diff)
        grad_mag = np.sqrt(gx**2 + gy**2)
        peak = grad_mag.max()
        diff_map = raw_diff * (1.0 + grad_mag / (peak + 1e-6))

    elif method == "posStreak":
        # Positive-only streak: only pixels that got BRIGHTER, weighted by gradient.
        # A bright club moving right creates a positive diff exactly where it IS NOW —
        # the ghost at its previous position is darker (negative diff) and is ignored.
        # This isolates the front/current blob without the trailing ghost.
        pos_diff = np.clip(d, 0, None).mean(axis=2).astype(float)
        gy, gx = np.gradient(pos_diff)
        grad_mag = np.sqrt(gx**2 + gy**2)
        peak = grad_mag.max()
        diff_map = pos_diff * (1.0 + grad_mag / (peak + 1e-6))

    elif method == "hsvDiff":
        # Diff in HSV space: V (brightness) catches the club face reflection
        # and shadow; S (saturation) catches metallic silver vs coloured background.
        # Both are complementary — combined they fire more reliably on any club type.
        def _to_vs(patch):
            r = patch[:, :, 0].astype(np.float32) / 255.0
            g = patch[:, :, 1].astype(np.float32) / 255.0
            b = patch[:, :, 2].astype(np.float32) / 255.0
            v  = np.maximum(np.maximum(r, g), b)
            mn = np.minimum(np.minimum(r, g), b)
            s  = np.where(v > 1e-6, (v - mn) / v, 0.0)
            return v, s
        v_c, s_c = _to_vs(patch_c)
        v_p, s_p = _to_vs(patchP_c)
        diff_map  = (np.abs(v_c - v_p) + np.abs(s_c - s_p) * 0.5) * 255.0

    else:                     diff_map = np.abs(d).mean(axis=2)

    # For non-near-impact frames, _erase_ball zeroed the disc in both patches so
    # diff_map is 0 there.  Fill with surrounding annulus median so the threshold
    # step doesn't create an artificial hole at the ball position.
    # (Near-impact: disc has real signal — don't overwrite it.)
    if not near_impact:
        ball_r_fill = ball_dia_px / 2
        _rs_f = np.arange(rows, dtype=float); _cs_f = np.arange(cols, dtype=float)
        _ys_f, _xs_f = np.meshgrid(_rs_f, _cs_f, indexing="ij")
        _dsq_f  = (_xs_f - bx_roi)**2 + (_ys_f - by_roi)**2
        _bdisc_f = _dsq_f <= ball_r_fill**2
        _bann_f  = (_dsq_f > ball_r_fill**2) & (_dsq_f <= (ball_r_fill * 1.8)**2)
        if _bdisc_f.any() and _bann_f.any():
            diff_map = diff_map.copy()
            diff_map[_bdisc_f] = float(np.median(diff_map[_bann_f]))

    thr = float(p["diff_thresh"])
    raw = diff_map >= thr

    # Exclusion zone mask (Excl× slider) — skip when near impact (already handled above).
    if not near_impact:
        excl_r2 = (ball_dia_px * float(p["exclusion"]) / 2) ** 2
        rs_a = np.arange(rows, dtype=float); cs_a = np.arange(cols, dtype=float)
        ys_g, xs_g = np.meshgrid(rs_a, cs_a, indexing="ij")
        excl_mask = (xs_g - bx_roi)**2 + (ys_g - by_roi)**2 <= excl_r2
        raw = raw & ~excl_mask

    # Morphological opening: erode n px then re-dilate n px.
    # This severs thin connections (shaft ≈ 3-8px wide → erodes away) while
    # keeping solid blobs (club head ≈ 20-40px wide → survives, then restored).
    # The Dilate slider now controls the opening radius; 2 is a good default.
    open_n = max(1, int(round(p.get("dilate", 2))))
    opened = _dilate(_erode(raw, open_n), open_n)
    active = opened

    return dict(active=active, raw=raw, diff_map=diff_map,
                x0_px=x0, y0_px=y0, roi=roi, ball=ball,
                patch=patch, patchP=patchP)


def build_brightness_mask(shot, fi, p, mode="bright"):
    """Frame-diff mask restricted to the ROI, using colour-change direction as signal.

    mode="bright" — pixels that became whiter/brighter (positive luminosity change).
    mode="dark"   — pixels that became darker  (negative luminosity change).
    mode="grey"   — pixels with a large, chromatically-neutral change (metallic clubs):
                    high magnitude diff where R/G/B channels all shifted together.

    Score is computed from t-1 → t diff so only moving parts score high, not the
    static bright/dark regions of the scene.  Ball disc excluded.  Threshold = 90th
    percentile of in-ROI, out-of-ball scores (top 10%).
    """
    if fi == 0: return None
    ball = _ball_for_frame(shot, fi)
    if ball is None: return None
    W, H = shot["W"], shot["H"]

    roi = _roi_rect(ball["cx"], ball["cy"], ball["dia"], p)
    patch,  x0, y0 = _get_patch(shot["frames"], fi,   roi, W, H)
    patchP, _,  _  = _get_patch(shot["frames"], fi-1, roi, W, H)
    if patch is None or patchP is None or patch.shape != patchP.shape: return None

    rows, cols = patch.shape[:2]
    bx_roi = ball["cx"]*W - x0
    by_roi = ball["cy"]*H - y0
    ball_dia_px = ball["dia"] * W

    d = patch.astype(float) - patchP.astype(float)   # signed per-channel diff

    if mode == "bright":
        score = np.clip(d, 0, None).mean(axis=2)      # pixels that got brighter
    elif mode == "dark":
        score = np.clip(-d, 0, None).mean(axis=2)     # pixels that got darker
    else:  # grey
        d_mag    = np.abs(d).mean(axis=2)              # total change magnitude
        d_chroma = d.std(axis=2)                       # colour shift (0 = pure grey change)
        score    = d_mag / (d_chroma + 1.0)            # high = large neutral-colour change

    # Ball exclusion disc
    rs_a = np.arange(rows, dtype=float); cs_a = np.arange(cols, dtype=float)
    ys_g, xs_g = np.meshgrid(rs_a, cs_a, indexing="ij")
    d2 = (xs_g - bx_roi)**2 + (ys_g - by_roi)**2
    not_ball = d2 > (ball_dia_px / 2) ** 2

    score_vals = score[not_ball] if not_ball.any() else score.ravel()
    if score_vals.max() < 1e-6: return None
    pct = 95 if mode == "dark" else 90   # dark = top 5%, others = top 10%
    thr = np.percentile(score_vals, pct)
    if thr < 1e-6: return None
    raw = (score >= thr) & not_ball

    open_n = max(1, int(round(p.get("dilate", 2))))
    opened = _dilate(_erode(raw, open_n), open_n)

    return dict(active=opened, raw=raw, diff_map=score,
                x0_px=x0, y0_px=y0, roi=roi, ball=ball,
                patch=patch, patchP=patchP)


def find_blobs(mask_result, shot, p, pred_x=None, pred_y=None):
    """Find connected components in the active mask.

    pred_x / pred_y: predicted club position (normalised 0-1) from velocity
    extrapolation in run_all.  When supplied, blobs are ranked by distance to
    the prediction rather than distance to ball.  This rejects the absDiff ghost
    (which sits at the *previous* position, one step BEHIND the prediction).
    Without a prediction (first two frames of a run), falls back to ball distance.
    """
    if mask_result is None or not mask_result["active"].any(): return []
    active = mask_result["active"]
    W, H = shot["W"], shot["H"]
    x0, y0 = mask_result["x0_px"], mask_result["y0_px"]
    ball = mask_result["ball"]
    bx = ball["cx"]*W; by = ball["cy"]*H

    if not active.any(): return []

    # Reference for blob ranking
    if pred_x is not None and pred_y is not None:
        ref_bx = pred_x * W; ref_by = pred_y * H
    else:
        ref_bx = bx; ref_by = by   # fallback: distance to ball

    rows, cols = active.shape
    py_coords = np.arange(rows, dtype=float) + y0
    px_coords = np.arange(cols, dtype=float) + x0
    visited = np.zeros_like(active, dtype=bool)
    blobs = []

    # 8-connectivity: diagonals count as neighbours so a tilted square stays one blob
    _NBRS = [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]

    for sr, sc in zip(*np.where(active)):
        if visited[sr, sc]: continue
        q = deque([(int(sr), int(sc))]); visited[sr, sc] = True
        pxs, pys = [], []
        while q:
            rr, cc = q.popleft()
            pxs.append(int(px_coords[cc])); pys.append(int(py_coords[rr]))
            for dr, dc in _NBRS:
                nr, nc = rr+dr, cc+dc
                if (0 <= nr < rows and 0 <= nc < cols
                        and active[nr,nc] and not visited[nr,nc]):
                    visited[nr,nc] = True; q.append((nr,nc))

        count = len(pxs)
        if count < int(p["min_area"]): continue
        if count > int(p.get("max_area", 6000)): continue

        min_x,max_x = min(pxs),max(pxs); min_y,max_y = min(pys),max(pys)
        cx_ = float(np.mean(pxs)); cy_ = float(np.mean(pys))
        bw = max(1, max_x-min_x+1); bh = max(1, max_y-min_y+1)

        # Squareness via PCA eigenvalue ratio — rotation-invariant and not fooled
        # by a few stray pixels at the edge inflating the bounding box.
        # sqrt(λ_max / λ_min) ≈ ratio of spread along major vs minor axis.
        # A square/circle → ~1.0; a shaft → 5-10+.
        pxs_a = np.array(pxs, dtype=float); pys_a = np.array(pys, dtype=float)
        if count >= 4:
            cov = np.cov(pxs_a - cx_, pys_a - cy_)
            eigs = np.sort(np.abs(np.linalg.eigvalsh(cov)))
            pca_aspect = math.sqrt(max(eigs[1], 1e-6) / max(eigs[0], 1e-6))
        else:
            pca_aspect = max(bw, bh) / max(min(bw, bh), 1)
        if pca_aspect > float(p.get("max_aspect", 2.2)): continue

        # Solidity: pixel count / bounding-box area.  A solid club head scores 0.3+.
        # A large scattered noise cluster has many gaps → low solidity → reject.
        solidity = count / max(bw * bh, 1)
        if solidity < 0.20: continue

        # Leading edge: centroid of the third of the blob closest to the ball
        dists_sq = [(pxs[k]-bx)**2+(pys[k]-by)**2 for k in range(count)]
        face_n = max(1, count//3)
        face_idx = sorted(range(count), key=lambda k: dists_sq[k])[:face_n]
        lead_x = float(np.mean([pxs[k] for k in face_idx])) / W
        lead_y = float(np.mean([pys[k] for k in face_idx])) / H

        dist = math.hypot(cx_ - ref_bx, cy_ - ref_by) / max(W, H)
        blobs.append(dict(count=count, cx=cx_/W, cy=cy_/H,
                          lead_x=lead_x, lead_y=lead_y,
                          bbox=(min_x/W, min_y/H, bw/W, bh/H),
                          dist=dist))

    # Closest blob to reference (prediction or ball) = current club position.
    # For absDiff the ghost is always ~1 frame behind the velocity prediction,
    # so the real club will rank first.
    blobs.sort(key=lambda b: b["dist"])
    return blobs


def _component_to_blob(component, x0, y0, W, H, ref_bx, ref_by):
    """Convert a _rightmost_blob_from_diff component list to the find_blobs dict format."""
    if not component:
        return None
    pxs = [c + x0 for _, c in component]
    pys = [r + y0 for r, _ in component]
    count = len(pxs)
    cx_ = float(np.mean(pxs)); cy_ = float(np.mean(pys))
    min_x, max_x = min(pxs), max(pxs)
    min_y, max_y = min(pys), max(pys)
    bw = max(1, max_x - min_x + 1); bh = max(1, max_y - min_y + 1)
    dists_sq = [(pxs[k] - ref_bx)**2 + (pys[k] - ref_by)**2 for k in range(count)]
    face_n   = max(1, count // 3)
    face_idx = sorted(range(count), key=lambda k: dists_sq[k])[:face_n]
    lead_x   = float(np.mean([pxs[k] for k in face_idx])) / W
    lead_y   = float(np.mean([pys[k] for k in face_idx])) / H
    dist     = math.hypot(cx_ - ref_bx, cy_ - ref_by) / max(W, H)
    return dict(count=count, cx=cx_/W, cy=cy_/H,
                lead_x=lead_x, lead_y=lead_y,
                bbox=(min_x/W, min_y/H, bw/W, bh/H),
                dist=dist)


def find_blobs_streak_bfs(mask_result, shot, p, impact_fi=None, fi=None, method=None):
    """BFS detection on normalized diff_map (no binary threshold).

    method="newDiff": ball disc is always zeroed out regardless of phase,
    since the ball position is always known and must never be selected as club.
    """
    if mask_result is None:
        return []
    dm   = mask_result["diff_map"]
    x0, y0 = mask_result["x0_px"], mask_result["y0_px"]
    rows, cols = dm.shape
    W, H = shot["W"], shot["H"]
    ball = mask_result.get("ball")

    dm_n  = dm / max(float(dm.max()), 1e-6)
    dm_det = dm_n.copy()

    if ball:
        bx_f   = ball["cx"] * W;  by_f = ball["cy"] * H
        ball_r = ball["dia"] * W / 2
        excl_r = ball_r * float(p.get("exclusion", 1.0))
        ys_b   = (np.arange(rows, dtype=float) + y0)[:, None]
        xs_b   = (np.arange(cols, dtype=float) + x0)[None, :]
        dist_sq   = (xs_b - bx_f)**2 + (ys_b - by_f)**2
        ball_disc = dist_sq <= ball_r**2

        if method == "newDiff":
            # Ball position always known. Pre-impact: club cannot be at or right
            # of ball — zero everything from ball_x rightward so BFS is physically
            # blocked from selecting that region.  Post-impact: mask ball disc only.
            if impact_fi is not None and fi is not None and fi <= impact_fi:
                ball_col = int(round(bx_f)) - x0   # ball x in ROI coords
                if 0 <= ball_col < cols:
                    dm_det[:, ball_col:] = 0.0
            else:
                dm_det[dist_sq <= excl_r**2] = 0.0
        elif impact_fi is not None and fi is not None:
            if fi < impact_fi:
                dm_det[dist_sq <= excl_r**2] = 0.0
            elif fi > impact_fi:
                dm_det[ball_disc] = 0.0
    else:
        bx_f = W / 2; by_f = H / 2

    post      = impact_fi is not None and fi is not None and fi > impact_fi
    thr_scale = 0.65 if method == "newDiff" else 1.0
    component = _rightmost_blob_from_diff(dm_det, leftmost=post, thr_scale=thr_scale)
    if not component:
        return []
    blob = _component_to_blob(component, x0, y0, W, H, bx_f, by_f)
    return [blob] if blob else []


def temporal_filter(dets, shot, p):
    """Post-process run_all detections to remove bad points.

    Pass 1 — No-backward: the club is always moving toward the ball.
              Each consecutive detection must be closer to the ball than
              the previous one (within a tolerance). Pure physics constraint,
              no fragile velocity estimation required.

    Pass 2 — Outlier rejection: iterative linear regression over the
              surviving points. Drops the single worst point each iteration
              until all residuals are within max_resid_px.
    """
    W, H = shot["W"], shot["H"]
    max_resid = float(p.get("max_resid_px", 60))

    ordered = [(fi, b) for fi, b in sorted(dets.items()) if b is not None]
    if len(ordered) < 2:
        return dict(dets), set()

    fis = np.array([fi for fi,_ in ordered], dtype=float)
    xs  = np.array([b["cx"]*W for _,b in ordered], dtype=float)
    ys  = np.array([b["cy"]*H for _,b in ordered], dtype=float)
    mask = np.ones(len(fis), dtype=bool)

    # Pass 1: distance to ball must NEVER increase — club always approaches ball.
    # 5px noise floor only to account for sub-pixel measurement jitter.
    ball = _ball_for_frame(shot, shot["impact"])
    if ball:
        bx = ball["cx"]*W; by = ball["cy"]*H
        dists = np.sqrt((xs-bx)**2 + (ys-by)**2)
        for i in range(1, len(fis)):
            if not mask[i-1]: continue
            if dists[i] > dists[i-1] + 5.0:   # 5px = measurement noise only
                mask[i] = False

    # Pass 1a: Y-band — club can't be far above/below ball height at impact.
    # ROI is vertically centered on the ball; anything outside that band is a
    # false positive (reflection, other object). Band tightens with roi_y in P3/P4.
    ball_yband = _ball_for_frame(shot, shot["impact"])
    if ball_yband is not None:
        by_band   = ball_yband["cy"] * H
        half_band = ball_yband["dia"] * W * p.get("roi_y", 12) / 2
        for i in range(len(fis)):
            if mask[i] and abs(ys[i] - by_band) > half_band:
                mask[i] = False

    # Pass 1b: Direction consistency — remove middle points that create a zig-zag.
    # For consecutive triple (A, B, C): if the swing direction reverses by > 90° at B
    # (dot product of A→B and B→C is negative), B is the bad point — remove it.
    # Iterates until stable so cascading zig-zags are fully cleaned.
    # This catches the case where only 3 points exist (linear regression degenerates
    # because any 2 points fit a line perfectly, making residuals meaningless).
    for _ in range(4):
        changed = False
        active_idx = [i for i in range(len(fis)) if mask[i]]
        for k in range(1, len(active_idx) - 1):
            ia, ib, ic = active_idx[k-1], active_idx[k], active_idx[k+1]
            dx1 = xs[ib]-xs[ia]; dy1 = ys[ib]-ys[ia]
            dx2 = xs[ic]-xs[ib]; dy2 = ys[ic]-ys[ib]
            l1 = math.sqrt(dx1**2+dy1**2); l2 = math.sqrt(dx2**2+dy2**2)
            if l1 < 1.0 or l2 < 1.0: continue
            if (dx1*dx2 + dy1*dy2) / (l1*l2) < 0:
                mask[ib] = False; changed = True
        if not changed: break

    # Pass 1c: Perpendicular deviation from ball-anchor trajectory line.
    # The club must travel roughly from its first detection → ball@impact.
    # Any detection that deviates more than max_resid perpendicular to that line
    # is an off-path blob (wrong object detected) and gets rejected.
    # This catches lateral outliers that the direction check misses because the
    # horizontal component of travel is large enough to keep the dot product positive.
    ball_imp_det = _ball_for_frame(shot, shot["impact"])
    if ball_imp_det is not None:
        bx_end = ball_imp_det["cx"] * W; by_end = ball_imp_det["cy"] * H
        active_idx = [i for i in range(len(fis)) if mask[i]]
        if len(active_idx) >= 2:
            i0 = active_idx[0]
            dx = bx_end - xs[i0]; dy = by_end - ys[i0]
            length = math.sqrt(dx**2 + dy**2)
            if length > 1.0:
                ux = dx/length; uy = dy/length   # unit vector along trajectory
                for i in active_idx[1:]:
                    vx = xs[i] - xs[i0]; vy = ys[i] - ys[i0]
                    perp = abs(vx*uy - vy*ux)    # perpendicular distance
                    if perp > max_resid:
                        mask[i] = False

    # Pass 2: iterative linear trend outlier rejection
    for _ in range(8):
        if mask.sum() < 2: break
        t=fis[mask]; xm=xs[mask]; ym=ys[mask]
        tm=t.mean(); denom=float(((t-tm)**2).sum())
        if denom < 1e-6: break
        vx=float(np.dot(t-tm,xm))/denom; vy=float(np.dot(t-tm,ym))/denom
        bx_=float(xm.mean()-vx*tm); by_=float(ym.mean()-vy*tm)
        pred_x=vx*fis+bx_; pred_y=vy*fis+by_
        resid=np.sqrt((xs-pred_x)**2+(ys-pred_y)**2)
        if not (mask & (resid > max_resid)).any(): break
        worst_idx = int(np.argmax(np.where(mask, resid, -1.0)))
        if resid[worst_idx] > max_resid:
            mask[worst_idx] = False
        else:
            break

    rejected = {int(fis[i]) for i in range(len(fis)) if not mask[i]}
    result = dict(dets)
    for fi_rej in rejected:
        result[fi_rej] = None
    return result, rejected

def extrapolate_near_impact(dets, shot, p, impact, skip, raw_dets=None, rejected=None):
    """Fill near-impact frames that have no kept detection.

    Priority order for each missing frame:
      1. Raw detection NOT rejected by temporal_filter — use real coords, mark cyan.
      2. Linear extrapolation from earlier good detections (last resort, marked cyan).

    Points in `rejected` were flagged as bad by temporal_filter and are never restored.
    """
    W, H = shot["W"], shot["H"]
    raw_dets = raw_dets or {}
    rejected  = rejected  or set()

    result = dict(dets)
    predicted = set()
    lo = max(1, impact - skip)
    hi = min(shot["N"] - 1, impact + 1)

    # Restore raw detections that are missing from dets but were NOT rejected as bad
    for fi in range(lo, hi + 1):
        if result.get(fi) is not None:
            continue
        if fi in rejected:   # temporal_filter said this is bad — don't restore it
            continue
        raw = raw_dets.get(fi)
        if raw is not None:
            restored = dict(raw, predicted=True)
            result[fi] = restored
            predicted.add(fi)

    # Second: for frames still missing, try linear extrapolation from good early dets
    still_missing = [fi for fi in range(lo, hi + 1) if result.get(fi) is None]
    if not still_missing:
        return result, predicted

    cutoff = impact - max(1, skip)
    good = [(fi, b) for fi, b in sorted(dets.items())
            if b is not None and not b.get("predicted") and fi <= cutoff]
    if len(good) < 2:
        return result, predicted

    fis = np.array([fi for fi,_ in good], dtype=float)
    xs  = np.array([b["cx"]*W for _,b in good], dtype=float)
    ys  = np.array([b["cy"]*H for _,b in good], dtype=float)
    tm = fis.mean(); denom = float(((fis-tm)**2).sum())
    if denom < 1e-6:
        return result, predicted
    vx = float(np.dot(fis-tm, xs)) / denom
    vy = float(np.dot(fis-tm, ys)) / denom
    ox = float(xs.mean() - vx*tm)
    oy = float(ys.mean() - vy*tm)

    for fi in still_missing:
        px = float(np.clip((vx * fi + ox) / W, 0.0, 1.0))
        py = float(np.clip((vy * fi + oy) / H, 0.0, 1.0))
        result[fi] = dict(count=0, cx=px, cy=py, lead_x=px, lead_y=py,
                          bbox=(px, py, 0.005, 0.005), dist=0.0, predicted=True)
        predicted.add(fi)
    return result, predicted


# ─────────────────────────────────────────────────────────────────────────────
# Live club metrics
# ─────────────────────────────────────────────────────────────────────────────

def compute_live_metrics(shot, detections, p):
    W, H   = shot["W"], shot["H"]
    fps    = shot["fps"]
    impact = shot["impact"]
    fov_x  = float(p.get("fov_x", 70)); fov_y = float(p.get("fov_y", 45))
    bd     = float(p.get("ball_diam_m", 0.04267))
    zero_d = float(p.get("zero_deg", 0))

    fx = W / (2*math.tan(math.radians(fov_x/2)))
    fy = H / (2*math.tan(math.radians(fov_y/2)))

    ball_imp = _ball_for_frame(shot, impact)
    if ball_imp is None: return None
    # Prefer 3D depth from precomputed ball observations (avoids sensitivity to
    # ball detector apparent size, which varies by pipeline version).
    if shot.get("ball_depth_m"):
        depth_m = shot["ball_depth_m"]
    else:
        depth_m = bd * fx / max(ball_imp["dia"]*W, 1.0)

    # Real non-predicted points for path/angle (no synthetic, no post-impact+2)
    pts = []
    for fi in sorted(detections):
        blob = detections[fi]
        if blob is None or blob.get("predicted") or blob.get("synthetic") or fi > impact+2: continue
        lx = blob["cx"]; ly = blob["cy"]
        X = (lx-0.5)*W/fx*depth_m; Y = (ly-0.5)*H/fy*depth_m
        pts.append(dict(fi=fi, t=fi/fps, pos=np.array([X,Y,depth_m]), lx=lx, ly=ly))

    n = len(pts)
    if n < 2:
        return dict(club_speed=None, points=n, method="not_enough_data",
                    club_path=None, attack_angle=None)

    # ── Speed: last real pre-impact detection → impact anchor ─────────────────
    # Build a separate list that includes the impact-frame anchor (synthetic OK)
    # but nothing after impact. Speed = distance between the two points closest
    # to contact — never the first or last of the full arc.
    spd_pts = []
    for fi in sorted(detections):
        blob = detections[fi]
        if blob is None or blob.get("predicted") or fi > impact: continue
        if blob.get("synthetic") and fi != impact: continue   # only impact anchor allowed
        lx = blob["cx"]; ly = blob["cy"]
        X = (lx-0.5)*W/fx*depth_m; Y = (ly-0.5)*H/fy*depth_m
        spd_pts.append(dict(fi=fi, t=fi/fps, pos=np.array([X,Y,depth_m])))

    # ── Speed: all pairwise velocity estimates, outliers removed, then averaged ─
    # Every (i, j) pair gives an independent speed estimate; more pairs = more
    # robust averaging.  IQR outlier fence kicks in with as few as 2 estimates.
    speed_mph       = None
    spd_frames      = None
    all_pair_speeds = []
    good_pair_speeds= []
    if len(spd_pts) >= 2:
        pair_speeds = []
        for i in range(len(spd_pts)):
            for j in range(i + 1, len(spd_pts)):
                p_a, p_b = spd_pts[i], spd_pts[j]
                dt_p = p_b["t"] - p_a["t"]
                if dt_p > 1e-9:
                    pair_speeds.append((
                        float(np.linalg.norm(p_b["pos"] - p_a["pos"]) / dt_p) * 2.23694,
                        (p_a["fi"], p_b["fi"])
                    ))
        if pair_speeds:
            vals = [v for v, _ in pair_speeds]
            if len(vals) >= 2:
                q1, q3 = np.percentile(vals, 25), np.percentile(vals, 75)
                iqr    = q3 - q1
                lo, hi = q1 - 1.5 * iqr, q3 + 1.5 * iqr
                good   = [(v, f) for v, f in pair_speeds if lo <= v <= hi]
                if not good:
                    good = pair_speeds   # all outliers? keep all (degenerate case)
            else:
                good = pair_speeds
            speed_mph  = float(np.mean([v for v, _ in good]))
            spd_frames = good[-1][1]
            all_pair_speeds = pair_speeds
            good_pair_speeds = good
    if spd_frames is None:
        mid = n // 2
        s0  = pts[max(0, mid - 1)]; s1 = pts[min(n - 1, mid)]
        spd_frames = (s0["fi"], s1["fi"])
        dt_fb = s1["t"] - s0["t"]
        if dt_fb > 1e-9:
            speed_mph = float(np.linalg.norm(s1["pos"] - s0["pos"]) / dt_fb) * 2.23694

    # ── Path + attack angle: first → last point ───────────────────────────────
    # Span the whole measured arc for direction; instantaneous middle is noisy.
    p0 = pts[0]; p1 = pts[-1]
    dt_path = p1["t"] - p0["t"]
    if dt_path < 1e-9:
        path = atk = None
    else:
        dxpx = (p1["lx"] - p0["lx"]) * W
        dypx = (p1["ly"] - p0["ly"]) * H
        th  = math.radians(zero_d)
        fwd = dxpx*math.cos(th) + dypx*(-math.sin(th))
        lat = dxpx*math.sin(th) + dypx*math.cos(th)
        path = math.degrees(math.atan2(lat, fwd)) if (abs(fwd)+abs(lat))>1e-6 else None

        dpos_path = p1["pos"] - p0["pos"]
        vy_p = dpos_path[1]; vh_p = math.sqrt(dpos_path[0]**2 + dpos_path[2]**2)
        atk  = math.degrees(math.atan2(-vy_p, max(vh_p, 1e-6))) if vh_p>1e-6 else None

    return dict(club_speed=speed_mph, points=n, method="mid2_speed+span_path",
                club_path=path, attack_angle=atk, depth_m=depth_m,
                spd_frames=spd_frames,
                all_pair_speeds=all_pair_speeds,
                good_pair_speeds=good_pair_speeds)

# ─────────────────────────────────────────────────────────────────────────────
# Labels
# ─────────────────────────────────────────────────────────────────────────────

_labels = {}

def load_labels():
    global _labels
    if LABELS_FILE.exists():
        _labels = json.loads(LABELS_FILE.read_text())
        print(f"Loaded {sum(len(v) for v in _labels.values())} labels")

def save_labels():
    LABELS_FILE.write_text(json.dumps(_labels, indent=2))
    print(f"Saved labels → {LABELS_FILE}")

def get_label(sname, fi): return _labels.get(sname, {}).get(str(fi))
def set_label(sname, fi, cx, cy): _labels.setdefault(sname, {})[str(fi)] = [cx, cy]
def clear_label(sname, fi): _labels.get(sname, {}).pop(str(fi), None)

# ─────────────────────────────────────────────────────────────────────────────
# State dump (Option A collaboration)
# ─────────────────────────────────────────────────────────────────────────────

def _serialise(obj):
    if isinstance(obj, np.ndarray): return obj.tolist()
    if isinstance(obj, (np.integer,)): return int(obj)
    if isinstance(obj, (np.floating,)): return float(obj)
    raise TypeError(type(obj))

def dump_state():
    shot = S.shot
    state = dict(
        shot  = shot["name"] if shot else None,
        frame = S.frame_idx,
        method = S.method,
        params = {k: float(v) for k,v in params.items()},
        impact = shot["impact"] if shot else None,
        detected = len(S.blobs) > 0,
        num_blobs = len(S.blobs),
        best_blob = S.blobs[0] if S.blobs else None,
        live_metrics = S.live_metrics,
    )
    STATE_FILE.write_text(json.dumps(state, indent=2, default=_serialise))
    print("\n" + "─"*60)
    print(f"STATE DUMP → {STATE_FILE}")
    print(json.dumps(state, indent=2, default=_serialise))
    print("─"*60)
    print("↑ paste that block into the chat\n")

# ─────────────────────────────────────────────────────────────────────────────
# Global state
# ─────────────────────────────────────────────────────────────────────────────

class _S:
    shot_idx   = 0; frame_idx  = 0
    method     = "posDiff"; label_mode = False
    shot       = None; mask_result = None
    blobs      = []; all_detections = {}; live_metrics = None
    filtered_detections = set()   # frame indices removed by temporal_filter
    predicted_frames    = set()   # frame indices filled by extrapolation near impact
    bright_mask_on = False         # toggle: show bright-change mask in frame panel
    dark_mask_on   = False         # toggle: show dark-change mask in frame panel
    grey_mask_on   = False         # toggle: show grey-change mask in frame panel
    pass_used      = None          # dominant pass (int)
    passes_used    = set()         # all passes that contributed points

S = _S(); params = dict(DEFAULT_P); shots = []

# ─────────────────────────────────────────────────────────────────────────────
# Figure layout
# ─────────────────────────────────────────────────────────────────────────────

fig = plt.figure(figsize=(17, 10), facecolor="#111")
fig.canvas.manager.set_window_title("Club Tracking Lab")

ax_frame   = fig.add_axes([0.01, 0.315, 0.56, 0.673])
ax_mask    = fig.add_axes([0.60, 0.560, 0.39, 0.428])
ax_metrics = fig.add_axes([0.60, 0.315, 0.39, 0.230])
ax_strip   = fig.add_axes([0.01, 0.212, 0.98, 0.090])
ax_info    = fig.add_axes([0.17, 0.165, 0.82, 0.038])

for ax in (ax_frame, ax_mask, ax_metrics, ax_strip, ax_info):
    ax.set_facecolor("#111")
    for sp in ax.spines.values(): sp.set_color("#444")

# Method radio
ax_radio = fig.add_axes([0.01, 0.013, 0.13, 0.300], facecolor="#1a1a2e")
radio = RadioButtons(ax_radio, METHODS, activecolor="#ff9900")
for lbl in radio.labels: lbl.set_color("white"); lbl.set_fontsize(9)

# Sliders  (3 rows)
_SLIDER_DEFS = [
    # Row 1: detection  y=0.118
    ("diff_thresh", "DiffThr",  1,  80,  [0.17, 0.118, 0.12, 0.022]),
    ("min_area",    "MinArea",  1, 500,  [0.30, 0.118, 0.12, 0.022]),
    ("max_area",    "MaxArea", 50,8000,  [0.43, 0.118, 0.12, 0.022]),
    ("exclusion",   "Excl×",  0.5, 5.0, [0.56, 0.118, 0.12, 0.022]),
    ("roi_x",       "ROI X",   2,  22,  [0.69, 0.118, 0.12, 0.022]),
    ("roi_y",       "ROI Y",   2,  16,  [0.82, 0.118, 0.12, 0.022]),
    # Row 2: filter  y=0.086
    ("dilate",           "Dilate",    0,   6,  [0.17, 0.086, 0.12, 0.022]),
    ("max_resid_px",     "MaxResid",  5, 200,  [0.30, 0.086, 0.12, 0.022]),
    ("skip_near_impact", "SkipImp",   0,   5,  [0.43, 0.086, 0.12, 0.022]),
    # Row 3: calibration  y=0.054
    ("fov_x",       "FOV X°", 35, 110,  [0.17, 0.054, 0.12, 0.022]),
    ("fov_y",       "FOV Y°", 25,  90,  [0.30, 0.054, 0.12, 0.022]),
    ("ball_diam_m","BallØ m",0.035,0.05,[0.43, 0.054, 0.12, 0.022]),
    ("zero_deg",    "0° Ref", -45,  45, [0.56, 0.054, 0.12, 0.022]),
]

sliders = {}
for key, lbl, vmin, vmax, rect in _SLIDER_DEFS:
    ax_s = fig.add_axes(rect, facecolor="#1a1a2e")
    sl = Slider(ax_s, lbl, vmin, vmax, valinit=params.get(key, vmin), color="#ff9900", track_color="#333")
    sl.label.set_color("white"); sl.label.set_fontsize(7)
    sl.valtext.set_color("#ff9900"); sl.valtext.set_fontsize(7)
    sliders[key] = sl

# Buttons
_BTN_DEFS = [
    ("prev_shot",  "◀ Shot",   [0.17, 0.012, 0.055, 0.030]),
    ("next_shot",  "Shot ▶",   [0.228,0.012, 0.055, 0.030]),
    ("prev_frame", "◀ Frame",  [0.286,0.012, 0.065, 0.030]),
    ("next_frame", "Frame ▶",  [0.354,0.012, 0.065, 0.030]),
    ("impact_btn", "→ Impact", [0.422,0.012, 0.065, 0.030]),
    ("run_btn",    "▶ Run",    [0.490,0.012, 0.055, 0.030]),
    ("label_btn",  "⊕ Label",  [0.548,0.012, 0.055, 0.030]),
    ("clear_btn",  "✕ Label",  [0.606,0.012, 0.055, 0.030]),
    ("save_btn",   "Save",     [0.664,0.012, 0.048, 0.030]),
    ("dump_btn",   "p Dump",   [0.715,0.012, 0.055, 0.030]),
    ("eval_btn",   "Eval",     [0.773,0.012, 0.048, 0.030]),
    ("bright_btn", "◑ Bright", [0.824,0.012, 0.050, 0.030]),
    ("dark_btn",   "◐ Dark",   [0.876,0.012, 0.050, 0.030]),
    ("grey_btn",   "◈ Grey",   [0.928,0.012, 0.050, 0.030]),
]
buttons = {}
for key, lbl, rect in _BTN_DEFS:
    ax_b = fig.add_axes(rect)
    buttons[key] = Button(ax_b, lbl, color="#1a1a2e", hovercolor="#2a2a4e")
    buttons[key].label.set_color("white"); buttons[key].label.set_fontsize(8)

# ─────────────────────────────────────────────────────────────────────────────
# Drawing
# ─────────────────────────────────────────────────────────────────────────────

def _fmt(v, suffix="", d=1):
    if v is None: return "—"
    if isinstance(v, float) and not math.isfinite(v): return "—"
    return f"{v:.{d}f}{suffix}"

def _fmt_lr(v, pos="R", neg="L"):
    if v is None: return "—"
    if isinstance(v, float) and not math.isfinite(v): return "—"
    return f"{abs(v):.1f}° {pos if v>=0 else neg}"


def draw_frame():
    ax = ax_frame; ax.cla()
    ax.set_facecolor("#111"); ax.set_xticks([]); ax.set_yticks([])
    shot = S.shot
    if shot is None:
        ax.text(0.5,0.5,"No shot",color="#777",ha="center",va="center",transform=ax.transAxes); return

    fi = S.frame_idx; W, H = shot["W"], shot["H"]

    if S.bright_mask_on or S.dark_mask_on or S.grey_mask_on:
        mode = "bright" if S.bright_mask_on else ("dark" if S.dark_mask_on else "grey")
        bm = build_brightness_mask(shot, fi, params, mode=mode)
        if bm:
            oy, ox = bm["y0_px"], bm["x0_px"]
            act = bm["active"]; rh, rw = act.shape
            roi_px = shot["frames"][fi][oy:oy+rh, ox:ox+rw]
            # dark mode = white bg; bright/grey = black bg
            bg = 255 if mode == "dark" else 0
            disp = np.full((H, W, 3), bg, dtype=np.uint8)
            section = np.full((rh, rw, 3), bg, dtype=np.uint8)
            section[act] = roi_px[act]
            disp[oy:oy+rh, ox:ox+rw] = section
            ax.imshow(disp, origin="upper")
            # Peak marker — cross at the single highest-scoring pixel in the mask
            score = bm["diff_map"]; raw_mask = bm["raw"]
            if raw_mask.any():
                pk = int(np.argmax(score * raw_mask.astype(float)))
                pr, pc = np.unravel_index(pk, score.shape)
                ax.plot(ox + pc, oy + pr, "+", color="#ff00ff",
                        ms=22, mew=3, zorder=9)
        else:
            ax.imshow(shot["frames"][fi], origin="upper")
    else:
        ax.imshow(shot["frames"][fi], origin="upper")

    ball = _ball_for_frame(shot, fi)
    if ball:
        bx,by = ball["cx"]*W, ball["cy"]*H
        # ax.add_patch(patches.Circle((bx,by), ball["dia"]*W/2, fill=False, lw=1.5, color="lime", zorder=5))
        # ax.add_patch(patches.Circle((bx,by), ball["dia"]*W*params["exclusion"]/2,
        #                             fill=False, lw=1, ls="--", color="#ff9900", alpha=0.4, zorder=4))
        roi = _roi_rect(ball["cx"], ball["cy"], ball["dia"], params)
        ax.add_patch(patches.Rectangle((roi[0]*W,roi[1]*H), roi[2]*W, roi[3]*H,
                                       fill=False, lw=1.5, ls="--", color="#ff9900", alpha=0.7, zorder=4))

    # Box / centroid color by pass: P1=orange, P2=blue, P3=green
    run_det = S.all_detections.get(fi)
    box_color = _PASS_COLORS.get((run_det or {}).get("pass_id", 1), "#ff9900")

    for i, b in enumerate(S.blobs):
        alpha = 1.0 if i==0 else 0.30; lw = 2.0 if i==0 else 1.0
        if "bbox" in b:
            bbx,bby,bbw,bbh = b["bbox"]
            ax.add_patch(patches.Rectangle((bbx*W,bby*H), bbw*W, bbh*H,
                                           fill=False, lw=lw, color=box_color, alpha=alpha, zorder=6))
        if i==0:
            ax.plot(b["cx"]*W,     b["cy"]*H,     "o", color=box_color, ms=5, zorder=7)
            ax.plot(b["lead_x"]*W, b["lead_y"]*H, "x", color="#aa44ff", ms=11, mew=2.5, zorder=8)

    # Trail from run history — dot color: orange=P1, blue=P2(fallback), cyan=predicted.
    trail_pts = [(fi_, d["cx"]*W, d["cy"]*H, d.get("pass_id", 1))
                 for fi_, d in sorted(S.all_detections.items())
                 if d and not d.get("predicted") and fi_ not in S.filtered_detections]
    if len(trail_pts) >= 2:
        txs = [pt[1] for pt in trail_pts]; tys = [pt[2] for pt in trail_pts]
        ax.plot(txs, tys, color="#ff9900", lw=2.5, alpha=0.85, zorder=5)
        for fi_, tx, ty, pass_id in trail_pts:
            dot_color = _PASS_COLORS.get(pass_id, "#ff9900")
            ax.plot(tx, ty, "o", color=dot_color, ms=6, zorder=7)

    lbl = get_label(shot["name"], fi)
    if lbl:
        ax.plot(lbl[0]*W, lbl[1]*H, "*", color="yellow", ms=16, zorder=9)

    if S.label_mode:
        ax.text(0.01,0.99,"● LABEL MODE — click to mark club head",
                color="yellow",fontsize=9,transform=ax.transAxes,va="top",
                bbox=dict(facecolor="#111",alpha=0.8,boxstyle="round,pad=0.2"))

    impact = shot["impact"]; rel = fi-impact
    phase = "IMPACT" if rel==0 else (f"pre {rel}" if rel<0 else f"post +{rel}")
    det = f"✓({len(S.blobs)} blobs)" if S.blobs else "✗ no detection"
    if len(S.passes_used) > 1:
        pass_tag = f"  P{'+P'.join(str(p) for p in sorted(S.passes_used))}(combined)"
    else:
        pass_tag = {1: "  P1✓", 2: "  P2↓absDiff", 3: "  P3↓(fallback)", 4: "  P4↓↓(fallback2)"}.get(S.pass_used, "")
    ax.set_title(f"{shot['name']}   Frame {fi} [{phase}]   {det}   {S.method}{pass_tag}",
                 color="white", fontsize=10, pad=4)


def draw_mask():
    ax = ax_mask; ax.cla()
    ax.set_facecolor("#111"); ax.set_xticks([]); ax.set_yticks([])
    mr = S.mask_result
    if mr is None:
        ax.text(0.5,0.5,"(no mask — frame 0 has no prev)",color="#555",
                ha="center",va="center",transform=ax.transAxes); return

    W, H = S.shot["W"], S.shot["H"]
    x0,y0 = mr["x0_px"], mr["y0_px"]
    active = mr["active"]; dm = mr["diff_map"]
    rows,cols = active.shape
    x1 = x0+cols; y1 = y0+rows
    ext = [x0,x1,y1,y0]

    ax.imshow(S.shot["frames"][S.frame_idx][y0:y1, x0:x1],
              origin="upper", aspect="auto", extent=ext, alpha=0.30)

    dm_n = dm / max(float(dm.max()), 1e-6)

    # Fill the stationary ball disc with surrounding median so the hot
    # colormap doesn't show a dark hole where the ball was sitting
    ball_d = mr["ball"]
    if ball_d:
        bx_d = ball_d["cx"] * W;  by_d = ball_d["cy"] * H
        br_d = ball_d["dia"] * W / 2
        ys_d = (np.arange(rows, dtype=float) + y0)[:, None]
        xs_d = (np.arange(cols, dtype=float) + x0)[None, :]
        dsq_d   = (xs_d - bx_d)**2 + (ys_d - by_d)**2
        bdisc_d = dsq_d <= br_d**2
        bann_d  = (dsq_d > br_d**2) & (dsq_d <= (br_d * 1.8)**2)
        if bann_d.any() and bdisc_d.any():
            dm_n = dm_n.copy()
            dm_n[bdisc_d] = float(np.median(dm_n[bann_d]))

    ax.imshow(dm_n, cmap="hot", origin="upper", aspect="auto", extent=ext, alpha=0.80)

    rgba = np.zeros((*active.shape,4), dtype=float)
    rgba[active,2]=1.0; rgba[active,3]=0.55
    ax.imshow(rgba, origin="upper", aspect="auto", extent=ext)

    ball = mr["ball"]
    # excl_r = ball["dia"]*W*params["exclusion"]/2
    # ax.add_patch(patches.Circle((ball["cx"]*W,ball["cy"]*H), excl_r,
    #                             fill=False,lw=1.2,ls="--",color="#ff9900",alpha=0.7))
    if S.blobs:
        b = S.blobs[0]
        if "bbox" in b:
            bbx,bby,bbw,bbh = b["bbox"]
            ax.add_patch(patches.Rectangle((bbx*W,bby*H), bbw*W, bbh*H,
                                           fill=False,lw=2,color="#ff9900",zorder=5))
        ax.plot(b["lead_x"]*W, b["lead_y"]*H, "x", color="#aa44ff", ms=9, mew=2, zorder=6)

    ax.set_xlim(x0,x1); ax.set_ylim(y1,y0)
    labels = dict(absDiff="hot=|diff|  blue=active",
                  posDiff="hot=+diff (brighter)  blue=active  → current pos for bright club",
                  negDiff="hot=−diff (darker)    blue=active  → current pos for dark club",
                  baseline="hot=max(dark_δ,bright_δ) vs pre-swing avg  production-style",
                  streak="hot=|diff|×grad  blue=active  threshold-based",
                  streakBFS="hot=|diff|×grad  detection=rightmost BFS (no threshold)",
                  brightBFS="hot=baseline diff  detection=rightmost BFS on brightness change",
                  newDiff="hot=|frame−window_mean|  BFS on per-frame standout — path visible, current pos loudest",
                  ensembleBFS="newDiff primary → brightBFS fallback if jagged / smash>1.5")
    ax.set_title(f"{S.method} — {labels.get(S.method,'')}",
                 color="white", fontsize=8, pad=4)


def draw_metrics():
    ax = ax_metrics; ax.cla()
    ax.set_facecolor("#0d0d1a"); ax.set_xticks([]); ax.set_yticks([])
    for sp in ax.spines.values(): sp.set_color("#333")
    shot = S.shot
    if shot is None: return

    pm = shot.get("precomputed") or {}
    m  = pm.get("metrics") or {}
    lm = S.live_metrics

    lx, rx = 0.03, 0.53
    y = 0.95

    def hdr(x, t, c="white"):
        ax.text(x,y,t,color=c,fontsize=8,weight="bold",transform=ax.transAxes,va="top")

    def row(x, lbl, val, vc="#44ff88"):
        ax.text(x,     y-0.12, lbl, color="#888", fontsize=7, transform=ax.transAxes, va="top")
        ax.text(x+0.20,y-0.12, val, color=vc,    fontsize=7, transform=ax.transAxes, va="top",
                family="monospace")

    hdr(lx, "BALL  (precomputed)")
    y -= 0.12
    for lbl,val in [
        ("Ball Speed", _fmt(m.get("ballSpeedMph")," mph")),
        ("VLA",        _fmt(m.get("vlaDegrees"),"°")),
        ("HLA",        _fmt_lr(m.get("hlaDegrees"))),
        ("Est. Carry", _fmt(m.get("carryYards")," yd",0)),
        ("Backspin",   _fmt(m.get("estimatedBackspinRpm")," rpm",0)),
        ("Sidespin",   m.get("estimatedSidespinDisplay") or "—"),
    ]:
        row(lx, lbl, val); y -= 0.14

    y = 0.95
    hdr(rx, "CLUB  (▶ Run to compute)", "#ff9900")
    y -= 0.12
    sspd = _fmt(m.get("clubSpeedMph")," mph"); ssmash = _fmt(m.get("smashFactor"),"",2)
    lspd = _fmt(lm.get("club_speed") if lm else None," mph")
    sf = lm.get("spd_frames") if lm else None
    spd_tag = f"[fr {sf[0]}↔{sf[1]}]" if sf else ""
    smash_live="—"
    if lm and lm.get("club_speed") and m.get("ballSpeedMph"):
        smash_live = f"{min(1.60,m['ballSpeedMph']/lm['club_speed']):.2f}"
    for lbl,val,vc in [
        ("Spd (live)",   f"{lspd}  {spd_tag}", "#ff9900"),
        ("  (stored)",   sspd,             "#ff6600"),
        ("Smash (live)", smash_live,       "#ff9900"),
        ("  (stored)",   ssmash,           "#ff6600"),
        ("Path (live)",  _fmt_lr(lm.get("club_path") if lm else None), "#ff9900"),
        ("Path (stored)",m.get("clubPathDisplay") or "—",              "#ff6600"),
        ("Attack∠ est",  _fmt(lm.get("attack_angle") if lm else None,"°"), "#ff9900"),
    ]:
        row(rx,lbl,val,vc); y -= 0.14

    # ── Speed pair legend ─────────────────────────────────────────────────────
    if lm:
        all_pairs  = lm.get("all_pair_speeds") or []
        good_pairs = set(id(x) for x in (lm.get("good_pair_speeds") or []))
        good_vals  = {v for v, _ in (lm.get("good_pair_speeds") or [])}
        if all_pairs:
            y -= 0.06
            ax.text(0.03, y, "Speed pairs", color="#aaaaaa", fontsize=6,
                    weight="bold", transform=ax.transAxes, va="top")
            ax.text(0.53, y, "● used  ○ outlier", color="#666666", fontsize=5.5,
                    transform=ax.transAxes, va="top")
            y -= 0.10
            for spd_v, (fa, fb) in all_pairs:
                used   = spd_v in good_vals
                color  = "#44ff88" if used else "#666666"
                marker = "●" if used else "○"
                ax.text(0.03, y, f"{marker} fr{fa}↔{fb}",
                        color=color, fontsize=6, transform=ax.transAxes, va="top",
                        family="monospace")
                ax.text(0.28, y, f"{spd_v:.1f} mph",
                        color=color, fontsize=6, transform=ax.transAxes, va="top",
                        family="monospace")
                y -= 0.09
            if speed_mph := (lm.get("club_speed")):
                ax.text(0.03, y, f"avg → {speed_mph:.1f} mph",
                        color="#ff9900", fontsize=6.5, weight="bold",
                        transform=ax.transAxes, va="top", family="monospace")


def draw_strip():
    ax = ax_strip; ax.cla()
    ax.set_facecolor("#111"); ax.set_xticks([]); ax.set_yticks([])
    shot = S.shot
    if shot is None: return
    N = shot["N"]; impact = shot["impact"]
    lbl_frames = {int(k) for k in _labels.get(shot["name"],{})}
    for i in range(N):
        is_cur=i==S.frame_idx; is_imp=i==impact
        has_run=i in S.all_detections; run_det=S.all_detections.get(i) is not None
        filtered=i in S.filtered_detections
        if   is_imp:                   color="#ffdd00"
        elif i in S.predicted_frames: color="#0099cc"   # cyan = extrapolated near impact
        elif filtered:                 color="#cc44cc"   # magenta = removed by filter
        elif has_run:                  color="#44cc44" if run_det else "#cc3333"
        else:                          color="#2a2a3e"
        ax.add_patch(patches.Rectangle((i/N,0.05),1/N-0.002,0.70,
                     linewidth=2.5 if is_cur else 0,
                     edgecolor="white",facecolor=color))
        if i in lbl_frames:
            ax.add_patch(patches.Circle((i/N+0.5/N,0.88),0.4/N,color="yellow",zorder=5))
        if N<=50:
            ax.text(i/N+0.5/N,0.38,str(i),ha="center",va="center",fontsize=5.5,
                    color="black" if color in("#ffdd00","#44cc44") else "#aaa")
    ax.set_xlim(0,1); ax.set_ylim(0,1)
    ax.text(0.5, 0.01,
            "yellow=impact  green=detected  red=missed  magenta=filtered  cyan=predicted  yellow●=labeled  "
            "trail: orange=diff  yellow=bright-fb  purple=dark-fb  teal=grey-fb  white=speed  cyan=predicted  click to jump",
            ha="center", va="bottom", fontsize=6, color="#888", transform=ax.transAxes)


def draw_info():
    ax = ax_info; ax.cla()
    ax.set_facecolor("#0d0d1a"); ax.set_xticks([]); ax.set_yticks([])
    for sp in ax.spines.values(): sp.set_color("#333")
    shot = S.shot
    if shot is None: return
    fi=S.frame_idx; lbl=get_label(shot["name"],fi)
    if S.blobs:
        b=S.blobs[0]; err_txt=""
        if lbl:
            ep=math.hypot((b["lead_x"]-lbl[0])*shot["W"],(b["lead_y"]-lbl[1])*shot["H"])
            err_txt=f"   err={ep:.0f}px"
        dist_str = f"   dist={b['dist']:.3f}" if 'dist' in b else ""
        info=(f"Frame {fi}/{shot['N']-1}   DETECTED   lead=({b['lead_x']:.3f},{b['lead_y']:.3f})"
              f"   count={b['count']}{dist_str}   blobs={len(S.blobs)}{err_txt}")
        color="#ff9900"
    else:
        info=f"Frame {fi}/{shot['N']-1}   NO DETECTION"+(f"   label=({lbl[0]:.3f},{lbl[1]:.3f})" if lbl else "")
        color="#cc4444"
    ax.text(0.005,0.5,info,color=color,fontsize=7.5,va="center",transform=ax.transAxes,family="monospace")


def _rightmost_blob_from_diff(diff_map: np.ndarray, leftmost: bool = False, thr_scale: float = 1.0):
    """Find connected components on the normalized diff image and return the
    best club blob.

    leftmost=False (default): pick blob with rightmost centroid.
    leftmost=True: pick blob with leftmost centroid (use post-impact when club
    has swung past the ball and is continuing left).

    Ball exclusion must be applied by the caller before passing diff_map in.
    """
    MIN_CLUB_PX = 50    # shaft slivers / noise are smaller than this

    rows, cols = diff_map.shape
    peak = diff_map.max()
    if peak < 1e-6:
        return []

    norm = diff_map / peak

    NBRS = [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]

    def _label(thr_n: float):
        mask = norm >= thr_n
        if not mask.any():
            return []
        visited = np.zeros((rows, cols), dtype=bool)
        found: list[list[tuple[int,int]]] = []
        ys, xs = np.where(mask)
        for r0, c0 in zip(ys.tolist(), xs.tolist()):
            if visited[r0, c0]:
                continue
            comp: list[tuple[int,int]] = []
            q: deque[tuple[int,int]] = deque([(r0, c0)])
            visited[r0, c0] = True
            while q:
                r, c = q.popleft()
                comp.append((r, c))
                for dr, dc in NBRS:
                    nr, nc = r+dr, c+dc
                    if 0 <= nr < rows and 0 <= nc < cols and mask[nr,nc] and not visited[nr,nc]:
                        visited[nr,nc] = True
                        q.append((nr,nc))
            if len(comp) >= MIN_CLUB_PX:
                found.append(comp)
        return found

    for thr_n in [t * thr_scale for t in [0.30, 0.20, 0.12, 0.07, 0.04]]:
        blobs = _label(thr_n)
        if blobs:
            if leftmost:
                return min(blobs, key=lambda b: float(np.mean([c for _, c in b])))
            return max(blobs, key=lambda b: float(np.mean([c for _, c in b])))

    return []


# BFS auto-sweep cache: keyed by (shot_name, method, params_tuple)
_bfs_sweep_cache: dict = {}


def _dedup_consecutive_dets(raw_dets: dict, W: int, H: int, thr_px: float = 4.0):
    """Null out ADJACENT frame detections that didn't move.

    Only checks neighbouring frames (i, i+1): a ghost artifact is a static blob
    re-detected in the immediately following frame.  Non-adjacent frames are allowed
    to be close — a slow or distant club may only travel a few pixels per frame.
    """
    ordered = sorted(f for f, d in raw_dets.items() if d is not None)
    for i in range(1, len(ordered)):
        a, b = ordered[i - 1], ordered[i]
        da, db = raw_dets[a], raw_dets[b]
        if da is None or db is None:
            continue
        dx = abs(da["cx"] - db["cx"]) * W
        dy = abs(da["cy"] - db["cy"]) * H
        if math.hypot(dx, dy) < thr_px:
            raw_dets[a] = None   # remove earlier (further from impact)
    return raw_dets


def _apply_monotonicity(raw_dets: dict, shot: dict, ball_imp, tol_px: float = 5.0):
    """Enforce left-to-right monotonicity for newDiff club detections.

    The club always enters from off-screen LEFT and moves right toward the ball.
    False positives near the center/ball appear in early frames because bgDiff
    fires strongly at the ball region.  Three-step cleanup:

    Step 1 — pre-impact detections must be left of ball_cx (hard physics rule).
    Step 2 — find the leftmost (minimum cx) detection: that is where the club
              truly entered the frame.  Any detection in an EARLIER frame that
              sits to the RIGHT of this minimum is a center ghost — null it.
              This prevents a false center detection from poisoning the frontier.
    Step 3 — walk detections in frame order and enforce cx never decreases by
              more than tol_px (left-to-right only, direction hardcoded).
    """
    if ball_imp is None:
        return
    W       = shot["W"]
    ball_cx = ball_imp["cx"]
    tol     = tol_px / W
    impact  = shot["impact"]

    # Step 1: pre-impact must be left of ball
    for fi, d in list(raw_dets.items()):
        if d is not None and fi < impact and d["cx"] >= ball_cx:
            raw_dets[fi] = None

    ordered = sorted((fi, d) for fi, d in raw_dets.items() if d is not None)
    if not ordered:
        return

    # Step 2: anchor on the leftmost detection — anything earlier that's
    # further right is a ghost firing before the club entered the frame.
    leftmost_fi, leftmost_d = min(ordered, key=lambda x: x[1]["cx"])
    leftmost_cx = leftmost_d["cx"]
    for fi, d in ordered:
        if fi < leftmost_fi and d["cx"] > leftmost_cx + tol:
            raw_dets[fi] = None

    # Step 3: strict left-to-right monotonicity
    ordered = sorted((fi, d) for fi, d in raw_dets.items() if d is not None)
    if len(ordered) < 2:
        return
    frontier = ordered[0][1]["cx"]
    for fi, d in ordered[1:]:
        cx = d["cx"]
        if cx < frontier - tol:
            raw_dets[fi] = None
        else:
            frontier = max(frontier, cx)


def _run_bfs_sweep(shot, method, mask_method, impact, start, end, ball_imp):
    """Core per-frame BFS sweep.  Returns raw_dets dict (may contain None values)."""
    W, H     = shot["W"], shot["H"]
    raw_dets = {}
    for fi in range(start, end + 1):
        mr    = build_mask(shot, fi, mask_method, params)
        blobs = find_blobs_streak_bfs(mr, shot, params,
                                      impact_fi=impact, fi=fi, method=method)
        raw_dets[fi] = dict(blobs[0], pass_id=1) if blobs else None
    _dedup_consecutive_dets(raw_dets, W, H)
    if method in ("newDiff", "ensembleBFS"):
        _apply_monotonicity(raw_dets, shot, ball_imp)
    return raw_dets


def _ensemble_pool_and_fit(raw_nd: dict, raw_bf: dict, shot: dict, impact: int,
                           start: int, end: int) -> dict:
    """Combine newDiff + brightBFS into the best single detection per frame.

    Per-frame logic:
      - Only one method detected → use it
      - Both detected → pick the one whose blob area (count) is closest to the
        median count across all detections (real club head = consistent size)
    Then:
      - Light outlier pass: only remove points > 60 px from a polynomial fit
        (very lenient — we keep almost everything)
      - Smash guard: if smash > 1.55 iteratively remove the single point whose
        removal most reduces smash, until ≤ 1.55 or nothing left
    """
    W, H = shot["W"], shot["H"]
    ball_imp = _ball_for_frame(shot, impact)
    ball_cx  = ball_imp["cx"] if ball_imp else 0.5
    ball_cy  = ball_imp["cy"] if ball_imp else 0.5

    # Median blob count across all candidates (consistent club-head size signal)
    all_blobs = [d for d in list(raw_nd.values()) + list(raw_bf.values()) if d]
    med_count = float(np.median([b.get("count", 1) for b in all_blobs])) if all_blobs else 100.0

    # Step 1 — pick best candidate per frame
    result: dict = {}
    for fi in range(start, end + 1):
        nd = raw_nd.get(fi)
        bf = raw_bf.get(fi)
        if nd is None and bf is None:
            result[fi] = None
        elif nd is None:
            result[fi] = bf
        elif bf is None:
            result[fi] = nd
        else:
            # Both detected — prefer the one with count closest to median
            result[fi] = min((nd, bf), key=lambda b: abs(b.get("count", 0) - med_count))

    # Step 1.5 — reject near-duplicate detections and look for the club elsewhere.
    # Walk in frame order; if a detection is extremely close to the previous kept
    # detection (< 6 px movement), it's a static ghost — try the OTHER method's
    # candidate for that frame.  If that's also too close (or absent), null the frame.
    prev_cx = prev_cy = None
    for fi in sorted(result):
        d = result[fi]
        if d is None:
            continue
        if prev_cx is not None:
            dist_px = math.hypot((d["cx"] - prev_cx) * W, (d["cy"] - prev_cy) * H)
            if dist_px < 6.0:
                nd = raw_nd.get(fi); bf = raw_bf.get(fi)
                # Try whichever method wasn't chosen first
                chosen = result[fi]
                alt = bf if (chosen is nd or (nd and chosen["cx"] == nd["cx"] and chosen["cy"] == nd["cy"])) else nd
                if alt is not None:
                    alt_dist = math.hypot((alt["cx"] - prev_cx) * W, (alt["cy"] - prev_cy) * H)
                    result[fi] = alt if alt_dist >= 6.0 else None
                else:
                    result[fi] = None
                if result[fi] is None:
                    continue
        d = result[fi]
        if d is not None:
            prev_cx = d["cx"]; prev_cy = d["cy"]

    # Step 2 — build confirmed set FIRST (frames where both methods agreed within 15 px)
    # These are protected from ALL filtering steps below.
    confirmed = set()
    for fi in range(start, end + 1):
        nd = raw_nd.get(fi); bf = raw_bf.get(fi)
        if nd and bf and math.hypot((nd["cx"]-bf["cx"])*W, (nd["cy"]-bf["cy"])*H) < 15.0:
            confirmed.add(fi)

    # Step 3 — hard physics filters (skip confirmed frames)
    tol_x = 5.0 / W   # 5 px horizontal tolerance for monotonicity
    tol_y = 0.12       # 12% of frame height — max allowed above ball
    frontier_cx = None
    for fi in sorted(result):
        d = result[fi]
        if d is None:
            continue
        if fi in confirmed:            # both methods agree — never remove
            if fi < impact:
                frontier_cx = d["cx"] if frontier_cx is None else max(frontier_cx, d["cx"])
            continue
        cx, cy = d["cx"], d["cy"]

        # 3a. Pre-impact: can't be at or right of ball, can't be more than tol_y above ball
        if fi < impact:
            if cx >= ball_cx:
                result[fi] = None; continue
            if cy < ball_cy - tol_y:
                result[fi] = None; continue

        # 3b. Monotonicity: club only moves left → right pre-impact
        if fi < impact:
            if frontier_cx is not None and cx < frontier_cx - tol_x:
                result[fi] = None; continue
            frontier_cx = cx if frontier_cx is None else max(frontier_cx, cx)

    # Step 4 — leave-one-out outlier removal (confirmed frames protected)
    # For each unconfirmed point, fit a polynomial on ALL OTHER points and measure
    # how far off this point is from that fit. An isolated "leader" that's far ahead
    # of a consistent cluster will have a huge LOO residual even if the global fit
    # (which includes it) looks deceivingly okay.
    # Require ≥ 5 points before removing anything — with fewer points the LOO
    # polynomial is too underconstrained and removes real detections.
    for _pass in range(10):
        real = [(fi, d) for fi, d in sorted(result.items()) if d is not None]
        if len(real) < 5:
            break
        fis_r = np.array([fi        for fi, _ in real], dtype=float)
        cxs_r = np.array([d["cx"]*W for _, d in real], dtype=float)
        worst_fi = None; worst_resid = 40.0   # minimum threshold to trigger removal
        for i, (fi, _) in enumerate(real):
            if fi in confirmed:
                continue
            # Fit on all OTHER points
            mask = np.ones(len(real), dtype=bool); mask[i] = False
            f_loo, c_loo = fis_r[mask], cxs_r[mask]
            if len(f_loo) < 2:
                continue
            pred_i = np.polyval(np.polyfit(f_loo, c_loo, min(2, len(f_loo)-1)), fis_r[i])
            resid  = abs(cxs_r[i] - pred_i)
            if resid > worst_resid:
                worst_resid = resid; worst_fi = fi
        if worst_fi is None:
            break
        result[worst_fi] = None

    # Step 4 — backwards-pair cleanup: if exactly 2 pre-impact points remain and the
    # later one is to the LEFT of the earlier one, the first point is a ghost — drop it.
    pre_pts = sorted([(fi, d) for fi, d in result.items() if d and fi < impact],
                     key=lambda x: x[0])
    if len(pre_pts) == 2:
        fi_a, d_a = pre_pts[0]
        fi_b, d_b = pre_pts[1]
        if d_b["cx"] < d_a["cx"]:   # later point is behind earlier point
            result[fi_a] = None

    # Step 5 — smash guard: smash MUST be ≤ 1.55
    pm       = shot.get("precomputed") or {}
    ball_spd = float((pm.get("metrics") or {}).get("ballSpeedMph", 0) or 0)
    if ball_spd > 0:
        for _ in range(len(result)):
            active = {f: d for f, d in result.items() if d}
            if len(active) < 2:
                break
            lm_chk = compute_live_metrics(shot, active, params)
            cs     = (lm_chk or {}).get("club_speed")
            if not cs or cs <= 1e-3 or ball_spd / cs <= 1.55:
                break
            best_fi = None; best_smash = float("inf")
            for fi_try in list(active):
                test = {f: d for f, d in active.items() if f != fi_try}
                if len(test) < 2:
                    continue
                lm_t  = compute_live_metrics(shot, test, params)
                cs_t  = (lm_t or {}).get("club_speed")
                if not cs_t or cs_t <= 1e-3:
                    continue
                smash_t = ball_spd / cs_t
                if smash_t < best_smash:
                    best_smash = smash_t; best_fi = fi_try
            if best_fi is None:
                # Can't fix smash by removing any single point (not enough points
                # to test individually, or all single-point removals fail to compute
                # speed). Keep whatever detections exist — speed will be flagged
                # as unreliable by the caller, but hiding the detections is worse.
                break
            result[best_fi] = None

    n_nd  = sum(1 for d in raw_nd.values() if d)
    n_bf  = sum(1 for d in raw_bf.values() if d)
    n_out = sum(1 for d in result.values() if d)
    print(f"  [ensembleBFS] nd={n_nd}  bf={n_bf}  kept={n_out}  med_count={med_count:.0f}")
    return result


_SWIFT_BFS_BINARY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ensemble_bfs")

def _run_ensemble_bfs_swift(shot, p):
    """Call the compiled Swift ensemble_bfs binary and return its detections.

    Falls back to the Python _ensemble_pool_and_fit implementation if the binary
    is missing or crashes, so the GUI degrades gracefully during development.
    """
    def _python_fallback():
        impact  = shot["impact"]
        start   = max(1, impact - 3)
        end     = min(shot["N"] - 1, impact + 1)
        ball_imp = _ball_for_frame(shot, impact)
        raw_nd  = _run_bfs_sweep(shot, "newDiff",   "bgDiff",   impact, start, end, ball_imp)
        raw_bf  = _run_bfs_sweep(shot, "brightBFS", "baseline", impact, start, end, ball_imp)
        return _ensemble_pool_and_fit(raw_nd, raw_bf, shot, impact, start, end)

    if not os.path.exists(_SWIFT_BFS_BINARY):
        print("  [ensembleBFS] Swift binary not found — using Python fallback")
        return _python_fallback()

    params_json = json.dumps({k: float(v) for k, v in p.items()})
    try:
        res = subprocess.run(
            [_SWIFT_BFS_BINARY, shot["folder"], params_json],
            capture_output=True, text=True, timeout=30,
        )
        if res.returncode != 0:
            raise RuntimeError(res.stderr.strip())
        if res.stderr.strip():
            print(res.stderr.strip())   # forward Swift's [ensembleBFS] log line
        data = json.loads(res.stdout)
        dets = {}
        for d in data.get("detections", []):
            fi = d["frame"]
            dets[fi] = dict(cx=d["cx"], cy=d["cy"], count=d.get("count", 0),
                            lead_x=d.get("lead_x", d["cx"]), lead_y=d.get("lead_y", d["cy"]),
                            pass_id=1)
        return dets
    except Exception as e:
        print(f"  [ensembleBFS] Swift error: {e} — falling back to Python")
        return _python_fallback()


def _sweep_bfs_method(method: str):
    """Run a BFS-style method on every frame in the detection window.

    Covers streakBFS, brightBFS, newDiff, ensembleBFS.  Results are cached so
    scrubbing frames doesn't re-run the sweep; cache invalidates on shot/param change.
    """
    shot = S.shot
    if shot is None: return
    impact   = shot["impact"]
    start    = max(1, impact - 3)
    end      = min(shot["N"] - 1, impact + 1)
    ball_imp = _ball_for_frame(shot, impact)
    mask_method = _BFS_MASK_METHOD.get(method, method)

    pkey = tuple(sorted((k, round(float(v), 6) if isinstance(v, float) else v)
                        for k, v in params.items()))
    ckey = (shot.get("name", id(shot)), method, pkey)
    if ckey in _bfs_sweep_cache:
        all_dets, filtered, lm = _bfs_sweep_cache[ckey]
        S.all_detections      = dict(all_dets)
        S.filtered_detections = set(filtered)
        S.live_metrics        = lm
        return

    if method == "ensembleBFS":
        raw_dets = _run_ensemble_bfs_swift(shot, params)
    else:
        raw_dets = _run_bfs_sweep(shot, method, mask_method, impact, start, end, ball_imp)

    dets     = {fi: d for fi, d in raw_dets.items() if d is not None}
    filtered = set()

    lm = compute_live_metrics(shot, dets, params)
    _bfs_sweep_cache[ckey] = (dict(dets), set(filtered), lm)
    S.all_detections      = dict(dets)
    S.filtered_detections = set(filtered)
    S.live_metrics        = lm


def _sweep_streakbfs():
    _sweep_bfs_method("streakBFS")


# Secondary posStreak view window ─────────────────────────────────────────────
_streak_fig = None
_streak_ax  = None
_streak_det_history: dict = {}          # {shot_key: {fi: (cx_norm, cy_norm)}}
_streak_last_shot:   list = [None]      # mutable sentinel — reset history on shot change

def _update_streak_view():
    """Maintain a secondary popup window showing the posStreak diff + rightmost-BFS blob."""
    global _streak_fig, _streak_ax

    # Close the window when not in streak mode
    if S.method != "streak":
        if _streak_fig is not None and plt.fignum_exists(_streak_fig.number):
            plt.close(_streak_fig)
        _streak_fig = _streak_ax = None
        return

    if S.shot is None: return
    fi = S.frame_idx
    if fi == 0: return

    # Use the SAME mask result the main GUI already computed — no recompute
    mr = S.mask_result
    if mr is None: return

    dm               = mr["diff_map"]
    x0, y0           = mr["x0_px"], mr["y0_px"]
    rows, cols_      = dm.shape
    W, H             = S.shot["W"], S.shot["H"]
    thr              = float(params["diff_thresh"])

    # Normalize exactly as draw_mask() does
    dm_n = dm / max(float(dm.max()), 1e-6)

    # Ball exclusion: applied on every frame EXCEPT the exact impact frame.
    # At impact the club head IS at the ball position and must be detectable.
    # Post-impact the ball rolls/flies rightward — the right-of-ball column
    # mask catches it even though it has moved past its original position.
    impact_fi = S.shot.get("impact", None)
    apply_ball_excl = (impact_fi is None) or (fi != impact_fi)

    ball_obj = mr.get("ball") or _ball_for_frame(S.shot, fi)
    dm_disp = dm_n.copy()
    dm_det  = dm_n.copy()
    if ball_obj:
        bx_f   = ball_obj["cx"] * W
        by_f   = ball_obj["cy"] * H
        ball_r = ball_obj["dia"] * W / 2
        excl_r = ball_r * float(params.get("exclusion", 1.0))

        ys_b = (np.arange(rows, dtype=float) + y0)[:, None]
        xs_b = (np.arange(cols_, dtype=float) + x0)[None, :]
        dist_sq = (xs_b - bx_f) ** 2 + (ys_b - by_f) ** 2

        # Always fill the actual ball disc in the display so the dark
        # stationary-ball hole doesn't appear in the image
        ball_disc = dist_sq <= ball_r ** 2
        annulus   = (dist_sq > ball_r ** 2) & (dist_sq <= (ball_r * 1.8) ** 2)
        fill_val  = float(np.median(dm_n[annulus])) if annulus.any() else 0.0
        dm_disp[ball_disc] = fill_val

        ball_center_col = max(0, int(bx_f - x0))

        if impact_fi is not None and fi < impact_fi:
            # Pre-impact: only disc exclusion. The ball is stationary → near-zero
            # diff → no detectable ball blob anyway. The old column mask zeroed
            # everything RIGHT of ball centre, which blocked the club approaching
            # from the right.
            excl_disc = dist_sq <= excl_r ** 2
            dm_det[excl_disc] = 0.0

        elif impact_fi is not None and fi > impact_fi:
            # Post-impact: club has swung PAST the ball and is now to the LEFT.
            # Ball rolled RIGHT → ball blob is the rightmost. Only exclude the
            # original ball disc (departure ghost); use leftmost selection below.
            dm_det[ball_disc] = 0.0

        # At exactly impact_fi: no exclusion — club is at ball, detect freely

    post_impact = ball_obj is not None and impact_fi is not None and fi > impact_fi
    component = _rightmost_blob_from_diff(dm_det, leftmost=post_impact)

    # ── Path-fit filtering ────────────────────────────────────────────────────
    global _streak_det_history, _streak_last_shot
    shot_key = S.shot.get("name", str(id(S.shot)))
    if _streak_last_shot[0] != shot_key:
        _streak_det_history.clear()
        _streak_last_shot[0] = shot_key
    history: dict = _streak_det_history.setdefault(shot_key, {})

    # Raw centroid of BFS result (normalized 0–1)
    cx_raw = cy_raw = None
    if component:
        pxs_r = [c + x0 for _, c in component]
        pys_r = [r + y0 for r, _ in component]
        cx_raw = float(np.mean(pxs_r)) / W
        cy_raw = float(np.mean(pys_r)) / H
        history[fi] = (cx_raw, cy_raw)      # store every raw detection

    # Iterative linear-regression outlier removal over ALL history points.
    # Uses the same algorithm as temporal_filter: drop the single worst point
    # each iteration until every remaining point fits within MaxResid.
    max_r_norm = float(params.get("max_resid_px", 60)) / max(W, 1)
    all_pts  = sorted((f, cx, cy) for f, (cx, cy) in history.items())
    use_fit  = False
    cx_out   = cx_raw
    cy_out   = cy_raw

    if len(all_pts) >= 3:
        fis_h = np.array([f  for f,_,_  in all_pts], dtype=float)
        cxs_h = np.array([cx for _,cx,_ in all_pts], dtype=float)
        cys_h = np.array([cy for _,_,cy in all_pts], dtype=float)
        msk   = np.ones(len(fis_h), dtype=bool)

        for _ in range(10):
            if msk.sum() < 2: break
            t  = fis_h[msk]; xm = cxs_h[msk]; ym = cys_h[msk]
            tm = t.mean();   dn = float(((t - tm)**2).sum())
            if dn < 1e-6: break
            vx_f = float(np.dot(t - tm, xm)) / dn
            vy_f = float(np.dot(t - tm, ym)) / dn
            ox_f = float(xm.mean() - vx_f * tm)
            oy_f = float(ym.mean() - vy_f * tm)
            resid = np.sqrt((cxs_h - (vx_f * fis_h + ox_f))**2 +
                            (cys_h - (vy_f * fis_h + oy_f))**2)
            bad = msk & (resid > max_r_norm)
            if not bad.any(): break
            msk[int(np.argmax(np.where(msk, resid, -1.0)))] = False

        # If the current frame is an outlier, replace its centroid with the
        # fit-line interpolation so the display shows the expected position.
        curr_idx = next((i for i,(f,_,_) in enumerate(all_pts) if f == fi), None)
        if curr_idx is not None and msk.sum() >= 2 and not msk[curr_idx]:
            t2 = fis_h[msk]; xm2 = cxs_h[msk]; ym2 = cys_h[msk]
            tm2 = t2.mean(); dn2 = float(((t2 - tm2)**2).sum())
            if dn2 > 1e-6:
                vx2 = float(np.dot(t2 - tm2, xm2)) / dn2
                vy2 = float(np.dot(t2 - tm2, ym2)) / dn2
                cx_out = float(np.clip(vx2 * fi + xm2.mean() - vx2 * tm2, 0, 1))
                cy_out = float(np.clip(vy2 * fi + ym2.mean() - vy2 * tm2, 0, 1))
                use_fit = True
    # ─────────────────────────────────────────────────────────────────────────

    # Create or reuse figure
    if _streak_fig is None or not plt.fignum_exists(_streak_fig.number):
        _streak_fig = plt.figure("streak — rightmost blob", figsize=(7, 5))
        _streak_fig.patch.set_facecolor("#111111")
        _streak_ax  = _streak_fig.add_axes([0.0, 0.06, 1.0, 0.88])
        _streak_fig.show()

    ax = _streak_ax
    ax.cla()
    ax.set_facecolor("#000000")
    ext = [x0, x0+cols_, y0+rows, y0]

    frame_crop = S.shot["frames"][fi][y0:y0+rows, x0:x0+cols_]
    ax.imshow(frame_crop, origin="upper", aspect="auto", extent=ext, alpha=0.30, zorder=1)
    ax.imshow(dm_disp,    cmap="hot",    origin="upper", aspect="auto", extent=ext, alpha=0.80, zorder=2)

    # Raw BFS blob pixels (always shown)
    if component:
        comp_mask = np.zeros((rows, cols_), dtype=np.float32)
        for r, c in component:
            if 0 <= r < rows and 0 <= c < cols_:
                comp_mask[r, c] = 1.0
        rgba = np.zeros((rows, cols_, 4), dtype=np.float32)
        rgba[:, :, 2] = comp_mask
        rgba[:, :, 3] = comp_mask * 0.50
        ax.imshow(rgba, origin="upper", aspect="auto", extent=ext, zorder=3)

    # Centroid: cyan = raw OK, magenta = fit-replaced (outlier), grey x = where outlier was
    if cx_out is not None:
        dot_color = "#ff44ff" if use_fit else "cyan"
        ax.plot(cx_out * W, cy_out * H, "+", color=dot_color, ms=16, mew=2.5, zorder=6)
        ax.plot(cx_out * W, cy_out * H, "o", color=dot_color, ms=7,
                markerfacecolor="none", mew=1.5, zorder=6)
    if use_fit and cx_raw is not None:
        ax.plot(cx_raw * W, cy_raw * H, "x", color="#666666", ms=9, mew=1.5, zorder=5)

    # All history dots (dim, for context)
    for hfi, (hcx, hcy) in history.items():
        if hfi != fi:
            ax.plot(hcx * W, hcy * H, ".", color="#444444", ms=4, zorder=4)

    # Ball circle — only before impact
    if impact_fi is None or fi <= impact_fi:
        if ball_obj:
            from matplotlib.patches import Circle as _Circle
            bx_ = ball_obj["cx"]*W; by_ = ball_obj["cy"]*H; br_ = ball_obj["dia"]*W/2
            ax.add_patch(_Circle((bx_, by_), br_, fill=False,
                                 edgecolor="#ffff00", lw=1.5, zorder=5))

    ax.set_xlim(x0, x0+cols_); ax.set_ylim(y0+rows, y0); ax.axis("off")

    fit_tag  = " [FIT]" if use_fit else ""
    cx_disp  = cx_out if cx_out is not None else 0.0
    blob_tag = (f"comp={len(component)}px  cx={cx_disp:.3f}{fit_tag}"
                if (component or use_fit) else "no blob")
    ax.set_title(f"{S.shot['name']}  fi={fi}  thr={thr:.0f}  {blob_tag}",
                 color="white", fontsize=8, pad=4)

    _streak_fig.canvas.draw_idle()


def redraw():
    if S.shot is None:
        S.mask_result=None; S.blobs=[]
    else:
        method_for_mask = _BFS_MASK_METHOD.get(S.method, S.method)
        S.mask_result = build_mask(S.shot, S.frame_idx, method_for_mask, params)
        if S.method in _BFS_MASK_METHOD:
            _sweep_bfs_method(S.method)   # auto-populate S.all_detections for trail
            # Use sweep's decision for this frame — don't re-run BFS independently
            # (for ensemble methods the sweep may have chosen brightBFS for this frame)
            det = S.all_detections.get(S.frame_idx)
            S.blobs = [det] if det is not None else []
        else:
            S.blobs = find_blobs(S.mask_result, S.shot, params)
    draw_frame(); draw_mask(); draw_metrics(); draw_strip(); draw_info()
    fig.canvas.draw_idle()
    _update_streak_view()

# ─────────────────────────────────────────────────────────────────────────────
# Shot switching
# ─────────────────────────────────────────────────────────────────────────────

def load_current_shot():
    if not shots: S.shot=None; return
    print(f"Loading {os.path.basename(shots[S.shot_idx])} …", end=" ", flush=True)
    S.shot = load_shot(shots[S.shot_idx])
    if S.shot:
        pm = S.shot.get("precomputed") or {}
        z = float(pm.get("zeroDegreeReferenceAngleDegrees", params["zero_deg"]))
        params["zero_deg"]=z; sliders["zero_deg"].set_val(z)
        S.frame_idx = max(0, S.shot["impact"]-5)
        print(f"{S.shot['N']} frames  impact={S.shot['impact']}  0°={z:+.1f}")
    else: print("FAILED")
    S.mask_result=None; S.blobs=[]; S.all_detections={}; S.live_metrics=None
    S.filtered_detections=set(); S.predicted_frames=set(); S.pass_used=None; S.passes_used=set()
    S.bright_mask_on=False; S.dark_mask_on=False; S.grey_mask_on=False
    _bfs_sweep_cache.clear()

# ─────────────────────────────────────────────────────────────────────────────
# Run all frames
# ─────────────────────────────────────────────────────────────────────────────

def _run_detection_pass(shot, method, p, impact, start, end, ball_imp, pass_num):
    """Single diff-based detection pass over [start, end].

    Returns (raw_dets, dets, filtered_set):
      raw_dets  — detections before temporal filter (synthetic impact anchor excluded)
      dets      — after temporal filter (synthetic excluded)
      filtered_set — frame indices removed by filter
    """
    bx_imp = ball_imp["cx"] if ball_imp else None
    by_imp = ball_imp["cy"] if ball_imp else None

    raw_dets  = {}
    confirmed = []

    mask_method = _BFS_MASK_METHOD.get(method, method)
    is_bfs = method in _BFS_MASK_METHOD
    for fi in range(start, end + 1):
        mr = build_mask(shot, fi, mask_method, p, win_start=start, win_end=end)

        # Ball-anchor prediction: line from last confirmed detection → ball @ impact.
        pred_x = pred_y = None
        if confirmed and bx_imp is not None:
            last_fi, last_blob = confirmed[-1]
            dt = impact - last_fi
            if dt > 0:
                vx = (bx_imp - last_blob["cx"]) / dt
                vy = (by_imp - last_blob["cy"]) / dt
                pred_x = last_blob["cx"] + vx * (fi - last_fi)
                pred_y = last_blob["cy"] + vy * (fi - last_fi)

        if is_bfs:
            blobs = find_blobs_streak_bfs(mr, shot, p,
                                          impact_fi=impact, fi=fi, method=method)
        else:
            blobs = find_blobs(mr, shot, p, pred_x, pred_y)
        if blobs:
            best = dict(blobs[0], pass_id=pass_num)
            raw_dets[fi] = best
            confirmed.append((fi, best))
        else:
            raw_dets[fi] = None

    # Remove ghost detections that didn't move between consecutive frames
    if is_bfs:
        _dedup_consecutive_dets(raw_dets, shot["W"], shot["H"])
    if method == "newDiff":
        _apply_monotonicity(raw_dets, shot, ball_imp)

    # Inject ball@impact as a synthetic regression anchor so temporal filter's
    # linear fit is constrained to the known endpoint.
    injected = False
    if ball_imp is not None and raw_dets.get(impact) is None:
        raw_dets[impact] = dict(count=0, cx=ball_imp["cx"], cy=ball_imp["cy"],
                                 lead_x=ball_imp["cx"], lead_y=ball_imp["cy"],
                                 bbox=(ball_imp["cx"], ball_imp["cy"], 0.001, 0.001),
                                 dist=0.0, pass_id=-1, synthetic=True)
        injected = True

    dets, filtered = temporal_filter(raw_dets, shot, p)
    filtered.discard(impact)

    # Never let temporal filter silently remove a real impact detection —
    # filtered.discard only protects the set, not dets itself.
    if not injected and dets.get(impact) is None:
        real_imp = raw_dets.get(impact)
        if real_imp and not real_imp.get("synthetic"):
            dets[impact] = real_imp

    if injected:
        raw_dets.pop(impact, None)
        dets.pop(impact, None)
    elif pass_num >= 3:
        # P3/P4 absDiff sensitivity can independently detect a false blob at impact;
        # strip it so the visual anchor pins correctly to the true ball position.
        dets.pop(impact, None)

    return raw_dets, dets, filtered


def _check_line_quality(dets, shot, p):
    """True if kept detections are straight and heading toward the ball."""
    W, H = shot["W"], shot["H"]
    ordered = [(fi, d) for fi, d in sorted(dets.items())
               if d and not d.get("synthetic") and not d.get("predicted")]
    if len(ordered) < 2:
        return False
    fis = np.array([fi for fi, _ in ordered], dtype=float)
    xs  = np.array([d["cx"] * W for _, d in ordered])
    ys  = np.array([d["cy"] * H for _, d in ordered])

    # Straightness: worst single point residual from temporal linear fit.
    # Using max (not mean) so one clearly bad outlier fails the check.
    max_resid = float(p.get("max_resid_px", 60))
    cx_fit = np.polyfit(fis, xs, 1); cy_fit = np.polyfit(fis, ys, 1)
    resids = np.sqrt((xs - np.polyval(cx_fit, fis))**2 + (ys - np.polyval(cy_fit, fis))**2)
    if np.max(resids) > max_resid * 0.55:
        return False

    # Direction: net club motion must point toward ball at impact
    ball = _ball_for_frame(shot, shot["impact"])
    if ball:
        bx = ball["cx"] * W; by = ball["cy"] * H
        dx_t = xs[-1] - xs[0]; dy_t = ys[-1] - ys[0]
        dx_b = bx - xs[0];     dy_b = by - ys[0]
        if (dx_t**2 + dy_t**2) > 0 and (dx_b**2 + dy_b**2) > 0:
            if dx_t * dx_b + dy_t * dy_b < 0:
                return False
    return True


def _spatial_dedup(candidates, W, H, k_px=20):
    """Remove near-duplicate detections from a flat candidate pool.

    For detections within k_px pixels of each other, keeps the one with
    the lowest pass_id (most trusted). Ties broken by dist (prefer closer).
    Handles the common case where multiple passes independently find the
    same blob — we keep only the most trusted source and discard the clone.
    """
    if not candidates:
        return []
    ordered = sorted(candidates, key=lambda d: (d.get("pass_id", 9), d.get("dist", 0.0)))
    kept = []
    k2 = float(k_px * k_px)
    for c in ordered:
        cx_px = c["cx"] * W
        cy_px = c["cy"] * H
        dup = any((cx_px - k["cx"]*W)**2 + (cy_px - k["cy"]*H)**2 < k2 for k in kept)
        if not dup:
            kept.append(c)
    return kept


def train_ensemble():
    """Learn per-method weights from labeled data.

    For every labeled (shot, frame, cx, cy), runs each base method, measures
    the pixel distance to the label, then sets weight = 1/(mean_error+1).
    Saves results to ensemble_weights.json so they survive restarts.
    """
    if not _labels:
        print("No labels — use Label Mode first."); return

    print("\n── ENSEMBLE TRAINING ────────────────────────────────────────────")
    base_methods = ["absDiff", "posDiff", "negDiff", "baseline",
                    "optFlow", "bgDiff", "streak", "posStreak", "hsvDiff"]
    errors = {m: [] for m in base_methods}

    for sfolder in shots:
        shot = load_shot(sfolder)
        if shot is None: continue
        sname = os.path.basename(sfolder)
        frame_labels = _labels.get(sname, {})
        if not frame_labels: continue

        impact = shot["impact"]
        start  = max(1, impact - 3)
        end    = min(shot["N"] - 1, impact + 1)
        W, H   = shot["W"], shot["H"]

        for fi_str, (lx, ly) in frame_labels.items():
            fi = int(fi_str)
            if fi < 1: continue

            for method in base_methods:
                try:
                    mr = build_mask(shot, fi, method, params,
                                    win_start=start, win_end=end)
                    blobs = find_blobs(mr, shot, params) if mr else []
                except Exception:
                    blobs = []

                if blobs:
                    b = blobs[0]
                    err = math.hypot((b["cx"] - lx) * W,
                                     (b["cy"] - ly) * H)
                else:
                    err = float(W)   # full-width penalty for no detection

                errors[method].append(err)

    weights = {}
    print(f"  {'method':12s}  {'n':>4}  {'mean_err':>10}  {'weight':>8}")
    print("  " + "─" * 42)
    for m in base_methods:
        if errors[m]:
            mean_err = sum(errors[m]) / len(errors[m])
            w = 1.0 / (mean_err + 1.0)
        else:
            mean_err = float("inf"); w = 0.0
        weights[m] = w
        print(f"  {m:12s}  {len(errors[m]):>4}  {mean_err:>10.1f}px  {w:>8.5f}")

    total = sum(weights.values()) or 1.0
    weights = {m: w / total for m, w in weights.items()}
    _method_weights.clear()
    _method_weights.update(weights)
    WEIGHTS_FILE.write_text(json.dumps(weights, indent=2))
    print(f"\n  Saved → {WEIGHTS_FILE}\n")


def _run_ensemble(shot, p, impact, start, end, ball_imp):
    """Ensemble detection using learned per-method weights.

    Pass 1 — for every frame, run all base methods and collect the best
              candidate from each, tagged with its method weight.
    Fit   — weighted-average positions → linear trajectory fit (lstsq).
    Pass 2 — rescore every candidate by method_weight × trajectory_fit;
              pick the top-scoring candidate per frame.
    """
    W, H = shot["W"], shot["H"]
    base_methods = ["absDiff", "posDiff", "negDiff", "baseline",
                    "optFlow", "bgDiff", "streak", "posStreak", "hsvDiff"]

    uniform = 1.0 / len(base_methods)
    def mw(m): return _method_weights.get(m, uniform)

    # ── Pass 1: best candidate per method per frame ───────────────────────────
    all_cands = {}
    for fi in range(start, end + 1):
        cands = []
        for method in base_methods:
            try:
                mr = build_mask(shot, fi, method, p, win_start=start, win_end=end)
                blobs = find_blobs(mr, shot, p) if mr else []
            except Exception:
                blobs = []
            if blobs:
                cands.append((blobs[0], mw(method), method))
        all_cands[fi] = cands

    # ── Weighted-average initial position per frame ───────────────────────────
    init_pos = {}
    for fi, cands in all_cands.items():
        if not cands: continue
        tw = sum(w for _, w, _ in cands)
        if tw > 0:
            init_pos[fi] = (
                sum(b["cx"] * w for b, w, _ in cands) / tw,
                sum(b["cy"] * w for b, w, _ in cands) / tw,
            )

    # ── Linear trajectory fit (fi → cx, fi → cy) ─────────────────────────────
    slope_cx = slope_cy = intercept_cx = intercept_cy = None
    if len(init_pos) >= 2:
        fis   = np.array(sorted(init_pos), dtype=float)
        cxs   = np.array([init_pos[fi][0] for fi in fis.astype(int)])
        cys   = np.array([init_pos[fi][1] for fi in fis.astype(int)])
        A     = np.column_stack([fis, np.ones_like(fis)])
        slope_cx, intercept_cx = np.linalg.lstsq(A, cxs, rcond=None)[0]
        slope_cy, intercept_cy = np.linalg.lstsq(A, cys, rcond=None)[0]

    def traj_pred(fi):
        if slope_cx is None: return None, None
        return slope_cx * fi + intercept_cx, slope_cy * fi + intercept_cy

    # ── Pass 2: rescore and pick best per frame ───────────────────────────────
    raw_dets = {}
    for fi in range(start, end + 1):
        cands = all_cands.get(fi, [])
        if not cands:
            raw_dets[fi] = None; continue

        pcx, pcy = traj_pred(fi)
        best_blob = None; best_score = -1.0

        for blob, w, method in cands:
            if pcx is not None:
                traj_dist = math.hypot(blob["cx"] - pcx, blob["cy"] - pcy)
                traj_score = 1.0 / (1.0 + traj_dist * 15.0)
            else:
                traj_score = 1.0
            score = w * traj_score
            if score > best_score:
                best_score = score
                best_blob = dict(blob, pass_id=1)

        raw_dets[fi] = best_blob

    # ── Temporal filter ───────────────────────────────────────────────────────
    injected = False
    if ball_imp is not None and raw_dets.get(impact) is None:
        raw_dets[impact] = dict(count=0, cx=ball_imp["cx"], cy=ball_imp["cy"],
                                lead_x=ball_imp["cx"], lead_y=ball_imp["cy"],
                                bbox=(ball_imp["cx"], ball_imp["cy"], 0.001, 0.001),
                                dist=0.0, pass_id=-1, synthetic=True)
        injected = True

    dets, filtered = temporal_filter(raw_dets, shot, p)
    filtered.discard(impact)

    if not injected and dets.get(impact) is None:
        real_imp = raw_dets.get(impact)
        if real_imp and not real_imp.get("synthetic"):
            dets[impact] = real_imp

    if injected:
        raw_dets.pop(impact, None); dets.pop(impact, None)

    n_real = sum(1 for v in dets.values() if v and not v.get("synthetic"))
    trained = "trained" if _method_weights else "untrained"
    print(f"ensemble({trained}) kept:{n_real}", end="  ")
    return 1, raw_dets, dets, filtered


def _run_ransac(shot, p, impact, start, end, ball_imp):
    """Trajectory-first RANSAC club tracker.

    Instead of committing to a single blob per frame, collect EVERY candidate
    blob from absDiff across all frames, then find the linear trajectory in
    (frame_index → cx) space that has the most support.  Inliers become the
    detection set; they are guaranteed to lie on a physically plausible path.

    Returns (pass_id, raw_dets, dets, filtered_set) matching _run_detection_pass.
    """
    W, H = shot["W"], shot["H"]

    # Gather all blobs from all frames using a loose threshold
    p_loose = dict(p, diff_thresh=p["diff_thresh"]*0.5,
                   min_area=p["min_area"]*0.3, max_aspect=4.0)
    all_blobs = {}   # fi → list of blob dicts
    for fi in range(start, end + 1):
        mr = build_mask(shot, fi, "absDiff", p_loose, win_start=start, win_end=end)
        blobs = find_blobs(mr, shot, p_loose) if mr else []
        if blobs:
            all_blobs[fi] = [dict(b, fi=fi, pass_id=1) for b in blobs[:4]]

    frames_with_blobs = [fi for fi in sorted(all_blobs) if all_blobs[fi]]
    best_inliers = {}

    if len(frames_with_blobs) >= 2:
        # Try every pair of (frame, blob) as the two anchor points of a line
        # in (fi → cx) space.  Score = number of other frames whose closest
        # blob lands within inlier_thr normalised units of the line.
        inlier_thr = 0.04   # ~4% of frame width
        best_score = -1

        for i, fi_a in enumerate(frames_with_blobs):
            for blob_a in all_blobs[fi_a]:
                for fi_b in frames_with_blobs[i+1:]:
                    for blob_b in all_blobs[fi_b]:
                        dfi = fi_b - fi_a
                        if dfi == 0: continue
                        slope = (blob_b["cx"] - blob_a["cx"]) / dfi
                        intercept = blob_a["cx"] - slope * fi_a

                        inliers = {}
                        for fi_t, blobs_t in all_blobs.items():
                            pred_cx = slope * fi_t + intercept
                            best_blob = min(blobs_t, key=lambda b: abs(b["cx"] - pred_cx))
                            if abs(best_blob["cx"] - pred_cx) < inlier_thr:
                                inliers[fi_t] = best_blob

                        if len(inliers) > best_score:
                            best_score = len(inliers)
                            best_inliers = inliers

    # Build raw_dets from inliers (None for frames with no support)
    raw_dets = {fi: best_inliers.get(fi) for fi in range(start, end + 1)}

    dets, filtered = temporal_filter(raw_dets, shot, p)
    filtered.discard(impact)
    if not dets.get(impact):
        raw_imp = raw_dets.get(impact)
        if raw_imp and not raw_imp.get("synthetic"):
            dets[impact] = raw_imp

    n_real = sum(1 for v in dets.values() if v and not v.get("synthetic"))
    print(f"blobs:{sum(len(v) for v in all_blobs.values())} inliers:{len(best_inliers)} kept:{n_real}", end="  ")
    return 1, raw_dets, dets, filtered


def run_all():
    shot = S.shot
    if shot is None: return
    impact = shot["impact"]
    skip  = max(0, int(round(params.get("skip_near_impact", 2))))
    start = max(1, impact - 3)
    end   = min(shot["N"] - 1, impact + 1)
    ball_imp = _ball_for_frame(shot, impact)
    W, H = shot["W"], shot["H"]

    p3 = dict(params, diff_thresh=params["diff_thresh"]*0.42,
              min_area=params["min_area"]*0.28, dilate=params["dilate"]+1.5,
              roi_y=params["roi_y"]*0.5)
    p4 = dict(params, diff_thresh=params["diff_thresh"]*0.55,
              min_area=params["min_area"]*0.73, dilate=max(1.0,params["dilate"]-0.5),
              roi_y=params["roi_y"]*0.5)

    pass_cfgs = [(1, S.method, params), (2, "absDiff", params),
                 (3, "absDiff", p3),    (4, "absDiff", p4)]

    # ── Detection: RANSAC trajectory OR cascade of passes ────────────────────
    print(f"[{shot['name']}] [{start}–{end}]", end="  ", flush=True)
    chosen_pn   = None
    chosen_raw  = None
    chosen_dets = None
    chosen_filt = set()

    if S.method == "ransac":
        chosen_pn, chosen_raw, chosen_dets, chosen_filt = _run_ransac(
            shot, params, impact, start, end, ball_imp)
        print(f"RANSAC→P{chosen_pn}")
    elif S.method == "ensemble":
        chosen_pn, chosen_raw, chosen_dets, chosen_filt = _run_ensemble(
            shot, params, impact, start, end, ball_imp)
        print()
    else:
        for pn, method, p in pass_cfgs:
            raw, dets, filt = _run_detection_pass(shot, method, p, impact, start, end, ball_imp, pass_num=pn)
            n_real = sum(1 for v in dets.values() if v and not v.get("synthetic"))
            tag = f"P{pn}:{'✓' if n_real>=1 else '✗'}{n_real}"

            if chosen_pn is None:
                reject = None

                if n_real < 2:
                    reject = "cnt"

                # Club path must be within ±20°
                if reject is None:
                    lm_t = compute_live_metrics(shot, dets, params)
                    if lm_t and lm_t.get("club_path") is not None:
                        cp = lm_t["club_path"]
                        if abs(cp) > 20.0:
                            reject = f"path{cp:+.0f}"

                # Trajectory must extrapolate to within 1 ball diameter of ball
                # center at the impact frame — ensures the path actually reaches
                # the ball, not some random arc across the ROI.
                if reject is None and ball_imp is not None:
                    real_pts = sorted(
                        [(fi, d["cx"], d["cy"]) for fi, d in dets.items()
                         if d and not d.get("synthetic") and not d.get("predicted")],
                        key=lambda x: x[0])
                    if len(real_pts) >= 2:
                        fis_r = np.array([p[0] for p in real_pts], dtype=float)
                        cxs_r = np.array([p[1] for p in real_pts], dtype=float)
                        cys_r = np.array([p[2] for p in real_pts], dtype=float)
                        A_r   = np.column_stack([fis_r, np.ones_like(fis_r)])
                        sx, bx_ = np.linalg.lstsq(A_r, cxs_r, rcond=None)[0]
                        sy, by_ = np.linalg.lstsq(A_r, cys_r, rcond=None)[0]
                        pred_cx = sx * impact + bx_
                        pred_cy = sy * impact + by_
                        dist_px = math.hypot(
                            (pred_cx - ball_imp["cx"]) * W,
                            (pred_cy - ball_imp["cy"]) * H)
                        if dist_px > ball_imp["dia"] * W:
                            reject = f"miss{dist_px:.0f}px"

                if reject is None or pn == 4:
                    chosen_pn = pn; chosen_raw = raw; chosen_dets = dets; chosen_filt = filt
                    tag += "→"
                else:
                    tag += f"✗{reject}"

            print(tag, end="  ", flush=True)
        print(f"  → P{chosen_pn}")

    S.pass_used            = chosen_pn
    S.passes_used          = {chosen_pn}
    S.filtered_detections  = chosen_filt

    # ── Extrapolate near-impact gaps ───────────────────────────────────────────
    S.predicted_frames = set()
    dets, S.predicted_frames = extrapolate_near_impact(
        chosen_dets, shot, params, impact, skip,
        raw_dets=chosen_raw, rejected=S.filtered_detections)

    S.all_detections = dets
    S.live_metrics   = compute_live_metrics(shot, dets, params)

    # ── Smash hard cap ────────────────────────────────────────────────────────
    # Smash factor = ball_speed / club_speed; physics guarantees smash ≤ 1.55.
    # If smash exceeds that, a bad detection is making the club appear to move
    # too slowly. Iteratively remove the point whose removal most reduces smash
    # until the cap is satisfied or only 2 real points remain.
    m_stored = (shot.get("precomputed") or {}).get("metrics") or {}
    ball_spd = m_stored.get("ballSpeedMph")
    if ball_spd:
        for _iter in range(8):
            lm = S.live_metrics
            if not lm: break
            club_spd = lm.get("club_speed") or 0.0
            if club_spd <= 0: break
            smash = ball_spd / club_spd
            if smash <= 1.55: break
            cur_real = [fi for fi, d in S.all_detections.items()
                        if d and not d.get("predicted") and not d.get("synthetic")]
            if len(cur_real) < 2: break
            best_fi = None; best_smash = smash
            for test_fi in cur_real:
                test_dets = {fi: (None if fi == test_fi else d)
                             for fi, d in S.all_detections.items()}
                tlm = compute_live_metrics(shot, test_dets, params)
                if tlm and (tlm.get("club_speed") or 0) > 0:
                    ts = ball_spd / tlm["club_speed"]
                    if ts < best_smash:
                        best_smash = ts; best_fi = test_fi
            if best_fi is None: break
            S.all_detections[best_fi] = None
            S.filtered_detections.add(best_fi)
            print(f"  [smash cap] removed fi={best_fi}  {smash:.2f}→{best_smash:.2f}")
            S.live_metrics = compute_live_metrics(shot, S.all_detections, params)

    # Update contributing passes after smash removal
    final_contrib = {d.get("pass_id", 1) for d in S.all_detections.values()
                     if d and not d.get("synthetic") and not d.get("predicted")}
    if final_contrib:
        S.passes_used = final_contrib
        S.pass_used   = min(final_contrib)


    if S.live_metrics:
        lm = S.live_metrics
        smash_tag = ""
        if ball_spd and (lm.get("club_speed") or 0) > 0:
            smash_tag = f"  smash:{ball_spd/lm['club_speed']:.2f}"
        print(f"  speed: {_fmt(lm.get('club_speed'),' mph')}  "
              f"path: {_fmt_lr(lm.get('club_path'))}  "
              f"attack: {_fmt(lm.get('attack_angle'),'°')}  "
              f"pts: {lm['points']}{smash_tag}")
    redraw()

# ─────────────────────────────────────────────────────────────────────────────
# Event handlers
# ─────────────────────────────────────────────────────────────────────────────

def _on_slider(_):
    for k,sl in sliders.items(): params[k]=sl.val
    redraw()
for sl in sliders.values(): sl.on_changed(_on_slider)

def _on_method(label): S.method=label; redraw()
radio.on_clicked(_on_method)

buttons["prev_shot"].on_clicked(lambda _: (setattr(S,"shot_idx",(S.shot_idx-1)%len(shots)) if shots else None, load_current_shot(), redraw()))
buttons["next_shot"].on_clicked(lambda _: (setattr(S,"shot_idx",(S.shot_idx+1)%len(shots)) if shots else None, load_current_shot(), redraw()))
buttons["prev_frame"].on_clicked(lambda _: (setattr(S,"frame_idx",max(0,S.frame_idx-1)), redraw()) if S.shot else None)
buttons["next_frame"].on_clicked(lambda _: (setattr(S,"frame_idx",min(S.shot["N"]-1,S.frame_idx+1)), redraw()) if S.shot else None)
buttons["impact_btn"].on_clicked(lambda _: (setattr(S,"frame_idx",S.shot["impact"]), redraw()) if S.shot else None)
buttons["run_btn"].on_clicked(lambda _: run_all())
buttons["save_btn"].on_clicked(lambda _: save_labels())
buttons["dump_btn"].on_clicked(lambda _: dump_state())
buttons["eval_btn"].on_clicked(lambda _: run_batch_eval())

def _mask_btns_off():
    for k in ("bright_btn","dark_btn","grey_btn"):
        buttons[k].ax.set_facecolor("#1a1a2e")

def _on_bright_mask(_):
    S.bright_mask_on = not S.bright_mask_on
    S.dark_mask_on = S.grey_mask_on = False
    _mask_btns_off()
    if S.bright_mask_on: buttons["bright_btn"].ax.set_facecolor("#553300")
    redraw()

def _on_dark_mask(_):
    S.dark_mask_on = not S.dark_mask_on
    S.bright_mask_on = S.grey_mask_on = False
    _mask_btns_off()
    if S.dark_mask_on: buttons["dark_btn"].ax.set_facecolor("#221144")
    redraw()

def _on_grey_mask(_):
    S.grey_mask_on = not S.grey_mask_on
    S.bright_mask_on = S.dark_mask_on = False
    _mask_btns_off()
    if S.grey_mask_on: buttons["grey_btn"].ax.set_facecolor("#113322")
    redraw()

buttons["bright_btn"].on_clicked(_on_bright_mask)
buttons["dark_btn"].on_clicked(_on_dark_mask)
buttons["grey_btn"].on_clicked(_on_grey_mask)

def _on_label_toggle(_):
    S.label_mode=not S.label_mode
    buttons["label_btn"].color="#660000" if S.label_mode else "#1a1a2e"; redraw()
buttons["label_btn"].on_clicked(_on_label_toggle)

def _on_clear(_):
    if S.shot: clear_label(S.shot["name"],S.frame_idx); redraw()
buttons["clear_btn"].on_clicked(_on_clear)

def _on_click(event):
    if event.inaxes==ax_frame and S.shot and S.label_mode and event.xdata:
        W,H=S.shot["W"],S.shot["H"]
        cx=max(0.0,min(1.0,event.xdata/W)); cy=max(0.0,min(1.0,event.ydata/H))
        if event.button==3: clear_label(S.shot["name"],S.frame_idx)
        else: set_label(S.shot["name"],S.frame_idx,cx,cy); print(f"Labeled {S.frame_idx}: ({cx:.3f},{cy:.3f})")
        redraw()
    elif event.inaxes==ax_strip and S.shot and event.xdata is not None:
        fi=int(event.xdata*S.shot["N"]); S.frame_idx=max(0,min(S.shot["N"]-1,fi)); redraw()

def _on_key(event):
    k=event.key
    if   k=="right":  setattr(S,"frame_idx",min(S.shot["N"]-1,S.frame_idx+1)); redraw()
    elif k=="left":   setattr(S,"frame_idx",max(0,S.frame_idx-1)); redraw()
    elif k=="]":      setattr(S,"shot_idx",(S.shot_idx+1)%len(shots)); load_current_shot(); redraw()
    elif k=="[":      setattr(S,"shot_idx",(S.shot_idx-1)%len(shots)); load_current_shot(); redraw()
    elif k=="i":      setattr(S,"frame_idx",S.shot["impact"]); redraw()
    elif k=="r":      run_all()
    elif k=="p":      dump_state()
    elif k=="l":      _on_label_toggle(None)
    elif k=="s":      save_labels()
    elif k=="e":      run_batch_eval()
    elif k=="d":      export_debug_pngs()
    elif k=="t":      train_ensemble()

fig.canvas.mpl_connect("button_press_event", _on_click)
fig.canvas.mpl_connect("key_press_event",    _on_key)

# ─────────────────────────────────────────────────────────────────────────────
# Debug PNG export
# ─────────────────────────────────────────────────────────────────────────────

def export_debug_pngs(output_dir=None):
    """Export one annotated PNG per shot showing every candidate and its fate."""
    from matplotlib.figure import Figure
    from matplotlib.backends.backend_agg import FigureCanvasAgg
    from matplotlib.patches import Circle
    from matplotlib.lines import Line2D

    if not shots:
        print("No shots loaded."); return

    out_root = output_dir or os.path.join(os.path.dirname(shots[0]), "debug_pngs")
    os.makedirs(out_root, exist_ok=True)
    print(f"\n── DEBUG EXPORT  {len(shots)} shots → {out_root} ──────────")

    for si, sfolder in enumerate(shots):
        shot = load_shot(sfolder)
        if shot is None: continue
        sname = os.path.basename(sfolder)
        print(f"  [{si+1}/{len(shots)}] {sname}", end="  ", flush=True)

        impact = shot["impact"]
        start  = max(1, impact - 3)
        end    = min(shot["N"] - 1, impact + 1)
        ball_imp = _ball_for_frame(shot, impact)
        W, H = shot["W"], shot["H"]

        p3 = dict(params, diff_thresh=params["diff_thresh"]*0.42,
                  min_area=params["min_area"]*0.28, dilate=params["dilate"]+1.5,
                  roi_y=params["roi_y"]*0.5)
        p4 = dict(params, diff_thresh=params["diff_thresh"]*0.55,
                  min_area=params["min_area"]*0.73, dilate=max(1.0, params["dilate"]-0.5),
                  roi_y=params["roi_y"]*0.5)
        pass_cfgs = [(1, S.method, params), (2, "absDiff", params),
                     (3, "absDiff", p3),    (4, "absDiff", p4)]

        # ── Replicate full pipeline, capturing each intermediate state ─────────
        all_cands = []
        for pn, method, p in pass_cfgs:
            _, dets, _ = _run_detection_pass(shot, method, p, impact, start, end,
                                             ball_imp, pass_num=pn)
            for fi, det in dets.items():
                if det is not None:
                    all_cands.append(dict(det, fi=fi))

        pool_dedup  = _spatial_dedup(all_cands, W, H, k_px=20)
        dedup_sigs  = {(round(c["cx"]*W), round(c["cy"]*H)) for c in pool_dedup}

        pool_impact = pool_dedup
        impact_sigs = dedup_sigs
        if ball_imp is not None:
            bx = ball_imp["cx"]*W; by = ball_imp["cy"]*H; bdia = ball_imp["dia"]*W
            def _ok(c):
                if c["fi"] != impact: return True
                dx = c["cx"]*W - bx; dy = c["cy"]*H - by
                return (dx*dx + dy*dy < (bdia*2)**2) and (c["cx"]*W <= bx + bdia*0.5)
            pool_impact = [c for c in pool_dedup if _ok(c)]
            impact_sigs = {(round(c["cx"]*W), round(c["cy"]*H)) for c in pool_impact}

        merged_pre = {}
        unassigned = []
        for c in sorted(pool_impact, key=lambda d: (d.get("pass_id",9), d.get("dist",0))):
            fi = c["fi"]
            if fi not in merged_pre: merged_pre[fi] = c
            else: unassigned.append(c)
        for c in sorted(unassigned, key=lambda d: d["cx"]):
            cx_c = c["cx"]
            for fi in range(start, impact+1):
                if merged_pre.get(fi) is not None: continue
                lo_l = [d["cx"] for f,d in merged_pre.items() if d and f < fi]
                hi_l = [d["cx"] for f,d in merged_pre.items() if d and f > fi]
                lo_cx = max(lo_l) if lo_l else None
                hi_cx = min(hi_l) if hi_l else None
                if lo_cx is not None and hi_cx is not None and lo_cx < cx_c < hi_cx:
                    merged_pre[fi] = dict(c, fi=fi); break
                elif lo_cx is None and hi_cx is not None and cx_c < hi_cx:
                    merged_pre[fi] = dict(c, fi=fi); break
                elif hi_cx is None and lo_cx is not None and cx_c > lo_cx:
                    merged_pre[fi] = dict(c, fi=fi); break

        dets_filt, filtered_set = temporal_filter(merged_pre, shot, params)

        m_stored  = (shot.get("precomputed") or {}).get("metrics") or {}
        ball_spd  = m_stored.get("ballSpeedMph")
        smash_removed = set()
        dets_work = dict(dets_filt)
        if ball_spd:
            lm = compute_live_metrics(shot, dets_work, params)
            for _ in range(8):
                if not lm: break
                cs = lm.get("club_speed") or 0.0
                if cs <= 0 or ball_spd / cs <= 1.55: break
                real = [fi for fi,d in dets_work.items()
                        if d and not d.get("predicted") and not d.get("synthetic")]
                if len(real) < 2: break
                best_fi = None; best_s = ball_spd / cs
                for tfi in real:
                    td  = {fi: (None if fi==tfi else d) for fi,d in dets_work.items()}
                    tlm = compute_live_metrics(shot, td, params)
                    if tlm and (tlm.get("club_speed") or 0) > 0:
                        ts = ball_spd / tlm["club_speed"]
                        if ts < best_s: best_s = ts; best_fi = tfi
                if best_fi is None: break
                dets_work[best_fi] = None
                smash_removed.add(best_fi)
                lm = compute_live_metrics(shot, dets_work, params)

        final_metrics = compute_live_metrics(shot, dets_work, params)

        # ── Render ─────────────────────────────────────────────────────────────
        fig = Figure(figsize=(14, 14 * H / W), facecolor="#111111")
        FigureCanvasAgg(fig)
        ax = fig.add_axes([0, 0.07, 1, 0.93])
        ax.set_facecolor("#111111")

        # Background: impact frame
        ax.imshow(shot["frames"][impact], extent=[0, W, H, 0], aspect="auto", zorder=0)

        # Ball at impact
        if ball_imp is not None:
            bball_x = ball_imp["cx"]*W; bball_y = ball_imp["cy"]*H
            bball_r = ball_imp["dia"]*W / 2
            ax.add_patch(Circle((bball_x, bball_y), bball_r, fill=False,
                                edgecolor="yellow", lw=2.5, zorder=10))
            ax.text(bball_x, bball_y - bball_r - 4, "ball", color="yellow",
                    fontsize=6, ha="center", zorder=11)

        # All raw candidates — tiny markers, dimmer if they were dedup'd
        for c in all_cands:
            sig = (round(c["cx"]*W), round(c["cy"]*H))
            pn  = c.get("pass_id", 1)
            col = _PASS_COLORS.get(pn, "#ffffff")
            survived = sig in dedup_sigs
            ax.plot(c["cx"]*W, c["cy"]*H,
                    ".", color=col, ms=5 if survived else 2,
                    alpha=0.65 if survived else 0.2, zorder=3)

        # Detections that made it into merged_pre but were rejected by filtering
        for fi, c in merged_pre.items():
            if c is None: continue
            pn  = c.get("pass_id", 1)
            col = _PASS_COLORS.get(pn, "#ffffff")
            if fi in smash_removed:
                # Red X = removed by smash cap
                ax.plot(c["cx"]*W, c["cy"]*H, "x",  color="#ff3333",
                        ms=14, mew=3, zorder=7)
                ax.plot(c["cx"]*W, c["cy"]*H, "o",  color="#ff3333",
                        ms=16, markerfacecolor="none", mew=1.5, alpha=0.7, zorder=6)
                ax.text(c["cx"]*W+6, c["cy"]*H-6, f"fi={fi} SMASH",
                        color="#ff3333", fontsize=6.5, fontweight="bold", zorder=8)
            elif fi in filtered_set:
                # Pass-colored X = rejected by temporal filter
                ax.plot(c["cx"]*W, c["cy"]*H, "x",  color=col, ms=12, mew=2.5, zorder=7)
                ax.plot(c["cx"]*W, c["cy"]*H, "o",  color=col, ms=14,
                        markerfacecolor="none", mew=1.5, alpha=0.7, zorder=6)
                ax.text(c["cx"]*W+6, c["cy"]*H-6, f"fi={fi} filt",
                        color=col, fontsize=6.5, zorder=8)

        # Final accepted detections — large solid dots, labeled
        accepted = [(fi,d) for fi,d in sorted(dets_work.items())
                    if d and not d.get("predicted") and not d.get("synthetic")]
        for fi, d in accepted:
            pn  = d.get("pass_id", 1)
            col = _PASS_COLORS.get(pn, "#ff9900")
            ax.plot(d["cx"]*W, d["cy"]*H, "o", color=col, ms=12, zorder=9)
            ax.text(d["cx"]*W+6, d["cy"]*H-6, f"fi={fi} P{pn}",
                    color=col, fontsize=7.5, fontweight="bold", zorder=10)

        # Path line through accepted
        if len(accepted) >= 2:
            ax.plot([d["cx"]*W for _,d in accepted],
                    [d["cy"]*H for _,d in accepted],
                    "-", color="white", lw=2, alpha=0.7, zorder=8)

        ax.set_xlim(0, W); ax.set_ylim(H, 0); ax.axis("off")

        # Legend
        legend_elems = [
            Line2D([0],[0], marker=".", color=_PASS_COLORS[pn], ms=8, ls="",
                   alpha=0.9, label=f"P{pn} raw")
            for pn in sorted(_PASS_COLORS)
        ] + [
            Line2D([0],[0], marker="o", color="white",   ms=11, ls="",  label="accepted (final)"),
            Line2D([0],[0], marker="x", color="gray",    ms=10, mew=2.5, ls="", label="rejected (temporal filter)"),
            Line2D([0],[0], marker="x", color="#ff3333", ms=10, mew=2.5, ls="", label="removed (smash cap)"),
            Line2D([0],[0], marker=".", color="gray",    ms=3,  ls="",  alpha=0.3, label="dedup'd out"),
            Line2D([0],[0], marker="o", color="yellow",  ms=10, markerfacecolor="none", ls="", label="ball@impact"),
        ]
        ax.legend(handles=legend_elems, loc="lower right", fontsize=7,
                  facecolor="#1a1a2e", edgecolor="#555", labelcolor="white", framealpha=0.92)

        # Bottom info bar
        ax_info2 = fig.add_axes([0, 0, 1, 0.07])
        ax_info2.set_facecolor("#000000"); ax_info2.axis("off")
        spd_s  = f"{final_metrics['club_speed']:.1f} mph" if final_metrics and final_metrics.get("club_speed") else "n/a"
        smsh_s = (f"   smash {ball_spd/final_metrics['club_speed']:.2f}"
                  if ball_spd and final_metrics and final_metrics.get("club_speed") else "")
        contrib = {d.get("pass_id",1) for _,d in accepted}
        pass_s  = f"   P{'+P'.join(str(p) for p in sorted(contrib))}" if contrib else ""
        n_raw  = len(all_cands); n_dedup = len(pool_dedup)
        n_filt = len(filtered_set); n_smash = len(smash_removed)
        n_kept = len(accepted)
        stats_s = (f"   raw:{n_raw}  dedup:{n_dedup}  filt:{n_filt}  "
                   f"smash:{n_smash}  kept:{n_kept}")
        ax_info2.text(0.01, 0.55, f"{sname}   {spd_s}{smsh_s}{pass_s}",
                      color="white", fontsize=9, fontweight="bold",
                      va="center", transform=ax_info2.transAxes)
        ax_info2.text(0.01, 0.15, stats_s,
                      color="#aaaaaa", fontsize=7.5,
                      va="center", transform=ax_info2.transAxes)

        out_path = os.path.join(out_root, f"{sname}_debug.png")
        fig.savefig(out_path, dpi=150, bbox_inches="tight", facecolor="#111111")
        print(f"✓  {os.path.basename(out_path)}")

    print(f"── Done. Open: {out_root}\n")


# ─────────────────────────────────────────────────────────────────────────────
# Batch eval
# ─────────────────────────────────────────────────────────────────────────────

def run_batch_eval():
    total=sum(len(v) for v in _labels.values())
    if total==0: print("No labels — use Label Mode first."); return
    print(f"\n── BATCH EVAL  ({total} labeled frames) ──────────────────────────")
    print(f"{'Method':<12}  {'HitRate':>8}  {'AvgErr(px)':>11}  {'n':>5}")
    print("─"*46)
    for method in METHODS:
        errs=[]; hits=0; labeled=0
        for sname,flabels in _labels.items():
            sfolder=next((s for s in shots if os.path.basename(s)==sname),None)
            if sfolder is None: continue
            shot=load_shot(sfolder)
            if shot is None: continue
            for fidx_str,(lx,ly) in flabels.items():
                fi=int(fidx_str)
                if fi>=shot["N"] or fi==0: continue
                labeled+=1
                mr=build_mask(shot,fi,method,params)
                blobs=find_blobs(mr,shot,params)
                if blobs:
                    b=blobs[0]
                    err=math.hypot((b["lead_x"]-lx)*shot["W"],(b["lead_y"]-ly)*shot["H"])
                    errs.append(err)
                    if err<50: hits+=1
        print(f"{method:<12}  {100*hits/max(labeled,1):>7.0f}%  "
              f"{sum(errs)/len(errs):>11.1f}  {labeled:>5}" if errs else
              f"{method:<12}  {'0%':>8}  {'—':>11}  {labeled:>5}")
    print("─ hit = within 50px of label ───────────────────────────────────\n")

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def _restore_saved_params():
    """On startup, reload params + method from the last p-dump so settings persist."""
    if not STATE_FILE.exists(): return
    try:
        state = json.loads(STATE_FILE.read_text())
        saved = state.get("params", {})
        for k, v in saved.items():
            if k in params:
                params[k] = float(v)
                if k in sliders:
                    sl = sliders[k]
                    clamped = max(sl.valmin, min(sl.valmax, float(v)))
                    sl.set_val(clamped)
        if state.get("method") in METHODS:
            S.method = state["method"]
            radio.set_active(METHODS.index(S.method))
        print(f"Restored params from {STATE_FILE.name}  (method={S.method})")
    except Exception as e:
        print(f"Could not restore params: {e}")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", nargs="?", default=".", help="Folder with ShotExport_* subfolders")
    args = ap.parse_args()
    shots = discover_shots(args.root)
    if not shots: print(f"No ShotExport_* in: {args.root}"); sys.exit(1)
    print(f"Found {len(shots)} shots")
    load_labels()
    if WEIGHTS_FILE.exists():
        _method_weights.update(json.loads(WEIGHTS_FILE.read_text()))
        top = sorted(_method_weights, key=lambda m: -_method_weights[m])[:3]
        print(f"Loaded ensemble weights  top: {', '.join(f'{m}={_method_weights[m]:.3f}' for m in top)}")
    _restore_saved_params()   # reload last p-dump
    load_current_shot()
    redraw()
    plt.show()
