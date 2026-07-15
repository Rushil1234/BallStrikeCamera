#!/usr/bin/env python3
"""Per-shot Garmin vs TrueCarry comparison table (HTML).

Ball speed: out-of-fold ridge predictions (each shot scored by a model that
never saw it). Club speed: raw physics scale (ball-diameter meters-per-pixel,
arc fit at contact) — no learned head yet, shown as measured. Launch direction
shown for reference only (relative measure, phone-angle dependent).
"""
import json, math, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import metrics_kfold as MK

SESSION = os.path.expanduser('~/Documents/TrueCarryTraining/session_2026-07-12')
BALL_M = 0.04267


def oof_predictions(X, y, clubs, k=5, alpha=1.0, seed=0):
    rng = np.random.default_rng(seed)
    idx = np.arange(len(y))
    folds = [[] for _ in range(k)]
    for ct in sorted(set(clubs)):
        sub = idx[np.array(clubs) == ct]
        rng.shuffle(sub)
        for i, j in enumerate(sub):
            folds[i % k].append(j)
    pred = np.zeros(len(y))
    for f in folds:
        te = np.array(sorted(f))
        tr = np.array(sorted(set(idx) - set(f)))
        mu, sd = X[tr].mean(0), X[tr].std(0) + 1e-9
        A = ((X[tr]-mu)/sd).T @ ((X[tr]-mu)/sd) + alpha * np.eye(X.shape[1])
        w = np.linalg.solve(A, ((X[tr]-mu)/sd).T @ (y[tr] - y[tr].mean()))
        pred[te] = ((X[te]-mu)/sd) @ w + y[tr].mean()
    return pred


def dcls(rel):
    if rel is None:
        return ''
    return 'g' if rel <= 2 else ('y' if rel <= 5 else 'r')


def main():
    rows = MK.build_rows()
    pairs = {p['shot']: p for p in json.load(open(os.path.join(SESSION, 'pairs.json'))) if p.get('shot')}

    X, y, keep = MK.xmat(rows, 'detector')
    clubs = [r['club_type'] for r in keep]
    pred = oof_predictions(X, y, clubs)
    # physics band: the model may refine the measurement, never contradict it
    _i = MK.FEATS.index('v2pt_phys')
    _vp = X[:, _i] * 2.23694
    pred = np.clip(pred, 0.7 * _vp, 1.4 * _vp)
    pred_by_shot = {r['shot']: p for r, p in zip(keep, pred)}

    # VLA head: same club-agnostic features -> Garmin Launch Angle (degrees)
    import csv as _csv
    from datetime import datetime as _dt
    _gv = {}
    _pairs_l = json.load(open(os.path.join(SESSION, 'pairs.json')))
    _pmap = {q['shot']: q for q in _pairs_l if q.get('shot')}
    for name in ('garmin_main.csv', 'garmin_small.csv'):
        with open(os.path.join(SESSION, name), encoding='utf-8-sig') as f:
            for row in _csv.DictReader(f):
                d = (row.get('Date') or '').strip()
                if d and row.get('Launch Angle'):
                    _gv[d] = float(row['Launch Angle'])
    def _gk(q):
        return _dt.fromisoformat(q['garmin_time']).strftime('%-m/%-d/%y %-I:%M:%S %p')
    yv, keep_v, Xv = [], [], []
    for r, x in zip(keep, X):
        q = _pmap.get(r['shot'])
        g = _gv.get(_gk(q)) if q else None
        if g is not None:
            yv.append(g); keep_v.append(r); Xv.append(x)
    Xv, yv = np.array(Xv), np.array(yv)
    # STACKED: append the OOF ball-speed prediction as a feature (train-upwards)
    ball_feat = np.array([[pred_by_shot.get(r['shot'], float(np.median(y)))] for r in keep_v])
    Xv = np.hstack([Xv, ball_feat])
    vpred = oof_predictions(Xv, yv, [r['club_type'] for r in keep_v])
    vla_by_shot = {r['shot']: (float(p), float(g)) for r, p, g in zip(keep_v, vpred, yv)}
    verr = np.abs(vpred - yv)
    print(f'VLA head (stacked, OOF): median abs err {np.median(verr):.1f}°  ≤2°: {(verr<=2).sum()}/{len(verr)}  ≤4°: {(verr<=4).sum()}/{len(verr)}')

    # STACKED club-speed head: physics measurement + OOF ball prediction → Garmin club
    _gc = {}
    for name in ('garmin_main.csv', 'garmin_small.csv'):
        with open(os.path.join(SESSION, name), encoding='utf-8-sig') as f:
            for row in _csv.DictReader(f):
                d = (row.get('Date') or '').strip()
                if d and row.get('Club Speed'):
                    _gc[d] = float(row['Club Speed'])
    Xc, yc, keep_c = [], [], []
    for r, x in zip(keep, X):
        q = _pmap.get(r['shot'])
        g = _gc.get(_gk(q)) if q else None
        f = r['detector']
        if g is not None and f and f.get('club_v'):
            Xc.append(list(x) + [pred_by_shot.get(r['shot'], float(np.median(y)))])
            yc.append(g); keep_c.append(r)
    club_pred_by_shot = {}
    if len(yc) >= 15:
        Xc, yc_a = np.array(Xc), np.array(yc)
        cpred = oof_predictions(Xc, yc_a, [r['club_type'] for r in keep_c])
        club_pred_by_shot = {r['shot']: float(p) for r, p in zip(keep_c, cpred)}
        cerr = np.abs(cpred - yc_a) / yc_a * 100
        print(f'club-speed head (stacked, OOF): n={len(yc)} median {np.median(cerr):.1f}%  ≤5%: {(cerr<=5).sum()}')
    else:
        print(f'club-speed head: only {len(yc)} trainable rows — showing raw physics')

    # garmin extras from the csv rows
    import csv
    gext = {}
    for name in ('garmin_main.csv', 'garmin_small.csv'):
        with open(os.path.join(SESSION, name), encoding='utf-8-sig') as f:
            for row in csv.DictReader(f):
                d = (row.get('Date') or '').strip()
                if d and row.get('Ball Speed'):
                    gext[d] = row
    from datetime import datetime
    def gkey(p):
        return datetime.fromisoformat(p['garmin_time']).strftime('%-m/%-d/%y %-I:%M:%S %p')

    trs = []
    n = 0
    sum_ball = []
    sum_club = []
    sum_conf = []
    for r in rows:
        shot = r['shot']
        p = pairs.get(shot)
        if not p or not p.get('garmin_ball_mph'):
            continue
        n += 1
        g = gext.get(gkey(p), {})
        t = shot[14:16] + ':' + shot[16:18] + ':' + shot[18:20]
        gb = p['garmin_ball_mph']
        f = r['detector']
        ours = pred_by_shot.get(shot)
        conf = bool(f and ((f['_n_flight'] >= 3 and f['_chi_max'] <= 2.5) or
                           (f['_n_flight'] == 2 and f['_2pt_agree'] <= 0.25)))
        if ours is not None:
            rel = abs(ours - gb) / gb * 100
            sum_ball.append(rel)
            if conf: sum_conf.append(rel)
            ball_cell = f'<td class="{dcls(rel)}">{ours:.1f}</td><td class="{dcls(rel)}">{rel:.1f}%</td>'
        else:
            ball_cell = '<td class="mut">—</td><td class="mut">withheld</td>'
        gcv = float(g['Club Speed']) if g.get('Club Speed') else None
        ocv = club_pred_by_shot.get(shot)
        if ocv is None and f and f.get('club_v') and f.get('r_lock_sub'):
            ocv = f['club_v'] * (BALL_M / 2 / max(f['r_lock_sub'], 2)) * 2.23694
        if ocv and gcv:
            crel = abs(ocv - gcv) / gcv * 100
            sum_club.append(crel)
            club_cell = f'<td>{gcv:.1f}</td><td class="{dcls(crel)}">{ocv:.1f}</td><td class="{dcls(crel)}">{crel:.0f}%</td>'
        else:
            club_cell = f'<td>{gcv:.1f}</td><td class="mut">—</td><td class="mut">—</td>' if gcv else '<td class="mut">—</td><td class="mut">—</td><td class="mut">—</td>'
        vla = vla_by_shot.get(shot)
        if vla:
            ov, gv2 = vla
            vd = abs(ov - gv2)
            vcls = 'g' if vd <= 1.5 else ('y' if vd <= 3 else 'r')
            vla_cell = f'<td>{gv2:.1f}°</td><td class="{vcls}">{ov:.1f}°</td><td class="{vcls}">{vd:.1f}°</td>'
        else:
            vla_cell = '<td class="mut">—</td><td class="mut">—</td><td class="mut">—</td>'
        gdir = g.get('Launch Direction')
        odir = f.get('angle') if f else None
        dir_cell = (f'<td class="mut">{float(gdir):+.1f}°</td><td class="mut">{odir:+.1f}°</td>'
                    if (gdir and odir is not None) else '<td class="mut">—</td><td class="mut">—</td>')
        trs.append(
            f'<tr><td>{t}</td><td>{gb:.1f}</td>{ball_cell}'
            f'<td>{"✓" if conf else "·"}</td><td>{f["_n_flight"] if f else 0}</td>'
            f'{club_cell}{vla_cell}{dir_cell}</tr>')

    sb = np.array(sum_ball); sc = np.array(sum_club); scf = np.array(sum_conf) if sum_conf else np.array([99.0])
    html = f"""<title>Garmin vs TrueCarry — shot by shot</title>
<style>
:root {{ --bg:#101410; --panel:#1a201a; --line:#2a332a; --text:#e8ece6; --mut:#9aa598; }}
@media (prefers-color-scheme: light) {{ :root {{ --bg:#f4f6f1; --panel:#fff; --line:#dde3d8; --text:#1a221a; --mut:#5c665a; }} }}
:root[data-theme="dark"] {{ --bg:#101410; --panel:#1a201a; --line:#2a332a; --text:#e8ece6; --mut:#9aa598; }}
:root[data-theme="light"] {{ --bg:#f4f6f1; --panel:#fff; --line:#dde3d8; --text:#1a221a; --mut:#5c665a; }}
body {{ background:var(--bg); color:var(--text); font:14px/1.5 -apple-system,BlinkMacSystemFont,sans-serif; margin:0; padding:28px 16px 70px; }}
main {{ max-width:1080px; margin:0 auto; }}
h1 {{ font-size:23px; margin:0 0 4px; }}
.sub {{ color:var(--mut); margin:0 0 16px; max-width:95ch; }}
.tblwrap {{ overflow-x:auto; border:1px solid var(--line); border-radius:8px; }}
table {{ border-collapse:collapse; width:100%; font-variant-numeric:tabular-nums; }}
th, td {{ padding:5px 9px; text-align:right; border-bottom:1px solid var(--line); font-size:13px; white-space:nowrap; }}
th {{ position:sticky; top:0; background:var(--panel); font-size:11px; text-transform:uppercase; letter-spacing:.05em; color:var(--mut); }}
td:first-child, th:first-child {{ text-align:left; }}
.g {{ color:#6ee7a0; font-weight:600; }} .y {{ color:#e0c93f; }} .r {{ color:#ff6b5e; }} .mut {{ color:var(--mut); }}
.sum {{ background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:10px 14px; margin:0 0 14px; display:inline-block; }}
</style>
<main>
<h1>Garmin vs TrueCarry — shot by shot</h1>
<p class="sub">Ball speed = out-of-fold model prediction (no shot is scored by a model that saw it). Club speed = stacked model (physics measurement + out-of-fold ball prediction as input) where trainable, raw physics otherwise — trained upwards, ball → club → VLA, each level consuming only out-of-fold outputs from below. The model is club-agnostic: no club-type information is used anywhere in the pipeline. Launch direction shown grey for reference only: it's relative to phone aim vs Garmin aim. ✓ = track passed the confidence gate; "withheld" = the pipeline declines to produce a number (fewer than 2 usable flight points).</p>
<div class="sum">All predicted (n={len(sb)}): ball median |Δ| {np.median(sb):.1f}%<br>
<b>Confident-only, what the app would show (n={len(scf)}):</b> ball median |Δ| {np.median(scf):.1f}% · ≤2%: {(scf<=2).sum()} · ≤5%: {(scf<=5).sum()}<br>
Club speed stacked (n={len(sc)}): median |Δ| {np.median(sc):.1f}% · VLA stacked: see Δ° column</div>
<div class="tblwrap"><table>
<tr><th>time</th><th>Garmin ball</th><th>ours</th><th>Δ</th><th>conf</th><th>pts</th><th>Garmin club</th><th>ours club</th><th>Δ</th><th>G VLA</th><th>our VLA</th><th>Δ°</th><th>G dir</th><th>our dir</th></tr>
{''.join(trs)}
</table></div>
</main>"""
    out = os.path.join(SESSION, 'viz', 'compare_table.html')
    with open(out, 'w') as fh:
        fh.write(html)
    print(f'wrote {out} — {n} shots, ball n={len(sb)} median {np.median(sb):.1f}%, club n={len(sc)} median {np.median(sc):.1f}%')


if __name__ == '__main__':
    main()
