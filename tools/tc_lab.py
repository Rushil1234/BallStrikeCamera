#!/usr/bin/env python3
"""tc_lab — the TrueCarry accuracy lab. One command per phase:

  ingest   unzip/copy a session's frame archive, filter by date window,
           auto-align TopTracer + Garmin truth (speed-DP with skips, the
           only alignment that survives missed captures), write session dir
  replay   stage archives into the simulator, run the headless live-parity
           replay, collect results (handles container rotation, app exit,
           stalls — every ops lesson from July 17/18 baked in)
  score    one report: flight%% vs labels per suite, every metric vs the
           target table, sorted worst-shot list for the viewer
  train    retrain color heads on ALL Swift-feature dumps + TT-normalized
           targets, merge bundle, rebuild the app

Typical day-after-range:
  python3 tools/tc_lab.py ingest  --zip ~/Downloads/TrueCarryFrames_X.zip \
      --tt ~/Downloads/swingsync-DATE.csv --garmin ~/Downloads/garmin.csv \
      --session 2026-07-19 --after 08:00
  python3 tools/tc_lab.py replay --archives 2026-07-19
  python3 tools/tc_lab.py score  --session 2026-07-19
  python3 tools/tc_lab.py train && python3 tools/tc_lab.py replay --archives all
"""
import argparse, csv, datetime, glob, json, math, os, re, shutil, subprocess, sys, time

UDID = '43599AB4-284E-4087-89A6-D25FB8B50E23'
def _bundle_id():
    # Rushil's July-19 commits changed PRODUCT_BUNDLE_IDENTIFIER (com.noahtobias ->
    # com.rushilkakkad1) and every simctl call here silently targeted a stale
    # install. Read it from the pbxproj so replays always hit the built app.
    try:
        s = open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                              'BallStrikeCamera.xcodeproj/project.pbxproj')).read()
        m = re.search(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', s)
        if m:
            return m.group(1).strip()
    except OSError:
        pass
    return 'com.noahtobias.BallStrikeCamera'


BUNDLE = _bundle_id()
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRAIN = os.path.expanduser('~/Documents/TrueCarryTraining')
ARCHIVE_ROOT = os.path.expanduser('~/Documents')
TARGETS = {'speed_pct': 2.0, 'vla_deg': 1.0, 'club_mph': 3.0,
           'backspin_rpm': 1000.0, 'sidespin_rpm': 200.0,
           'carry_yd': 2.0, 'total_yd': 4.0}


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True,
                          text=True, **kw)


def container():
    return sh(['xcrun', 'simctl', 'get_app_container', UDID, BUNDLE, 'data']).stdout.strip()


# ── ingest ────────────────────────────────────────────────────────────────────

def load_tt(path):
    rows = []
    for r in csv.DictReader(open(path)):
        def fv(k):
            try:
                v = float(r.get(k, ''))
                return None if v == -10000 else v
            except (TypeError, ValueError):
                return None
        try:
            num = int(r['shotNumber'])
        except (ValueError, KeyError):
            continue
        rows.append(dict(num=num, ball_mph=fv('ballSpeed'), club_mph=fv('clubSpeed'),
                         launch=fv('launchAngle'), carry=fv('carry'), total=fv('total'),
                         backspin=fv('backSpin'), sidespin=fv('sideSpin'),
                         push_pull=fv('pushPull'), peak=fv('peakHeight'),
                         smash=fv('smashFactor'), descent=fv('decentAngle'),
                         club=(r.get('type') or r.get('clubName') or '?')))
    rows.sort(key=lambda x: x['num'])
    return rows


def load_garmin(path):
    rows = []
    for r in csv.DictReader(open(path)):
        date = r.get('﻿Date') or r.get('Date')
        if not date or '/' not in date:
            continue
        def fv(k):
            try:
                return float(r[k])
            except (ValueError, KeyError, TypeError):
                return None
        if fv('Ball Speed') is None:
            continue
        t = datetime.datetime.strptime(date, '%m/%d/%y %I:%M:%S %p')
        rows.append(dict(time=t.isoformat(), ball_mph=fv('Ball Speed'),
                         club_mph=fv('Club Speed'), launch=fv('Launch Angle'),
                         launch_dir=fv('Launch Direction'), backspin=fv('Backspin'),
                         spin=fv('Spin Rate'), club_path=fv('Club Path'),
                         club_face=fv('Club Face'), attack=fv('Attack Angle'),
                         smash=fv('Smash Factor'), carry=fv('Carry Distance'),
                         total=fv('Total Distance')))
    rows.sort(key=lambda g: g['time'])
    return rows


def dp_align(seq_a, seq_b, cost_fn, skip_a=1.2, skip_b=0.35):
    """Monotonic one-to-one alignment with skips on both sides. Returns {i_a: i_b}.
    THE alignment lesson of July 17: greedy matching without skips shifts whole
    stretches when one side misses an event (TT logs every swing; we don't)."""
    INF = float('inf')
    n, m = len(seq_a), len(seq_b)
    D = [[INF] * (m + 1) for _ in range(n + 1)]
    P = [[None] * (m + 1) for _ in range(n + 1)]
    D[0][0] = 0
    for i in range(n + 1):
        for j in range(m + 1):
            if D[i][j] == INF:
                continue
            if i < n and j < m and D[i][j] + cost_fn(seq_a[i], seq_b[j]) < D[i + 1][j + 1]:
                D[i + 1][j + 1] = D[i][j] + cost_fn(seq_a[i], seq_b[j])
                P[i + 1][j + 1] = ('M', i, j)
            if i < n and D[i][j] + skip_a < D[i + 1][j]:
                D[i + 1][j] = D[i][j] + skip_a
                P[i + 1][j] = ('A', i, j)
            if j < m and D[i][j] + skip_b < D[i][j + 1]:
                D[i][j + 1] = D[i][j] + skip_b
                P[i][j + 1] = ('B', i, j)
    match = {}
    i, j = n, m
    while (i > 0 or j > 0) and P[i][j]:
        k, pi, pj = P[i][j]
        if k == 'M':
            match[pi] = pj
        i, j = pi, pj
    return match


def cmd_ingest(a):
    sess_dir = os.path.join(TRAIN, f'session_{a.session}')
    os.makedirs(sess_dir, exist_ok=True)
    day = a.session.replace('-', '')
    arch_root = os.path.join(ARCHIVE_ROOT, f'TrueCarryFramesArchive_{day}')
    arch = os.path.join(arch_root, 'AllFramesArchive')
    os.makedirs(arch, exist_ok=True)

    if a.zip:
        tmp = os.path.join(sess_dir, '_unzip')
        shutil.rmtree(tmp, ignore_errors=True)
        sh(['unzip', '-q', os.path.expanduser(a.zip), '-d', tmp])
        n_in = n_kept = 0
        for d in sorted(glob.glob(tmp + '/**/shot_*', recursive=True)):
            if not os.path.isdir(d):
                continue
            n_in += 1
            name = os.path.basename(d)
            hhmm = name[14:16] + ':' + name[16:18]
            if name[5:13] == day and (not a.after or hhmm >= a.after) \
               and (not a.before or hhmm <= a.before):
                shutil.move(d, os.path.join(arch, name))
                n_kept += 1
        shutil.rmtree(tmp, ignore_errors=True)
        print(f'ingest: {n_kept}/{n_in} shot folders -> {arch}')

    shots = sorted(d for d in os.listdir(arch) if d.startswith('shot_'))
    tc = [dict(shot=s) for s in shots]

    tt = load_tt(os.path.expanduser(a.tt)) if a.tt else []
    gm = load_garmin(os.path.expanduser(a.garmin)) if a.garmin else []
    if a.tt:
        shutil.copy(os.path.expanduser(a.tt), sess_dir)
    if a.garmin:
        shutil.copy(os.path.expanduser(a.garmin), os.path.join(sess_dir, 'garmin.csv'))

    # TC<->TT: needs our replay speeds — first-pass alignment uses folder time order
    # vs TT order with a neutral cost; refined automatically after the first replay
    # by `score --realign`. TT<->Garmin aligns now by speed (both are truth).
    pairs = []
    g_of_tt = {}
    if tt and gm:
        g_of_tt = dp_align(gm, tt, lambda g, t: min(abs(g['ball_mph'] - t['ball_mph'])
                                                    / t['ball_mph'], 1.5),
                           skip_a=0.5, skip_b=0.35)
        agree = [abs(gm[i]['ball_mph'] - tt[j]['ball_mph']) / tt[j]['ball_mph'] * 100
                 for i, j in g_of_tt.items()]
        agree.sort()
        print(f'TT<->Garmin: {len(g_of_tt)} matched, median agreement '
              f'{agree[len(agree) // 2]:.2f}%')
    tt_of_g = {j: i for i, j in g_of_tt.items()}
    for i, t in enumerate(tt):
        entry = {'shot': None, 'toptracer': t, 'club': t['club']}
        if i in tt_of_g:
            entry['garmin'] = gm[tt_of_g[i]]
        pairs.append(entry)
    json.dump(pairs, open(os.path.join(sess_dir, 'pairs_unbound.json'), 'w'), indent=1)
    json.dump([t['shot'] for t in tc], open(os.path.join(sess_dir, 'tc_shots.json'), 'w'),
              indent=1)
    print(f'wrote {sess_dir}/pairs_unbound.json ({len(pairs)} truth rows, '
          f'{len(tc)} TC shots) — run replay, then `score --realign` to bind')


# ── replay ────────────────────────────────────────────────────────────────────

def cmd_replay(a):
    archives = []
    if a.archives == 'all':
        archives = sorted(glob.glob(os.path.join(ARCHIVE_ROOT,
                                                 'TrueCarryFramesArchive_*/AllFramesArchive')))
    else:
        for tag in a.archives.split(','):
            day = tag.replace('-', '')
            archives.append(os.path.join(ARCHIVE_ROOT,
                                         f'TrueCarryFramesArchive_{day}/AllFramesArchive'))
    if a.build:
        r = sh(f'cd {REPO} && xcodebuild -project BallStrikeCamera.xcodeproj '
               f'-scheme BallStrikeCamera -sdk iphonesimulator '
               f"-destination 'platform=iOS Simulator,id={UDID}' "
               f'-derivedDataPath build_replay build')
        if 'BUILD SUCCEEDED' not in r.stdout:
            sys.exit('BUILD FAILED:\n' + '\n'.join(
                l for l in r.stdout.splitlines() if 'error:' in l)[:2000])
        print('build OK')

    sh(f'pkill -9 -f "{BUNDLE}"')
    sh(['xcrun', 'simctl', 'bootstatus', UDID, '-b'])
    app = os.path.join(REPO, 'build_replay/Build/Products/Debug-iphonesimulator/BallStrikeCamera.app')
    sh(['xcrun', 'simctl', 'install', UDID, app])
    cont = container()                      # resolve AFTER install — UUID rotates
    res = os.path.join(cont, 'Documents/ReplayResults')
    stage = os.path.join(cont, 'Documents/AllFramesArchive')
    shutil.rmtree(res, ignore_errors=True)
    shutil.rmtree(stage, ignore_errors=True)
    os.makedirs(stage)
    total = 0
    for arch in archives:
        for d in sorted(glob.glob(arch + '/shot_*')):
            shutil.copytree(d, os.path.join(stage, os.path.basename(d)))
            total += 1
    print(f'staged {total} shots')
    env = os.environ.copy()
    env['SIMCTL_CHILD_TC_REPLAY_EXPORTS'] = '1'
    subprocess.run(['xcrun', 'simctl', 'launch', UDID, BUNDLE], env=env)
    time.sleep(20)
    cont2 = container()                     # verify no post-launch rotation
    if cont2 != cont:
        print(f'container rotated post-launch -> {cont2}')
        cont, res = cont2, os.path.join(cont2, 'Documents/ReplayResults')
    prev, same = -1, 0
    while True:
        n = len(glob.glob(res + '/shot_*.json'))
        alive = 'BallStrikeCamera.app' in sh('ps aux').stdout
        if n >= total:
            break
        if not alive and n < total:
            print(f'app exited at {n}/{total}')
            break
        same = same + 1 if n == prev else 0
        if same >= 12:
            print(f'stalled at {n}/{total}')
            break
        prev = n
        print(f'\r{n}/{total}', end='', flush=True)
        time.sleep(20)
    out = os.path.join(TRAIN, 'replays', 'latest')
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    for f in glob.glob(res + '/shot_*.json'):
        shutil.copy(f, out)
    print(f'\ncollected {len(glob.glob(out + "/*.json"))} results -> {out}')


# ── score ─────────────────────────────────────────────────────────────────────

def _median(v):
    s = sorted(v)
    return s[len(s) // 2] if s else None


def cmd_score(a):
    sess_dir = os.path.join(TRAIN, f'session_{a.session}')
    res_dir = a.results or os.path.join(TRAIN, 'replays', 'latest')
    day = a.session.replace('-', '')
    results = {}
    for f in glob.glob(res_dir + f'/shot_{day}*.json'):
        results[os.path.basename(f)[:-5]] = json.load(open(f))
    print(f'{len(results)} results for session {a.session}')

    pairs_p = os.path.join(sess_dir, 'pairs.json')
    unbound_p = os.path.join(sess_dir, 'pairs_unbound.json')
    if a.realign or not os.path.exists(pairs_p):
        rows = json.load(open(unbound_p))
        tt_rows = [r['toptracer'] for r in rows]
        tc = sorted(results)
        tc_speeds = [(results[s].get('metrics') or {}).get('ballSpeedMph') for s in tc]
        def cost(s_ours, t):
            if not s_ours:
                return 2.0
            return min(abs(s_ours - t['ball_mph']) / t['ball_mph'], 1.5)
        match = dp_align(tc_speeds, tt_rows, cost)
        pairs = []
        for i, j in sorted(match.items()):
            e = dict(rows[j])
            e['shot'] = tc[i]
            pairs.append(e)
        json.dump(pairs, open(pairs_p, 'w'), indent=1)
        print(f'realigned: {len(pairs)}/{len(tc)} TC shots bound to truth')
    pairs = {p['shot']: p for p in json.load(open(pairs_p)) if p.get('shot')}

    excl_p = os.path.join(sess_dir, 'excluded_shots.json')
    excluded = set(json.load(open(excl_p))) if os.path.exists(excl_p) else set()

    per_metric = {k: [] for k in TARGETS}
    outliers = []
    for sid, d in sorted(results.items()):
        if sid in excluded:
            continue
        m = d.get('metrics') or {}
        p = pairs.get(sid)
        tt = (p or {}).get('toptracer') or {}
        row = {}
        if m.get('ballSpeedMph') and tt.get('ball_mph'):
            row['speed_pct'] = abs(m['ballSpeedMph'] - tt['ball_mph']) / tt['ball_mph'] * 100
        if m.get('vlaDegrees') is not None and tt.get('launch') is not None:
            row['vla_deg'] = abs(m['vlaDegrees'] - tt['launch'])
        if m.get('clubSpeedMph') and tt.get('club_mph'):
            row['club_mph'] = abs(m['clubSpeedMph'] - tt['club_mph'])
        if m.get('carryYards') and tt.get('carry'):
            row['carry_yd'] = abs(m['carryYards'] - tt['carry'])
        if m.get('totalYards') and tt.get('total'):
            row['total_yd'] = abs(m['totalYards'] - tt['total'])
        for k, v in row.items():
            per_metric[k].append(v)
        if row.get('speed_pct', 0) > 8 or row.get('vla_deg', 0) > 4:
            outliers.append((sid, row))

    print(f'\n{"metric":<14}{"median":>9}{"target":>9}{"n":>5}   verdict')
    for k, tgt in TARGETS.items():
        vals = per_metric.get(k, [])
        med = _median(vals)
        if med is None:
            print(f'{k:<14}{"—":>9}{tgt:>9}{0:>5}   (no data)')
            continue
        unit = '%' if k.endswith('pct') else ''
        ok = '✓' if med <= tgt else f'gap {med - tgt:.1f}'
        print(f'{k:<14}{med:>8.1f}{unit}{tgt:>9}{len(vals):>5}   {ok}')
    if outliers:
        print(f'\nworst shots ({len(outliers)}):')
        for sid, row in sorted(outliers, key=lambda x: -x[1].get('speed_pct', 0))[:10]:
            print('  ', sid, {k: round(v, 1) for k, v in row.items()})


# ── train ─────────────────────────────────────────────────────────────────────

def cmd_train(a):
    print('training heads on all Swift-feature dumps (yellow: TT, white: TT-normalized Garmin)…')
    r = sh(f'/opt/homebrew/bin/python3.11 {REPO}/tools/experimental/retrain_on_swift_feats.py')
    print(r.stdout.strip() or r.stderr.strip()[:400])
    r = sh(f'/opt/homebrew/bin/python3.11 {REPO}/tools/experimental/train_white_heads.py')
    print(r.stdout.strip() or r.stderr.strip()[:400])
    print('heads merged — run `replay --build` to validate the new bundle')


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('ingest')
    p.add_argument('--zip')
    p.add_argument('--tt')
    p.add_argument('--garmin')
    p.add_argument('--session', required=True)
    p.add_argument('--after')
    p.add_argument('--before')
    p = sub.add_parser('replay')
    p.add_argument('--archives', required=True, help='comma-separated dates or "all"')
    p.add_argument('--build', action='store_true')
    p = sub.add_parser('score')
    p.add_argument('--session', required=True)
    p.add_argument('--results')
    p.add_argument('--realign', action='store_true')
    p = sub.add_parser('train')
    a = ap.parse_args()
    {'ingest': cmd_ingest, 'replay': cmd_replay,
     'score': cmd_score, 'train': cmd_train}[a.cmd](a)


if __name__ == '__main__':
    main()
