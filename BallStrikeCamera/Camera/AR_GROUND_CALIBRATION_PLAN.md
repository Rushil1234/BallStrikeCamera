# Ground calibration + better pre-shot detection (ARKit)

Short answer to "can't we do this with Apple's stuff": **yes — ARKit.** It can
find the tripod height above the ground and map the ground plane, and that data
makes the heuristic pre-shot ball detector much more reliable. Below is the plan;
it is written up rather than shipped because ARKit can only be validated on a real
device, and an untested ARKit file would break the whole app build.

## The key constraint that shapes the design

The capture pipeline runs a **240 fps `AVCaptureSession`** (`CameraController`,
`hd1280x720`, `activeVideoMinFrameDuration = 1/240`). **ARKit's `ARSession` cannot
run at the same time as a custom high-speed `AVCaptureSession`** — they both want
exclusive use of the camera. So this is a **pre-shot calibration phase**, not a
live overlay:

1. User aims the tripod-mounted phone at the ground near the ball.
2. A brief ARKit phase measures the ground plane + camera height.
3. We store the calibration, **stop the ARSession**, then start the 240 fps
   capture, which now detects with real-world scale.

## What ARKit gives us

- `ARWorldTrackingConfiguration(planeDetection: [.horizontal])` → an
  `ARPlaneAnchor` for the ground. Tripod height = `camera.transform.columns.3.y
  − groundPlane.transform.columns.3.y` (take the **lowest** horizontal plane as
  the ground).
- On LiDAR devices (Pro): `sceneReconstruction = .mesh` and
  `frameSemantics = .sceneDepth` give a dense ground mesh / depth map for a true
  ground map and occlusion. On non-LiDAR devices, plane detection alone still
  yields height + a flat ground plane (good enough for scale).
- `ARFrame.camera.intrinsics` + the ground plane give a **pixel↔ground
  homography**.

## How that improves pre-shot detection

The current `BallDetector` is a CPU heuristic with no notion of scale, so it can
lock "ready" on wrong-size blobs or background motion. With calibration:

1. **Expected ball size.** A golf ball is 42.67 mm. From height + intrinsics +
   the ground plane we compute the ball's **expected pixel radius** at its ground
   position. Reject candidates that are the wrong size → far fewer false readies.
2. **Ground ROI.** Project the small teeing patch of ground in front of the
   camera into image space and restrict detection to that ROI → ignore movement
   in the background / sky.
3. **Pixel→ground mapping.** Convert detections to real-world ground coordinates
   for better ball-position and launch estimates.

## Files to add (when built on-device)

- `Camera/GroundCalibration.swift` — `ARSession` wrapper (ObservableObject):
  publishes `groundHeightMeters`, `groundPlane`, and a `CalibrationResult`
  (`expectedBallRadiusPx`, `groundROI`, `pixelToGroundTransform`). Delegate
  callbacks marshal `@Published` updates to the main queue.
- `UI/.../GroundCalibrationView.swift` — `ARView`/`ARSCNView` with a live
  "Tripod height: NN cm — point at the ball" readout and a Confirm button.
- Wire `CalibrationResult` into `CameraController` → pass `expectedBallRadiusPx`
  and `groundROI` into `BallDetector.detect(...)` (it already takes an `roi`).

## Rollout

Build on a feature branch, test on a real device (ideally one LiDAR + one
non-LiDAR iPhone), confirm the height reading and the detection improvement, then
merge. Do **not** land untested ARKit on `main` — a compile error there blocks the
entire app.
