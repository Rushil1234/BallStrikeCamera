# TrueCarry Accuracy Plan — Range Day 2026-07-19

**The bar (Noah):** any shot, any metric, within the band TT and Garmin disagree by (~3%).

## Targets vs current (live build, July-17 yellow session, TT truth)

| Metric | Target | Current median | Status / lever |
|---|---|---|---|
| Ball speed | ±2 mph (~2%) | 3.5% (~3 mph) | 720px capture + ~100 new TT pairs + mishit guard |
| VLA | ±1° | 2.8° | 720px doubles diameter precision (binding constraint) |
| Club speed | ±3 mph | **2.4 mph via smash ✓ SHIPPED** | clubSpeed = ballSpeed/smash(club), per-club table from 289 TT rows; direct tracking stays fallback (14.2→ calibratable to ~9%) |
| Backspin | ±1000 rpm | not yet reported in-app | learn from 288 TT rows (est. CV ~1045 → under 1000 with new rows) |
| Sidespin | ±200 rpm | not measured | needs lateral curvature — 720px 6-point experiment |
| Carry | ±2 yd | 9.3 yd live; **physics ODE: 3.3 yd median on TT's own inputs** | ballistic drag/lift fit (tools/experimental/tt_physics.py) beats all regressions; Swift port next |
| Total | ±4 yd | 8.7 yd | same |

Tracking state: yellow flight 100% (jul17) / 98.0% (jul16), white 97.67% (all-time high).
All models TT-referenced (Garmin→TT cross-calibration: launch TT=0.912·G−3.88, speed identity).

## Key finding: the "TT equation" has a ceiling from launch numbers alone

Fitting carry/total on TT's OWN inputs (speed/VLA/spin/club/direction, 289 rows):
best CV = carry 4.4 yd median, total 4.2 yd. GBT no better than ridge → the residual is
trajectory-integration information (TT observes the whole flight; launch numbers alone
don't determine landing). Consequences:
1. Carry ≤2 yd needs BOTH tighter inputs AND trajectory features we measure ourselves
   (descent/apex from 720px tracks) — mimic what TT integrates.
2. Also: carry error ≈ 1.6 yd/mph speed error + ~2.5 yd/° VLA error. The carry goal
   implies speed ≤~1 mph and VLA ≤~0.5°.
3. flight_model.json retrained on all 289 rows (was 119, single-session).

## Tomorrow protocol (range: ~100 yellow, TT+Garmin · home: ~100 white, Garmin)

1. **First 3 shots: verify 720px** — watch for frame-drop warnings; if they appear,
   Profile → toggle OFF "720p Measurement Capture" (new kill-switch) and keep hitting.
2. **Log clubs in TT for every shot** (the alignment + truth backbone).
3. Continuous blocks, one ball type per block. Mishits welcome — models need them.
4. If allowed: 15–20 WHITE balls at the TT bay → whites' first direct TT pairs.
5. Home whites: Garmin only is fine (cross-calibration converts to TT scale).
6. Export/upload all three (frames zip, swingsync CSV, Garmin CSV) like July 17.

## Day-after pipeline (tools/tc_lab.py — one command per phase)

```
python3 tools/tc_lab.py ingest --zip <frames.zip> --tt <swingsync.csv> \
    --garmin <garmin.csv> --session 2026-07-19 --after 08:00
python3 tools/tc_lab.py replay --archives 2026-07-19
python3 tools/tc_lab.py score  --session 2026-07-19 --realign
python3 tools/tc_lab.py train  && python3 tools/tc_lab.py replay --archives all --build
```
Viewers: :8765 labeler · :8766 shot viewer (frames+tracking+3-way metrics) · :8767 progress.

## End-of-day 2026-07-19 goals

- [ ] 720px field-validated (no frame drops, archives at 720 wide)
- [ ] ~200 new shots ingested + auto-aligned (yellow TT+Garmin, white Garmin[+TT bay if possible])
- [ ] Heads retrained on ~2× data (both colors); speed median ≤2.5%, aiming ≤2 mph
- [ ] VLA retrained with 720px diameters; target ≤2°, aiming lower
- [ ] Club round: coverage ≥80%, club-speed head vs TT club pairs, error ≤5 mph (path to 3)
- [ ] Backspin model shipped (TT-learned), report in-app; target ≤1000 rpm CV
- [ ] Sidespin curvature experiment on 720px tracks (measure, don't promise)
- [ ] Hosel-point retest on 720px (Noah's clubless-speed idea: shaft-head junction as
      the invariant point; sound geometry, blocked at 360px — shaft detector fired 1/51;
      at 720px the shaft doubles in apparent width)
- [ ] Carry/total refit incl. our measured descent/apex features; target ≤5 yd median (path to 2/4)
- [ ] Full validation: all suites, no regressions; viewer refreshed; committed

## Standing lessons (do not re-learn)

- Alignment: DP-with-skips only; TT is the sole club-truth; verify with club sequence.
- Offline-first iteration (43 s/366 shots); sim replay = final parity only.
- Every dead end gets a measurement + code comment (see PostImpactBallTracker).
- Container UUID rotates on install — resolve AFTER install+launch; verify by mtimes.
