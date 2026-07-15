#!/usr/bin/env python3
"""Score the Swift V2 engine's replay outputs against Garmin (parity gate).

Reads ReplayResults/*.json produced by the headless replay with the V2 engine
live, extracts the final metrics (V2-overridden where confident, tagged in
warnings), pairs with Garmin, and prints the same scorecard as the Python
pipeline for apples-to-apples comparison.

Usage: python3 score_v2_swift.py <ReplayResults dir>
"""
import json, glob, os, sys
import numpy as np

SESSION = os.path.expanduser('~/Documents/TrueCarryTraining/session_2026-07-12')


def main():
    d = sys.argv[1]
    pairs = json.load(open(os.path.join(SESSION, 'pairs.json')))
    res = {}
    for f in glob.glob(os.path.join(d, 'shot_*.json')):
        res[os.path.basename(f)[:-5]] = json.load(open(f))

    rel_all, rel_conf, vla_rows = [], [], []
    n_v2_active = n_v2_low = n_v2_withheld = n_legacy = 0
    for p in pairs:
        shot = p.get('shot')
        if not shot or shot not in res or not p.get('garmin_ball_mph'):
            continue
        j = res[shot]
        m = j.get('metrics', {})
        speed = m.get('ballSpeedMph')
        warns = ' | '.join(m.get('warnings', []) or [])
        g = p['garmin_ball_mph']
        v2_active = 'V2 metrics active' in warns
        if v2_active:
            n_v2_active += 1
        elif 'V2 low-confidence' in warns:
            n_v2_low += 1
        elif 'V2 withheld' in warns:
            n_v2_withheld += 1
        else:
            n_legacy += 1
        if isinstance(speed, (int, float)) and speed:
            rel = abs(speed - g) / g * 100
            rel_all.append(rel)
            if v2_active:
                rel_conf.append(rel)

    ra = np.array(rel_all)
    print(f'paired shots with a displayed speed: {len(ra)}')
    print(f'V2 active(confident)={n_v2_active}  low-conf={n_v2_low}  withheld={n_v2_withheld}  no-v2-tag={n_legacy}')
    if len(ra):
        print(f'ALL displayed:      median {np.median(ra):.1f}%  ≤2%: {(ra<=2).sum()}  ≤5%: {(ra<=5).sum()}  >10%: {(ra>10).sum()}')
    if rel_conf:
        rc = np.array(rel_conf)
        print(f'V2-CONFIDENT only:  n={len(rc)}  median {np.median(rc):.1f}%  ≤2%: {(rc<=2).sum()} ({100*(rc<=2).mean():.0f}%)  ≤5%: {(rc<=5).sum()} ({100*(rc<=5).mean():.0f}%)  >10%: {(rc>10).sum()}')
    print('\nPython reference (July 14): detector all 4.2-4.6% median; confident ~4.1%.')


if __name__ == '__main__':
    main()
