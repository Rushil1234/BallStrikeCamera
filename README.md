# Ball Strike Camera

Native iOS SwiftUI + AVFoundation starter app for detecting a stationary ball, switching to ready mode, and grabbing frames around the moment the ball leaves its spot.

## What is implemented

- Landscape-only SwiftUI layout:
  - Top half: 2/3 live camera preview, 1/3 captured-frames panel.
  - Bottom half: five empty placeholder boxes.
- Camera preview uses `.resizeAspect`, so the full camera feed is scaled into the preview area instead of being cropped.
- Four opaque shutter buttons over the preview:
  - Moon: `1/1000`
  - Cloud: `1/2000`
  - Sun: `1/4000`
  - Bright sun: `1/8000`
- AVFoundation session configured for 240 fps when the device supports it.
- Lightweight Swift detector that searches each frame for a bright, low-saturation ball-like blob.
- State machine:
  1. Searching for ball
  2. Tracking with green circle overlay
  3. Ready after the ball is stationary for multiple frames
  4. Capture trigger when the ball leaves the ready spot
- Frame capture: keeps a rolling buffer and displays frames around the hit event.

## Open and run

1. Open `BallStrikeCamera.xcodeproj` in Xcode.
2. Select your iPhone as the run target. The camera and high-FPS capture will not work correctly in Simulator.
3. Set your Apple Developer Team in Xcode under **Signing & Capabilities**.
4. Run on device.

## Important notes

- 240 fps depends on the physical iPhone camera format. If a device does not support 240 fps at the selected resolution, the app uses the best available matching format it can find.
- The detector is intentionally simple and CPU-only. It is designed to be replaced later by a stronger Core ML / Vision detector.
- Very fast shutter speeds need a lot of light. At `1/8000`, the image may be dark unless lighting is strong.
- Frame thumbnails are currently generated directly from video buffers for simple visual debugging. For production, use a more memory-efficient ring buffer or write frames to disk.

## Repo layout

```text
BallStrikeCamera/
  App/
    BallStrikeCameraApp.swift
  Camera/
    CameraController.swift
  Detection/
    BallDetector.swift
    BallObservation.swift
  Models/
    CameraPhase.swift
    PlatformImage.swift
  UI/
    ContentView.swift
    CameraPreview.swift
  Resources/
    Info.plist
    Assets.xcassets/
```

## Next upgrades

- Replace the heuristic detector with a small Core ML model trained on ball images.
- Add manual ISO controls per shutter preset.
- Add calibration for different ball colors/backgrounds.
- Add frame-by-frame scrubber after capture.
- Export the captured frame burst as images or a slow-motion clip.
