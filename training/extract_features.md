# Feature extraction (Swift replay harness)

The per-frame flight features come from the app's replay harness (runs the REAL tracker):

```
# 1. build the app for the sim
xcodebuild -project BallStrikeCamera.xcodeproj -scheme BallStrikeCamera \
  -destination 'id=<SIM_UDID>' -configuration Debug build
xcrun simctl install <SIM> <app.app>
# 2. drop a session's frames into the sim container's Documents/AllFramesArchive/
# 3. batch-replay every shot through the live pipeline -> Documents/ReplayResults/<shot>.json
SIMCTL_CHILD_TC_OPEN_TESTER=1 SIMCTL_CHILD_TC_REPLAY_ALL=1 \
  xcrun simctl launch --console-pty --terminate-running-process <SIM> com.noahtobias.BallStrikeCamera
# 4. flatten ReplayResults/*.json -> one features.csv (shot_id,t,u,v,diameter,ball_speed) -> Drive features/
```

`ReplayResults/<shot>.json` already carries per-frame `t` + observation `(u,v,diameter)` (LiveParityTestRunner).
For a standalone quick check, the compiled `BallDetector`/`ImpactDetector` harness in scratch works too,
but the FULL flight features need the tracker (PostImpactBallTracker) which only runs in the app/sim.
