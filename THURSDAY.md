# THURSDAY SESSION PLAYBOOK (written 2026-07-14)

Instructions to future-me for Noah's next Garmin range session. Read fully before
touching anything. The prime directive: **the new session is a TEST first,
training data second.** Do not tune anything on it before recording its held-out
numbers.

## What shipped on 2026-07-14 (state of the world)

- **V2 engine live in-app** (`PostImpactBallTracker.swift`, bottom half; integration in
  `ShotMetricsCalculator.calculate`). Hue-distance detection + golf priors + label-trained
  scorers + stacked metric heads (ball → club → VLA) + physics guards + [0.7,1.4]×physics
  clamp + confidence gate. Confident → V2 values replace legacy ball speed/VLA/club speed
  (smash, carry, spin all derive downstream). Not confident → legacy values + warning tag.
  Kill switch: `UserDefaults tc_v2_metrics = false`.
- **Models**: `BallStrikeCamera/Resources/Models/tc_v2_models.json` (folder-ref — replacing
  the file re-ships automatically). Trained on session_2026-07-12: ball n=75, VLA n=75,
  club n=12 (club head is weak — more data needed).
- **Capture health**: yellow banner when 2 consecutive stats windows run <225fps or >5%
  drops, or thermalState ≥ serious. `[FPS]` console lines unchanged.
- **Load reductions**: no frame rendering while `.searching` (biggest idle cost gone),
  archive + Drive zips now JPEG q0.9 (~6× smaller/faster than PNG), auto-offload to Drive
  with size-verified local delete (fires on camera-screen close + app background when the
  dev toggle is on and ≥5 shots pending).
- **Frame naming**: new captures save `frame_NNN.jpg`. All Swift loaders accept both
  extensions. **Python tools still assume .png — FIX BEFORE ANALYZING NEW SHOTS** (see
  step 3 below).
- Simulate Shot uses `shot_20260712_110759_624` (driver, Garmin 98.3, ours 98.8).
- **Parity PASSED (07-14, optimized sim replay of all 223 shots)**: Swift V2-confident
  n=57, median 4.0% vs Garmin (Python reference 4.1%) — V2 stays default-ON. The
  "all displayed" median reads worse (6.9%) only because low-confidence shots show
  tagged LEGACY values. Scorer: `tools/experimental/score_v2_swift.py <ReplayResults>`.

## Data + tooling map

- Frames archive (223 shots, PNG era): `~/Documents/TrueCarryFramesArchive_20260712/AllFramesArchive`
- Labels: `~/Documents/TrueCarryTraining/labels/labels.json` (+ scorers, caches)
- Session workspace: `~/Documents/TrueCarryTraining/session_2026-07-12/`
  (`pairs.json`, garmin CSVs, `metrics_kfold.py` outputs, `viz/`)
- Tools (all repo, `tools/experimental/`): `label_server.py` (labeler, :8765),
  `gallery_server.py` (read-only tracking gallery, :8766), `eval_detector.py`,
  `run_eval2.py`, `metrics_kfold.py`, `compare_table.py`, `extract_tracks.py`
- Artifacts: report `claude.ai/code/artifact/71df052c…`, shot table `…/5589d99b…`
- Headless replay: build for sim `2833A1DF-…`, inject shots into container
  `Documents/AllFramesArchive`, launch with `SIMCTL_CHILD_TC_REPLAY_EXPORTS=1`,
  collect `Documents/ReplayResults/*.json`.

## Thursday procedure

### 0. Before Noah leaves for the range
- Install the device build **with optimization** — V2's per-frame image work is ~20×
  slower unoptimized (debug sim: ~5min/shot; optimized: ~2s/shot):
  ```bash
  xcodebuild -project BallStrikeCamera.xcodeproj -scheme BallStrikeCamera \
    -destination 'id=<DEVICE-UDID>' -configuration Debug SWIFT_OPTIMIZATION_LEVEL=-O build
  ```
  then install via Xcode (Run with "Debug executable" unchecked) or devicectl.
  Same flag applies to any simulator batch replay.
- Confirm dev toggles: Save All Frames ON, Drive auto-upload ON + signed in.
- Remind: 1/1000 shutter default, 60–100 shots across clubs, export Garmin CSV
  immediately after, shade the phone if hot, watch for the yellow banner.

### 1. Ingest (new session = session_2026-07-17 or actual date)
```bash
mkdir -p ~/Documents/TrueCarryTraining/session_<DATE>
# frames: either pull from phone (devicectl copy, see below) or download the
# auto-offloaded zips from Drive folder "TrueCarry Frames" and unzip into
# ~/Documents/TrueCarryFramesArchive_<DATE>/AllFramesArchive/
xcrun devicectl device copy from --device <UDID> \
  --domain-type appDataContainer --domain-identifier com.noahtobias.BallStrikeCamera \
  --source Documents/AllFramesArchive --destination ~/Documents/TrueCarryFramesArchive_<DATE>/AllFramesArchive
# garmin CSVs from Drive (search title contains 'DrivingRange-<date>'), decode to session dir
```
**First analysis act: frame-drop audit** on the new timestamps — this is the verdict
on the capture fixes. Compare gap rate vs July 12's 92%.

### 2. Held-out test (BEFORE any training)
- Pair: adapt `pairs` builder in the session dir (clock-offset scan ±15s, 3s window).
- The device already computed V2 metrics live — extract per-shot ball speed/VLA/club
  from the saved shots or replay JSONs and score vs Garmin **as-is**. That number is
  the first true leave-one-session-out result. Record it in the report artifact
  BEFORE anything else. Expected if all went well: confident-coverage ≥70%,
  confident ball median ≤4%; anything better than July 12's 4.1% confident = progress.

### 3. Python tools .png→.jpg fix (one-time)
New captures are `.jpg`. Patch the frame-path constructions in
`tools/experimental/*.py` (grep `frame_{fi:03d}.png` / `frame_%03d.png` /
`f.startswith('frame_')`) to try `.png` then `.jpg`. Also `label_server.py`'s
`/img/` route content-type.

### 4. Label the new session
```bash
# point ARCHIVE in extract_tracks.py (or parametrize) at the new archive dir
python3 tools/experimental/label_server.py --port 8765   # prelabels auto-generate
open http://localhost:8765
```
Noah labels (~1hr for 100 shots; approve-shot fast path). Labels append into the
same labels.json keyed by shot name — no collision (timestamps differ).

### 5. Score tracking vs new labels
`run_eval2.py` against the merged labels → per-day table now includes the new date.
Ball accuracy on the NEW day is the tracking generalization number.

### 6. Retrain with both sessions
- Rebuild scorer caches (delete `labels/ball_train_cache.json`,
  `club_train_cache_v3.json`) → `train_ball_scorer.py`, `train_club_gbt.py`
  (cross-day eval now includes the new day — watch held-out numbers).
- `metrics_kfold.py` with **leave-one-session-out** as the headline (add a
  `--holdout-day` mode: train on 7/12, test new day, and vice versa).
- Re-export: the export snippet lives in the 07-14 conversation; recreate as
  `tools/experimental/export_models.py` if not present → writes
  `Resources/Models/tc_v2_models.json`. Rebuild + reinstall app.
- Re-run headless parity on ALL labeled shots (old 223 + new) before the new
  model ships to the device.

### 7. Report
Update both artifacts (same URLs) with: drop-audit verdict, held-out test numbers,
new cross-day tracking table, retrained k-fold/LOSO numbers, refreshed shot table.

## Decision gates
- Capture fix verdict: new-session gap rate <10% = success; >30% = the drop fix
  failed, investigate before anything else (it caps everything downstream).
- V2 live verdict: held-out confident median ≤4.1% (July 12 baseline) = keep V2
  default ON; worse = flip `tc_v2_metrics` off, diagnose from replay JSONs.
- Club head: if new session yields ≥40 club-speed rows, retrain club head and
  promote it (currently n=12, barely trained).

## Open items from 2026-07-14
- LocateAnything-3B benchmark blocked: homebrew python/libexpat broke pip.
  Fix env (`brew reinstall python@3.14`), then `tools/experimental/la3b_probe.py`
  (weights already in HF cache). License = benchmark only.
- Full-resolution measurement + camera intrinsics NOT yet in the live path
  (needs capture-path surgery; biggest remaining precision lever, ~3.5×).
- Old Swift legacy tracker still computes first (V2 overrides after) — once V2
  proves out live, consider skipping legacy ball-speed work for latency.
- Club-speed head n=12 — treat its outputs as provisional until retrained.
