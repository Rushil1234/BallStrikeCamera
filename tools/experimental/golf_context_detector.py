#!/usr/bin/env python3
"""Golf-context detector — hue-distance channel + golf physics priors.

Priors (why this isn't generic blob detection):
  BALL  starts at the pre-shot LOCK (metadata.json locked_ball_rect), stays
        there until impact, then moves monotonically FORWARD along one
        straight line — over the few feet we see, there is no curve.
  CLUB  approaches from BEHIND the ball inside a ±60° cone (apex at the lock,
        axis pointing backward), passes through the lock at impact, and its
        head is the moving compact blob — never the bag, mat markings, or
        edge strips. Two-pass search: bright/chrome first (hue-distance mask),
        then a DARK pass (black crowns, dark wedges) if the bright pass finds
        nothing.

Markers only appear when a candidate passes hard cutoffs — an empty frame is
the honest answer once the ball is out of frame.

Usage:
  python3 golf_context_detector.py --archive <AllFramesArchive> [--replay <dir>]
      [--auto 50 | --shots a,b] [--pre 2] [--post 7] --out out.html [--open]
"""
import argparse, base64, json, math, os, sys
import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hsv_object_explorer import frame_path, pick_diverse, impact_index  # noqa: E402
from hue_dist_gallery import hue_dist, b64jpg  # noqa: E402

FLIGHT_DIR = -1.0          # ball flies toward -x with the current mount
CONE_HALF_DEG = 60.0


def blobs_from_mask(mask, motion, min_area=12):
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    Hh, Ww = mask.shape
    out = []
    for c in contours:
        area = cv2.contourArea(c)
        if area < min_area:
            continue
        (ex, ey), er = cv2.minEnclosingCircle(c)
        m = cv2.moments(c)
        if m['m00'] <= 0:
            continue
        x, y, w, h = cv2.boundingRect(c)
        out.append({
            'area': area,
            'circ': float(area / (np.pi * er * er + 1e-6)),
            'r': float(np.sqrt(area / np.pi)),
            'cx': m['m10'] / m['m00'], 'cy': m['m01'] / m['m00'],
            'w': w, 'h': h,
            'border': x <= 1 or y <= 1 or x + w >= Ww - 2 or y + h >= Hh - 2,
            'mot': float(motion[y:y + h, x:x + w].mean()) if motion is not None else 0.0,
        })
    return out


def in_club_zone(b, lock_px, ball_r_px):
    """Backward ±60° cone from the lock, or the impact neighborhood itself
    (the head passes through the lock and a little beyond on follow-through)."""
    dx, dy = b['cx'] - lock_px[0], b['cy'] - lock_px[1]
    dist = math.hypot(dx, dy)
    if dist <= ball_r_px * 5:
        return True
    backward = dx * (-FLIGHT_DIR)   # +x side of the lock for a right-to-left flight
    if backward <= 0:
        return False
    ang = math.degrees(math.atan2(abs(dy), backward))
    return ang <= CONE_HALF_DEG


class ShotState:
    """Carries the golf priors across a shot's frames."""

    def __init__(self, lock_norm, size):
        self.W, self.H = size
        self.lock = (lock_norm[0] * self.W, lock_norm[1] * self.H)
        self.ball_r = max(4.0, lock_norm[2] * self.W / 2)
        self.progress = 0.0          # px along flight, monotone
        self.direction = None        # unit vector once flight is established
        self.ball_path = [self.lock]
        self.club_path = []
        self.last_pos = None         # last accepted flight position
        self.last_fi = None
        self.vel = None              # px/frame — constant over this short horizon
        self.exited = False          # projected off-screen: ball is gone, stays gone

    def pick_ball(self, cands, impacted, fi):
        if self.exited:
            return None
        # Exit projection: ball speed is constant over the few visible feet, so
        # last position + per-frame velocity × frames elapsed says where it must
        # be. Off-screen projection = the ball has left; anything round we find
        # after that is turf noise, not the ball.
        if self.vel is not None and self.last_fi is not None:
            px = self.last_pos[0] + self.vel[0] * (fi - self.last_fi)
            py = self.last_pos[1] + self.vel[1] * (fi - self.last_fi)
            m = self.ball_r
            if not (-m <= px <= self.W + m and -m <= py <= self.H + m):
                self.exited = True
                return None
        BALL_MIN_CIRC, BALL_MIN_AREA = 0.55, 15
        ok = [b for b in cands
              if 2.5 <= b['r'] <= 22 and b['circ'] >= BALL_MIN_CIRC
              and b['area'] >= BALL_MIN_AREA and not b['border']]
        if not impacted:
            near = [b for b in ok if math.hypot(b['cx'] - self.lock[0], b['cy'] - self.lock[1]) <= self.ball_r * 2.2]
            near.sort(key=lambda b: -b['circ'])
            return near[0] if near else None
        best, best_key = None, None
        for b in ok:
            vx, vy = b['cx'] - self.lock[0], b['cy'] - self.lock[1]
            dist = math.hypot(vx, vy)
            if dist < self.ball_r:            # still at the lock = not flight
                continue
            if vx * FLIGHT_DIR < 0:           # backwards = never the ball
                continue
            if dist < self.progress - self.ball_r:   # monotone forward only
                continue
            dev = 0.0
            if self.direction is not None:
                du = (vx / dist, vy / dist)
                dev = math.degrees(math.acos(max(-1, min(1, du[0] * self.direction[0] + du[1] * self.direction[1]))))
                if dev > 25:                  # one straight line, no curve yet
                    continue
            key = (dev, -b['circ'])
            if best is None or key < best_key:
                best, best_key = b, key
        if best is not None:
            vx, vy = best['cx'] - self.lock[0], best['cy'] - self.lock[1]
            dist = math.hypot(vx, vy)
            self.progress = max(self.progress, dist)
            if dist >= self.ball_r * 2:
                self.direction = (vx / dist, vy / dist)
            self.ball_path.append((best['cx'], best['cy']))
        return best

    def pick_club(self, bright_cands, dark_cands, diff_cands, ball=None):
        CLUB_AREA = (60, 3000)
        CLUB_MAX_ASPECT = 3.5
        CLUB_MIN_MOTION = 15.0

        def near_ball(b):
            return ball is not None and math.hypot(b['cx'] - ball['cx'], b['cy'] - ball['cy']) <= ball['r'] * 2

        def eligible(cands, max_aspect=CLUB_MAX_ASPECT, min_area=CLUB_AREA[0]):
            return [b for b in cands
                    if not b['border']
                    and min_area <= b['area'] <= CLUB_AREA[1]
                    and max(b['w'], b['h']) / max(1, min(b['w'], b['h'])) <= max_aspect
                    and b['mot'] >= CLUB_MIN_MOTION
                    and in_club_zone(b, self.lock, self.ball_r)
                    and not near_ball(b)]

        pool, source = eligible(bright_cands), 'bright'
        if not pool:
            pool, source = eligible(dark_cands), 'dark'
        if not pool:
            # Frame-differencing pass: at 240fps a fast club is a FAINT STREAK the
            # static masks miss entirely. The streak is elongated by nature, so the
            # aspect cap comes off; area floor drops (thin line = few pixels).
            pool, source = eligible(diff_cands, max_aspect=99.0, min_area=30), 'diff'
        if not pool:
            return None, 'none'
        if self.club_path:
            px, py = self.club_path[-1]
            pool.sort(key=lambda b: (math.hypot(b['cx'] - px, b['cy'] - py), -b['mot']))
        else:
            pool.sort(key=lambda b: -b['mot'])
        c = pool[0]
        self.club_path.append((c['cx'], c['cy']))
        return c, source


def derive_impact(d, lock_px, ball_r, base_luma, hint, Ww, Hh):
    """IMPACT = the frame BEFORE the ball moves. Scan around the pipeline's hint
    for the first frame with a round candidate displaced >=1.5 ball radii
    forward of the lock; impact is the frame before it. Falls back to the hint
    when no movement is ever seen (ball never tracked leaving)."""
    for fi in range(max(0, hint - 8), hint + 10):
        p = frame_path(d, fi)
        if not os.path.exists(p):
            continue
        bgr = cv2.imread(p)
        dh, _ = hue_dist(bgr)
        motion = np.abs(bgr.mean(axis=2) - base_luma) if base_luma is not None else None
        mask = cv2.morphologyEx((dh >= 160).astype(np.uint8) * 255, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
        for b in blobs_from_mask(mask, motion):
            if not (2.5 <= b['r'] <= 22 and b['circ'] >= 0.55 and b['area'] >= 15 and not b['border']):
                continue
            vx = b['cx'] - lock_px[0]
            vy = b['cy'] - lock_px[1]
            if vx * FLIGHT_DIR <= 0:
                continue
            if math.hypot(vx, vy) >= ball_r * 1.5:
                return fi - 1, 'ball-motion'
    return hint, 'pipeline-hint'


def derive_lock(d, Ww, Hh, meta_lock):
    """The lock is the round blob that HOLDS STILL across the earliest frames —
    derived from the ball itself, because metadata locks are missing on older
    exports and padded/offset on others. Metadata is only a tie-breaker hint."""
    positions = []
    for fi in (0, 2, 4, 6, 8):
        p = frame_path(d, fi)
        if not os.path.exists(p):
            continue
        bgr = cv2.imread(p)
        dh, _ = hue_dist(bgr)
        mask = cv2.morphologyEx((dh >= 160).astype(np.uint8) * 255, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
        cands = [b for b in blobs_from_mask(mask, None)
                 if 2.5 <= b['r'] <= 22 and b['circ'] >= 0.55 and b['area'] >= 15 and not b['border']]
        positions.append(cands)
    # find the candidate that recurs at (nearly) the same spot in >=3 frames
    best, best_n = None, 0
    for base_frame in positions:
        for b in base_frame:
            n = sum(1 for fr in positions
                    for c in fr if math.hypot(c['cx'] - b['cx'], c['cy'] - b['cy']) <= max(4, b['r']))
            if n > best_n:
                best, best_n = b, n
    if best is not None and best_n >= 3:
        return (best['cx'] / Ww, best['cy'] / Hh, max(0.02, 2 * best['r'] / Ww)), 'observed-rest-ball'
    if meta_lock:
        return (meta_lock['x'] + meta_lock['width'] / 2,
                meta_lock['y'] + meta_lock['height'] / 2,
                meta_lock['width']), 'metadata'
    return (0.64, 0.55, 0.05), 'default'


def render_shot(archive, shot, imp, pre, post):
    d = os.path.join(archive, shot)
    meta = json.load(open(os.path.join(d, 'metadata.json'))) if os.path.exists(os.path.join(d, 'metadata.json')) else {}
    first = cv2.imread(frame_path(d, 0))
    Hh, Ww = first.shape[:2]
    lock_norm, lock_src = derive_lock(d, Ww, Hh, meta.get('locked_ball_rect'))

    pres = []
    for i in range(0, max(3, imp - 2), 3):
        p = frame_path(d, i)
        if os.path.exists(p):
            pres.append(cv2.imread(p).mean(axis=2))
    base_luma = np.median(np.stack(pres), axis=0) if len(pres) >= 3 else None

    state = ShotState(lock_norm, (Ww, Hh))
    imp, imp_src = derive_impact(d, state.lock, state.ball_r, base_luma, imp, Ww, Hh)
    cells = []
    prev_luma = None
    for fi in range(imp - pre, imp + post + 1):
        p = frame_path(d, fi)
        if not os.path.exists(p):
            continue
        bgr = cv2.imread(p)
        dh, _ = hue_dist(bgr)
        luma = bgr.mean(axis=2)
        motion = np.abs(luma - base_luma) if base_luma is not None else None

        bright_mask = cv2.morphologyEx((dh >= 160).astype(np.uint8) * 255, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        bright_mask = cv2.morphologyEx(bright_mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
        bright = blobs_from_mask(bright_mask, motion)

        hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
        V, S = hsv[..., 2], hsv[..., 1]
        dark_mask = ((V <= 70) & (S <= 120)).astype(np.uint8) * 255
        if motion is not None:
            dark_mask[motion < 15] = 0
        dark_mask = cv2.morphologyEx(dark_mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        dark_mask = cv2.morphologyEx(dark_mask, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
        dark = blobs_from_mask(dark_mask, motion, min_area=50)

        # Consecutive-frame differencing: a fast club is a faint streak. Noise
        # filter: threshold adapts to the frame pair's own noise floor (global
        # exposure flicker raises the median; real streaks sit far above it).
        diff_cands = []
        if prev_luma is not None:
            fd = np.abs(luma - prev_luma)
            noise = float(np.median(fd))
            thr = max(18.0, noise * 4 + 10)
            diff_mask = (fd >= thr).astype(np.uint8) * 255
            diff_mask = cv2.morphologyEx(diff_mask, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
            diff_mask = cv2.morphologyEx(diff_mask, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
            diff_cands = blobs_from_mask(diff_mask, motion, min_area=30)
        prev_luma = luma

        # impact frame = last frame at rest, so flight logic starts the frame after
        ball = state.pick_ball(bright, impacted=(fi > imp), fi=fi)
        club, club_src = state.pick_club(bright, dark, diff_cands, ball=ball)

        out = cv2.cvtColor(dh, cv2.COLOR_GRAY2BGR)
        lx, ly = int(state.lock[0]), int(state.lock[1])
        # cone prior (faint): apex at lock, opening backward
        L = 130
        for sgn in (-1, 1):
            ex = lx + int(L * (-FLIGHT_DIR) * math.cos(math.radians(CONE_HALF_DEG)))
            ey = ly + sgn * int(L * math.sin(math.radians(CONE_HALF_DEG)))
            cv2.line(out, (lx, ly), (ex, ey), (60, 120, 120), 1)
        cv2.drawMarker(out, (lx, ly), (90, 200, 90), cv2.MARKER_TILTED_CROSS, 8, 1)
        if len(state.ball_path) >= 2:
            pts = np.array([(int(x), int(y)) for x, y in state.ball_path])
            cv2.polylines(out, [pts], False, (70, 70, 220), 1)
        if len(state.club_path) >= 2:
            pts = np.array([(int(x), int(y)) for x, y in state.club_path])
            cv2.polylines(out, [pts], False, (200, 200, 70), 1)
        if ball:
            cv2.circle(out, (int(ball['cx']), int(ball['cy'])), int(ball['r']) + 3, (60, 60, 255), 2)
        if club:
            pcl = (int(club['cx']), int(club['cy']))
            col = {'bright': (255, 220, 60), 'dark': (60, 160, 255), 'diff': (255, 80, 255)}.get(club_src, (255, 220, 60))
            cv2.circle(out, pcl, 4, col, -1)
            cv2.line(out, (pcl[0] - 9, pcl[1]), (pcl[0] + 9, pcl[1]), col, 1)
            cv2.line(out, (pcl[0], pcl[1] - 9), (pcl[0], pcl[1] + 9), col, 1)
        tag = f'f{fi}' + (' IMPACT' if fi == imp else '')
        cv2.rectangle(out, (0, 0), (12 + 9 * len(tag), 20), (0, 0, 0), -1)
        cv2.putText(out, tag, (5, 14), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (80, 235, 255), 1)
        cells.append(f'<div class="cell"><img src="data:image/jpeg;base64,{b64jpg(out)}"></div>')
    return cells, imp, imp_src, lock_src


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--archive', required=True)
    ap.add_argument('--replay', default=None)
    ap.add_argument('--shots', default=None)
    ap.add_argument('--auto', type=int, default=50)
    ap.add_argument('--pre', type=int, default=4)
    ap.add_argument('--post', type=int, default=7)
    ap.add_argument('--out', required=True)
    ap.add_argument('--open', action='store_true')
    a = ap.parse_args()

    shots = a.shots.split(',') if a.shots else pick_diverse(a.archive, a.auto)
    sections = []
    for shot in shots:
        hint, _ = impact_index(shot, a.archive, a.replay)
        cells, imp, imp_src, lock_src = render_shot(a.archive, shot, hint, a.pre, a.post)
        t = shot[5:]
        pretty = f'{t[4:6]}/{t[6:8]} {t[9:11]}:{t[11:13]}:{t[13:15]}'
        sections.append(
            f'<h2>{shot}</h2><p class="sub">captured {pretty} · impact f{imp} ({imp_src}, last frame before ball moves) · lock: {lock_src}</p>'
            f'<div class="strip">{"".join(cells)}</div>')

    html = f"""<title>Golf-Context Detector — hue-distance + physics priors, {len(shots)} shots</title>
<style>
:root {{ --bg:#111417; --panel:#1a1f24; --line:#2a3138; --text:#e8ebee; --mut:#98a2ab; }}
@media (prefers-color-scheme: light) {{ :root {{ --bg:#f2f4f6; --panel:#fff; --line:#d9dee3; --text:#1a2026; --mut:#5b6570; }} }}
:root[data-theme="dark"] {{ --bg:#111417; --panel:#1a1f24; --line:#2a3138; --text:#e8ebee; --mut:#98a2ab; }}
:root[data-theme="light"] {{ --bg:#f2f4f6; --panel:#fff; --line:#d9dee3; --text:#1a2026; --mut:#5b6570; }}
body {{ background:var(--bg); color:var(--text); font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; margin:0; padding:28px 18px 70px; }}
main {{ max-width:1280px; margin:0 auto; }}
h1 {{ font-size:24px; margin:0 0 2px; }}
h2 {{ font-size:14px; font-family:ui-monospace,Menlo,monospace; margin:30px 0 2px; }}
.sub {{ color:var(--mut); font-size:12px; margin:0 0 6px; }}
.legend {{ color:var(--mut); font-size:13.5px; margin:6px 0 10px; max-width:110ch; }}
.strip {{ display:flex; gap:6px; overflow-x:auto; padding:8px; background:var(--panel); border:1px solid var(--line); border-radius:8px; }}
.cell img {{ height:200px; display:block; border-radius:4px; }}
</style>
<main>
<h1>Golf-Context Detector</h1>
<p class="legend">Hue-distance channel + golf priors. <b style="color:#7fbf7f">Green ✕</b> = lock, derived from the ball itself (the round blob holding still in the earliest frames — metadata only breaks ties), with the faint ±60° club-approach cone behind it · <b style="color:#e05252">red circle</b> = ball, monotone forward along one line from the lock (red polyline = path) · club crosshair by pass: <b style="color:#e0c93f">yellow</b> = bright mask, <b style="color:#ffa03f">orange</b> = dark second pass (black crowns/wedges), <b style="color:#f050f0">magenta</b> = frame-differencing third pass (faint streak clubs); yellow polyline = club path. IMPACT is re-derived as the last frame before the ball moves. Once last-position + per-frame velocity projects the ball off-screen, ball detection stops for the shot. No marker = nothing passed the cutoffs.</p>
{''.join(sections)}
</main>"""
    with open(a.out, 'w') as f:
        f.write(html)
    print(f'wrote {a.out} ({os.path.getsize(a.out)//1024} KB, {len(shots)} shots)')
    if a.open:
        os.system(f'open "{a.out}"')


if __name__ == '__main__':
    main()
