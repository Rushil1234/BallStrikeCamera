#!/usr/bin/env python3
"""Hosel-point club speed from Noah's hand labels vs TT/Garmin truth.

Noah's July 19 hosel round: the shaft-head junction labeled on club-window
frames (impact-3..+1). Question: does hosel displacement beat the shipped
smash-factor path (2.4 mph median vs TT) or the calibrated centroid (~9.4%
post-cal)?

Speed estimators per shot (hosel points sorted by frame, t from
timestamps.json, px->m via rest-ball radius = 21.335 mm):
  impact : last interval ending at frame <= impact+1  (what TT/Garmin report)
  mean   : mean of all intervals ending <= impact+1
  peak   : max interval

Truth: jul17 pairs.json toptracer.club_mph (51) · jul16 pairs tt_shot ->
swingsync clubSpeed (89) · jul12 pairs garmin_idx -> garmin_main.csv Club
Speed (Garmin radar; whites, no TT). Smash baseline recomputed on the same
shots where the TT club name exists.
"""
import csv, json, math, os

TRAIN = os.path.expanduser('~/Documents/TrueCarryTraining')
REPO = '/Users/noahtobias/Downloads/BallStrikeCamera'
ARCHIVE = os.path.join(TRAIN, 'hosel_archive')
MM_PER_BALL_R = 21.335

labels = json.load(open(os.path.join(TRAIN, 'labels/labels.json')))
prelabels = json.load(open(os.path.join(TRAIN, 'labels/prelabels.json')))
smash_tbl = json.load(open(os.path.join(
    REPO, 'BallStrikeCamera/Resources/Models/v3_heads.json'))).get('smash_by_club', {})

try:
    EXCLUDED = set(json.load(open(os.path.join(TRAIN, 'session_2026-07-17/excluded_shots.json'))))
except FileNotFoundError:
    EXCLUDED = set()


def norm_club(name):
    if not name:
        return None
    k = str(name).strip().lower().replace(' ', '_').replace('-', '_')
    alias = {'pw': 'pitching_wedge', 'sw': 'sand_wedge', 'gw': 'gap_wedge',
             'lw': 'lob_wedge', 'dr': 'driver'}
    k = alias.get(k, k)
    return k if k in smash_tbl else None


def load_truth():
    """shot -> {'tt': mph|None, 'garmin': mph|None, 'tt_ball': mph|None, 'club': str|None}"""
    out = {}
    p17 = json.load(open(os.path.join(TRAIN, 'session_2026-07-17/pairs.json')))
    for p in p17:
        tt, gm = p.get('toptracer') or {}, p.get('garmin') or {}
        out[p['shot']] = {'tt': tt.get('club_mph'), 'garmin': gm.get('club_mph'),
                          'tt_ball': tt.get('ball_mph'), 'club': tt.get('club')}
    ss16 = {}
    with open(os.path.expanduser('~/Downloads/swingsync-2026-07-16.csv')) as f:
        for row in csv.DictReader(f):
            try:
                ss16[int(row['shotNumber'])] = (float(row['clubSpeed']), row.get('type'))
            except (ValueError, KeyError):
                pass
    for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-16/pairs.json'))):
        cs = ss16.get(p.get('tt_shot'))
        out[p['shot']] = {'tt': cs[0] if cs else None, 'garmin': None,
                          'tt_ball': p.get('tt_ball_mph'),
                          'club': (cs[1] if cs else None) or p.get('club')}
    g12 = []
    with open(os.path.join(TRAIN, 'session_2026-07-12/garmin_main.csv')) as f:
        for row in csv.DictReader(f):
            try:
                g12.append(float(row['Club Speed']))
            except (ValueError, KeyError):
                g12.append(None)
    for p in json.load(open(os.path.join(TRAIN, 'session_2026-07-12/pairs.json'))):
        gi = p.get('garmin_idx')
        cs = g12[gi] if gi is not None and gi < len(g12) else None
        out[p['shot']] = {'tt': None, 'garmin': cs, 'tt_ball': None, 'club': None}
    return out


def rest_radius(shot, labs):
    balls = sorted((int(f), e['ball']) for f, e in labs.items()
                   if isinstance(e, dict) and e.get('reviewed') and e.get('ball'))
    pl = prelabels.get(shot) or {}
    imp = pl.get('impact', 999)
    pre = [b for f, b in balls if f <= imp and b.get('r')]
    if pre:
        return max(3.0, pre[0]['r'])
    for f in sorted(pl.get('per_frame', {}), key=int):
        b = pl['per_frame'][f].get('ball')
        if b and b.get('r'):
            return max(3.0, b['r'])
    return None


def hosel_speeds(shot, labs):
    d = os.path.join(ARCHIVE, shot)
    pl = prelabels.get(shot)
    if pl is None or not os.path.isdir(d):
        return None
    imp = pl['impact']
    hs = sorted((int(f), e['hosel']) for f, e in labs.items()
                if isinstance(e, dict) and e.get('reviewed') and e.get('hosel'))
    if len(hs) < 2:
        return None
    ts = {}
    tp = os.path.join(d, 'timestamps.json')
    if os.path.exists(tp):
        ts = {e['frame_index']: e['timestamp']
              for e in json.load(open(tp)).get('timestamps', [])}
    r0 = rest_radius(shot, labs)
    if r0 is None:
        return None
    scale = (MM_PER_BALL_R / 1000.0 / r0) * 2.23694   # px/s -> mph
    ivals = []
    for (fa, a), (fb, b) in zip(hs, hs[1:]):
        if fb - fa > 3 or fb > imp + 1:
            continue
        ta, tb = ts.get(fa, fa / 240.0), ts.get(fb, fb / 240.0)
        if tb - ta <= 0:
            continue
        vpx = math.hypot(b['cx'] - a['cx'], b['cy'] - a['cy']) / (tb - ta)
        ivals.append((fb, vpx * scale))
    if not ivals:
        return None
    used = [h for h in hs if h[0] <= imp + 1]
    dx_net = (used[-1][1]['cx'] - used[0][1]['cx']) if len(used) >= 2 else 0.0
    return {'impact': ivals[-1][1],
            'mean': sum(v for _, v in ivals) / len(ivals),
            'peak': max(v for _, v in ivals),
            'dx_net': dx_net,
            'n': len(ivals)}


def med(a):
    s = sorted(a)
    n = len(s)
    return float('nan') if not n else (s[n // 2] if n % 2 else 0.5 * (s[n//2-1] + s[n//2]))


def report(name, pred_truth):
    """pred_truth: list of (pred, truth). Print bias, post-cal % + mph medians."""
    if len(pred_truth) < 5:
        print(f'  {name:<8} n={len(pred_truth)} (too few)')
        return
    ratios = [p / t for p, t in pred_truth]
    k = med(ratios)                       # single global scale calibration
    pct = [abs(p / k - t) / t * 100 for p, t in pred_truth]
    mph = [abs(p / k - t) for p, t in pred_truth]
    raw = [abs(p - t) for p, t in pred_truth]
    print(f'  {name:<8} n={len(pred_truth):3d}  scale k={k:.3f}  raw med {med(raw):5.1f} mph'
          f'  POST-CAL med {med(mph):4.1f} mph ({med(pct):4.1f}%)'
          f'  p90 {sorted(mph)[int(0.9*len(mph))]:5.1f} mph')


def main():
    truth = load_truth()
    est = {}
    for shot, labs in sorted(labels.items()):
        if shot in EXCLUDED:
            continue
        r = hosel_speeds(shot, labs)
        if r:
            est[shot] = r
    # Junk gates (Noah: these shots wouldn't register in the sim and must not
    # train the detector). Written as {shot: reason} for the YOLO export.
    #   static    peak hosel speed < 30 mph — labels sat on stationary clutter
    #   backwards hosel's net x-displacement isn't forward (play is right-to-
    #             left, so forward = decreasing x)
    #   no_club   shot has zero reviewed club/hosel frames anywhere
    junk = {}
    for s, r in est.items():
        if r['peak'] < 30.0:
            junk[s] = 'static'
        elif r['dx_net'] >= 0:
            junk[s] = 'backwards'
    for shot, labs in labels.items():
        has_club = any(isinstance(e, dict) and e.get('reviewed')
                       and (e.get('club') or e.get('hosel')) for e in labs.values())
        if not has_club:
            junk[shot] = 'no_club'
    json.dump(junk, open(os.path.join(TRAIN, 'hosel_junk_shots.json'), 'w'), indent=1)
    est = {s: r for s, r in est.items() if s not in junk}
    from collections import Counter
    print(f'hosel speed estimates: {len(est)} shots · junk excluded: '
          f'{dict(Counter(junk.values()))} -> hosel_junk_shots.json')

    sets = (('vs TOPTRACER (jul16+17)', 'tt', None),
            ('vs TOPTRACER (jul17 range ONLY — TT+Garmin session)', 'tt', 'shot_20260717'),
            ('vs GARMIN (jul12 whites)', 'garmin', None))
    for tname, key, prefix in sets:
        print(f'\n{tname}')
        for variant in ('impact', 'mean', 'peak'):
            pt = [(est[s][variant], truth[s][key]) for s in est
                  if s in truth and truth[s].get(key)
                  and (prefix is None or s.startswith(prefix))]
            report(variant, pt)

    # smash baseline on the same TT shots (needs TT ball + club name in table)
    pt_smash, pt_hosel = [], []
    for s in est:
        t = truth.get(s) or {}
        ck = norm_club(t.get('club'))
        if t.get('tt') and t.get('tt_ball') and ck:
            pt_smash.append((t['tt_ball'] / smash_tbl[ck], t['tt']))
            pt_hosel.append((est[s]['mean'], t['tt']))   # mean = best variant
    print('\nsame-shot comparison (TT truth, shots with club name in smash table)')
    report('smash', pt_smash)
    report('hosel', pt_hosel)

    out = {s: {**est[s], 'tt': (truth.get(s) or {}).get('tt'),
               'garmin': (truth.get(s) or {}).get('garmin')} for s in est}
    op = os.path.join(TRAIN, 'hosel_speed_results.json')
    json.dump(out, open(op, 'w'), indent=1)
    print(f'\nper-shot results -> {op}')


if __name__ == '__main__':
    main()
