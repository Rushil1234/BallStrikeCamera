import AVFoundation
import SwiftUI
import CoreImage
import CoreMedia
import UIKit
import QuartzCore

final class CameraController: NSObject, ObservableObject {
    @Published var phase: CameraPhase = .searching
    @Published var selectedShutter: ShutterPreset = .oneThousand
    @Published var currentBallRect: CGRect?
    @Published var capturedFrames: [CapturedFrame] = []
    @Published var statusText: String = "Looking for ball"
    @Published var isAnalyzingShot: Bool = false
    @Published var latestShotAnalysis: ShotAnalysisResult?
    @Published var analysisStatusText: String = ""
    @Published var showReview: Bool = false
    @Published var showShotResult: Bool = false
    /// Set by the hosting screen whenever the selected club changes. Putter shots are slow-rolling
    /// and never leave the ground, so capture/tracking/metrics all need different behavior — see
    /// preHitFrames/postHitFrames below and computeAnalysis's isPutterMode parameter.
    @Published var isPutterMode: Bool = false

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.ballstrike.camera.session")
    private let videoQueue = DispatchQueue(label: "com.ballstrike.camera.video", qos: .userInteractive)
    private let detector = BallDetector()
    private let impactDetector = ImpactDetector()
    private let ciContext = CIContext()

    private var device: AVCaptureDevice?
    private var videoOutputRef: AVCaptureVideoDataOutput?

    // ROI in normalized 1x-camera space; accessed from both main and video threads.
    private let roiLock = NSLock()
    nonisolated(unsafe) private var _searchROI: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    // While the result screen / analysis is up there is nothing useful for the live pipeline
    // to do, and its 240fps detect+render loop was starving the analysis threads (measured
    // 31% frame drops and a seconds-long "Analyzing" screen). Set on MainActor, read on the
    // video queue under roiLock.
    nonisolated(unsafe) private var _liveProcessingPaused = false

    // Impact ROI — set on MainActor when ball locks, read on videoQueue via impactLock.
    private let impactLock = NSLock()
    nonisolated(unsafe) private var _impactROI: CGRect? = nil
    private var lockedImpactROI: CGRect?

    func updateSearchROI(_ roi: CGRect) {
        print("CameraController search ROI updated: \(roi)")
        roiLock.lock()
        defer { roiLock.unlock() }
        _searchROI = roi
    }

    private var rollingBuffer: [CapturedFrame] = []
    private let rollingBufferLimit = 120
    // Putter shots move far slower than a full swing — more frames both before and after impact
    // give the tracker more samples to fit a reliable speed from, at the cost of a longer capture
    // window (~421ms vs ~171ms at 240fps). rollingBufferLimit (120) already covers preHitFrames+1
    // in both cases.
    private var preHitFrames: Int { isPutterMode ? 50 : 20 }
    private var postHitFrames: Int { isPutterMode ? 50 : 20 }

    private var stableRect: CGRect?
    private var stableFrameCount = 0
    // A club sweeping through the placement circle can look ball-shaped for a frame or two,
    // which used to flip .searching → .tracking and hide the "Set into" circle. Require a
    // short run of consecutive plausible detections (12.5ms at 240fps) before leaving
    // .searching — imperceptible for a real ball, rarely satisfied by a moving clubhead.
    private var searchingStreak = 0
    private let searchingStreakRequired = 3
    private var trackingMissCount = 0
    private let trackingMissLimit = 5   // tolerate brief gaps before resetting stable count
    private var lockedBallRect: CGRect?
    private var lockedStateEnteredAt: Date?
    private let requiredStableFrames = 20
    private let stableCenterThreshold: CGFloat = 0.025
    private let leaveSpotThreshold: CGFloat = 0.035

    // How many consecutive missing/invalid frames are tolerated before leaving .ready.
    private var readyLostFrameCount = 0
    // Throttles the "club pull-back suppressed" log (fires per-frame while suppressing).
    private var clubPullSuppressCount = 0
    // Throttles automatic exposure re-locks when lighting drifts (see relockExposureIfDrifted).
    private var lastExposureRelock = Date.distantPast
    private let readyLostFrameLimit = 120   // ~0.5 s at 240 fps
    private let readyNearThreshold: CGFloat = 0.06
    private let readyHoldLogInterval = 240  // throttle "hold" prints (~1 s at 240 fps)

    private var pendingPostCapture = false
    private var eventFrames: [CapturedFrame] = []
    private var remainingPostFrames = 0
    private var lastPublishedDetectionTime = CACurrentMediaTime()
    // Caps @Published overlay-rect updates at ~30Hz during tracking — see processFrame.
    private var lastOverlayPublishTime: CFTimeInterval = 0
    private var reviewTriggerLogCount: Int = 0

    // Plausibility thresholds. The ball sits at a FIXED distance from the mounted camera, so
    // its apparent size barely varies — every genuine lock in the field logs measured
    // w=0.042-0.047, h=0.075-0.083. The old window (w up to 0.070) was 1.6x the real ball,
    // wide enough for shoe/club glare blobs to slip through and trigger phantom shots.
    private let ballMinWidth:  CGFloat = 0.028
    private let ballMaxWidth:  CGFloat = 0.062
    private let ballMinHeight: CGFloat = 0.050
    private let ballMaxHeight: CGFloat = 0.108
    private let ballMinAspect: CGFloat = 0.35   // width / height
    private let ballMaxAspect: CGFloat = 0.95
    // Roundness gate: a ball is a solid bright disc that fills its cluster bbox densely — the
    // real ball measured fill ~0.6-0.8 in the field (77 bright samples in a ~10x10 cell grid).
    // Ball-SIZED glare slivers on a shoe or clubhead are elongated/hollow and fill far less.
    // 0.30 proved too lenient (a foot still triggered a shot); 0.42 keeps 40%+ margin under
    // the ball's worst observed value.
    private let ballMinFillRatio: Double = 0.42

    // Throttle rejection prints: print at most once every 30 rejected frames.
    private var rejectedFrameCount = 0
    private let rejectionLogInterval = 30

    // Frame timing diagnostics — touched only from videoQueue, so nonisolated(unsafe) is safe.
    private let targetFPS: Double = 240.0
    private let frameStatsPrintInterval: Double = 2.0
    nonisolated(unsafe) private var lastFrameTimestamp: Double = -1
    nonisolated(unsafe) private var totalFramesSeen: Int = 0
    nonisolated(unsafe) private var droppedFrameEstimate: Int = 0
    nonisolated(unsafe) private var lastFrameStatsPrintTime: Double = -1
    nonisolated(unsafe) private var frameStatsWindowStartTime: Double = -1
    nonisolated(unsafe) private var windowFramesSeen: Int = 0

    override init() {
        super.init()
    }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else {
                Task { @MainActor in
                    self?.statusText = "Camera permission is required"
                }
                return
            }

            self?.sessionQueue.async { [weak self] in
                self?.configureSessionIfNeeded()
                self?.session.startRunning()
                Task { @MainActor in
                    self?.applyShutter(.oneThousand)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func applyShutter(_ preset: ShutterPreset) {
        selectedShutter = preset
        statusText = "Shutter \(preset.label)"

        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }

            // Re-measure the scene before freezing exposure. Locking straight onto
            // device.iso (the old behavior) captures whatever transient ISO the sensor
            // last had — often a stale/arbitrary value from right after session start
            // or from a previous custom lock — instead of a value calibrated to what's
            // actually in frame. Kicking back to auto and waiting for it to settle gives
            // us a real reading before we snapshot it.
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {
                print("BallDetector exposure: could not re-enable auto-exposure before lock: \(error.localizedDescription)")
            }

            let convergeStart = CACurrentMediaTime()
            var waited = 0.0
            let timeout = 1.0
            while device.isAdjustingExposure && waited < timeout {
                Thread.sleep(forTimeInterval: 0.05)
                waited = CACurrentMediaTime() - convergeStart
            }
            let converged = !device.isAdjustingExposure
            let autoConvergedDuration = device.exposureDuration
            print(String(format: "BallDetector exposure: auto-converge %@ after %.2fs — preConvergeISO=%.1f preConvergeDuration=1/%.0f targetOffset=%.2fEV",
                         converged ? "settled" : "TIMED OUT", waited,
                         device.iso, autoConvergedDuration.seconds > 0 ? 1.0 / autoConvergedDuration.seconds : 0,
                         device.exposureTargetOffset))

            do {
                try device.lockForConfiguration()
                var duration = CMTime(value: 1, timescale: preset.denominator)
                let minISO = Double(device.activeFormat.minISO)
                let maxISO = Double(device.activeFormat.maxISO)

                // Preserve the AE-metered exposure across the duration change: exposure ∝
                // duration × ISO, so a preset N× faster than what AE metered needs N× the ISO.
                // Keeping the metered ISO unchanged (old behavior) underexposed by exactly that
                // ratio — e.g. 1/8000 against a metered 1/1300 ran ~2.7 stops dark, dim enough
                // that the ball in flight disappeared from post-impact tracking while the
                // stationary pre-shot ball still read fine.
                let meteredISO    = Double(device.iso)
                let autoSeconds   = autoConvergedDuration.seconds
                let presetSeconds = 1.0 / Double(preset.denominator)
                var neededISO     = meteredISO
                if autoSeconds > 0, presetSeconds > 0 {
                    neededISO = meteredISO * autoSeconds / presetSeconds
                }

                if neededISO < minISO {
                    // Preset is slower than the scene needs and ISO can't drop below the floor —
                    // locking the preset would overexpose. Keep the AE-metered duration instead.
                    print(String(format: "BallDetector exposure: preset %@ would overexpose at floor ISO (%.1f) — using auto-converged duration 1/%.0f instead",
                                 preset.label, minISO, autoSeconds > 0 ? 1.0 / autoSeconds : 0))
                    duration = autoConvergedDuration
                    neededISO = meteredISO
                } else if neededISO > maxISO {
                    // The requested shutter can't be exposed even at max ISO. Honoring it anyway
                    // ran sessions 3 stops dark — the ball went invisible in flight and the
                    // tracker chased ISO-noise blobs. A launch monitor needs a VISIBLE ball more
                    // than an ultra-fast shutter: lock the fastest duration max ISO can expose.
                    let properSeconds = min(autoSeconds * (meteredISO / maxISO), 1.0 / 250.0)
                    if properSeconds > presetSeconds {
                        duration = CMTimeMakeWithSeconds(properSeconds, preferredTimescale: 1_000_000)
                        print(String(format: "BallDetector exposure: preset %@ needs ISO %.0f (max %.0f) — using fastest properly-exposed duration 1/%.0f instead",
                                     preset.label, neededISO, maxISO, 1.0 / properSeconds))
                    }
                    neededISO = maxISO
                }

                let targetISO = Float(min(max(neededISO, minISO), maxISO))
                print(String(format: "BallDetector exposure: LOCKING preset=%@ iso=%.1f (metered %.1f @ 1/%.0f, range %.0f-%.0f) duration=1/%.0f",
                             preset.label, targetISO, meteredISO,
                             autoSeconds > 0 ? 1.0 / autoSeconds : 0,
                             minISO, maxISO,
                             duration.seconds > 0 ? 1.0 / duration.seconds : 0))
                device.setExposureModeCustom(duration: duration, iso: targetISO, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                Task { @MainActor in
                    self.statusText = "Could not set shutter: \(error.localizedDescription)"
                }
            }
        }
    }

    private func configureSessionIfNeeded() {
        guard session.inputs.isEmpty, session.outputs.isEmpty else { return }

        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            Task { @MainActor in self.statusText = "Back camera unavailable" }
            return
        }

        session.addInput(input)
        self.device = camera
        configureCameraForHighFPS(camera)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = false
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            Task { @MainActor in self.statusText = "Video output unavailable" }
            return
        }

        session.addOutput(videoOutput)
        self.videoOutputRef = videoOutput

        if let connection = videoOutput.connection(with: .video) {
            // Buffer orientation must match the hand-locked UI orientation. Lefty locks the
            // interface to .landscapeLeft (180° from righty); if the buffer stays
            // .landscapeRight the screen-space search ROI maps to the diagonally-opposite
            // region of the buffer and the detector literally scans the wrong patch of grass.
            // Rotating the buffer also makes a lefty's ball travel right→left in buffer
            // coordinates exactly like a righty's, so the entire analysis pipeline
            // (HitDirection, club side, launch ROI) works unchanged for both hands.
            connection.videoOrientation = Self.videoOrientationForHand()
            connection.isVideoMirrored = false
        }

        session.commitConfiguration()
    }

    private static func videoOrientationForHand() -> AVCaptureVideoOrientation {
        UserDefaults.standard.string(forKey: "tc_hitting_hand") == "L" ? .landscapeLeft : .landscapeRight
    }

    /// Call whenever the hitting-hand preference changes so the detection buffer re-orients
    /// along with the UI lock (the preview layer already does this on its own connection).
    func applyHandOrientation() {
        sessionQueue.async { [weak self] in
            guard let self, let connection = self.videoOutputRef?.connection(with: .video) else { return }
            let target = Self.videoOrientationForHand()
            if connection.videoOrientation != target {
                connection.videoOrientation = target
                print("Camera buffer orientation → \(target == .landscapeLeft ? "landscapeLeft (lefty)" : "landscapeRight (righty)")")
            }
        }
    }

    private func configureCameraForHighFPS(_ camera: AVCaptureDevice) {
        do {
            try camera.lockForConfiguration()
            if let format = best240FPSFormat(for: camera) {
                camera.activeFormat = format
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 240)
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 240)
            }

            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            camera.unlockForConfiguration()
        } catch {
            Task { @MainActor in
                self.statusText = "Could not configure 240fps: \(error.localizedDescription)"
            }
        }
    }

    private func expandedImpactROI(from rect: CGRect, scale: CGFloat = 2.5) -> CGRect {
        let cx = rect.midX
        let cy = rect.midY
        let w  = rect.width  * scale
        let h  = rect.height * scale
        let expanded = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        return expanded.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func best240FPSFormat(for camera: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = camera.formats.filter { format in
            format.videoSupportedFrameRateRanges.contains { range in
                range.maxFrameRate >= 240 && range.minFrameRate <= 240
            }
        }

        return formats.max { lhs, rhs in
            let lhsDims = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let rhsDims = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return Int(lhsDims.width) * Int(lhsDims.height) < Int(rhsDims.width) * Int(rhsDims.height)
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        logFrameTiming(timestamp: timestamp)
        roiLock.lock()
        let roi = _searchROI
        let paused = _liveProcessingPaused
        roiLock.unlock()
        // Result screen / analysis active: skip detection, impact checks, and the per-frame
        // CGImage render entirely so analysis gets the CPU.
        if paused { return }
        let raw = detector.detect(in: pixelBuffer, roi: roi)
        // Discard detections whose center falls in the corners of the bounding rect
        // but outside the actual circular placement boundary (ellipse equation check).
        let observation = raw.flatMap { obs -> BallObservation? in
            guard roi.width > 0, roi.height > 0 else { return obs }
            let dx = (obs.center.x - roi.midX) / (roi.width  / 2)
            let dy = (obs.center.y - roi.midY) / (roi.height / 2)
            return dx * dx + dy * dy <= 1 ? obs : nil
        }
        impactLock.lock()
        let impactROI = _impactROI
        impactLock.unlock()

        var impactDetected = false
        if let impactROI {
            impactDetector.establishBaselineIfNeeded(pixelBuffer: pixelBuffer, roi: impactROI)
            impactDetected = impactDetector.checkForImpact(pixelBuffer: pixelBuffer, roi: impactROI)
        }

        let frame = makeCapturedFrame(from: pixelBuffer, timestamp: timestamp)

        Task { @MainActor in
            processFrame(frame, observation: observation, impactDetected: impactDetected)
        }
    }

    nonisolated private func logFrameTiming(timestamp: Double) {
        let expectedDuration = 1.0 / targetFPS

        // Initialise window on first frame.
        if lastFrameStatsPrintTime < 0 {
            lastFrameStatsPrintTime = timestamp
            frameStatsWindowStartTime = timestamp
        }

        // Estimate dropped frames by looking at the gap since the last delivered frame.
        if lastFrameTimestamp >= 0 {
            let delta = timestamp - lastFrameTimestamp
            if delta > expectedDuration * 1.5 {
                let missed = Int(round(delta / expectedDuration)) - 1
                droppedFrameEstimate += missed
            }
        }
        lastFrameTimestamp = timestamp

        totalFramesSeen  += 1
        windowFramesSeen += 1

        let elapsed = timestamp - lastFrameStatsPrintTime
        if elapsed >= frameStatsPrintInterval {
            let windowDuration = timestamp - frameStatsWindowStartTime
            let windowFPS = windowDuration > 0 ? Double(windowFramesSeen) / windowDuration : 0
            let dropRate = totalFramesSeen + droppedFrameEstimate > 0
                ? Double(droppedFrameEstimate) / Double(totalFramesSeen + droppedFrameEstimate) * 100
                : 0

            print(String(format: "Frame stats: seen=%d estimatedDropped=%d dropRate=%.1f%% windowFPS=%.1f",
                         totalFramesSeen, droppedFrameEstimate, dropRate, windowFPS))

            // Live exposure state — lets us see if the custom lock actually held (mode
            // should stay .custom) and how far the current fixed exposure is from what
            // auto-exposure would pick for the current scene (targetOffset far from 0
            // means the locked exposure is wrong for what's currently in frame).
            if let device {
                let modeStr = device.exposureMode == .custom ? "custom" : "\(device.exposureMode.rawValue)"
                let offset = device.exposureTargetOffset
                print(String(format: "Exposure state: mode=%@ iso=%.1f duration=1/%.0f targetOffset=%.2fEV isAdjusting=%@",
                             modeStr, device.iso,
                             device.exposureDuration.seconds > 0 ? 1.0 / device.exposureDuration.seconds : 0,
                             offset, device.isAdjustingExposure ? "yes" : "no"))
                // Conditions drifted badly since the lock (cloud/sun change) — a whole session
                // once ran at +2.5EV blown out / 3 stops under and every shot was garbage.
                // Re-meter and re-lock, but only while idle (never mid-ready or mid-analysis).
                if abs(offset) > 1.5 {
                    Task { @MainActor in self.relockExposureIfDrifted() }
                }
            }

            lastFrameStatsPrintTime    = timestamp
            frameStatsWindowStartTime  = timestamp
            windowFramesSeen           = 0
        }
    }

    nonisolated private func makeCapturedFrame(from pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> CapturedFrame? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let targetWidth: CGFloat = 360
        let scale = targetWidth / image.extent.width
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return CapturedFrame(image: UIImage(cgImage: cgImage), timestamp: timestamp)
    }

    @MainActor
    private func processFrame(_ frame: CapturedFrame?, observation: BallObservation?, impactDetected: Bool) {
        if let frame {
            rollingBuffer.append(frame)
            if rollingBuffer.count > rollingBufferLimit {
                rollingBuffer.removeFirst(rollingBuffer.count - rollingBufferLimit)
            }
        }

        if pendingPostCapture {
            if let frame { eventFrames.append(frame) }
            remainingPostFrames -= 1
            let collectedPost = postHitFrames - remainingPostFrames
            if collectedPost % 20 == 0 && collectedPost > 0 && remainingPostFrames > 0 {
                print("Post-impact frames collected: \(collectedPost)/\(postHitFrames)")
            }
            if remainingPostFrames <= 0 {
                capturedFrames = Array(eventFrames.prefix(preHitFrames + postHitFrames + 1))
                let expectedTotal = preHitFrames + postHitFrames + 1
                print("Shot capture complete: totalFrames=\(capturedFrames.count) expected=\(expectedTotal)")
                // Testing mode: persist every raw burst (even ones analysis will later discard) so
                // they can be batch-exported and compared against a reference monitor. No-op unless
                // the developer "Save all frames" toggle is on.
                FrameArchiveService.shared.archive(frames: capturedFrames, impactIndex: preHitFrames)
                print("Resetting shot pipeline")
                let savedLockedBallRect  = lockedBallRect   // capture before reset clears them
                let savedLockedImpactROI = lockedImpactROI
                pendingPostCapture = false
                eventFrames = []
                resetShotPipeline(to: .captured, status: "Captured \(capturedFrames.count) hit frames")
                analyzeCapturedFrames(capturedFrames,
                                      lockedBallRect: savedLockedBallRect,
                                      lockedImpactROI: savedLockedImpactROI)
            }
            return
        }

        // While review screen is open, block all shot triggers.
        if phase == .reviewingShot {
            reviewTriggerLogCount += 1
            if reviewTriggerLogCount % 240 == 1 {
                print("Shot trigger ignored: review screen active")
            }
            return
        }

        // Handle the .ready phase before the observation guard so we can apply the
        // lost-frame counter regardless of whether the detector returned anything.
        if phase == .ready {
            // Assigning an @Published fires objectWillChange even when the value is identical,
            // and at 240fps that re-invalidates the SwiftUI camera panel every frame — starving
            // the TimelineView animation that draws the aim fan. Publish only on real change.
            if currentBallRect != lockedBallRect { currentBallRect = lockedBallRect }
            if statusText != "READY — watching for impact" { statusText = "READY — watching for impact" }

            let observationValid = observation.map { isPlausibleBallObservation($0) } ?? false
            let nearLock = observationValid && observation.map { isObservationNearLockedBall($0) } ?? false

            if impactDetected {
                let lockAge = lockedStateEnteredAt.map { Date().timeIntervalSince($0) } ?? 0
                // Was 0.6s — swinging quickly after the lock had the trigger suppressed for
                // ~280ms AFTER the ball left, so the capture buffer missed the entire flight
                // (67 suppressed trigger frames observed). The 20-stable-frame lock + roundness
                // + well-inside gates already prevent positioning false-fires; 0.25s is enough.
                guard lockAge >= 0.25 else {
                    // Suppress — ball is still being positioned
                    return
                }
                // The impact ROI's brightness dropped, but the ball is STILL sitting at its
                // locked spot — whatever left the ROI was the club being pulled back from
                // address (the EMA baseline absorbs the club, so pulling it away looks like a
                // brightness collapse). A real strike can't leave the ball at the lock.
                if nearLock {
                    readyLostFrameCount = 0
                    clubPullSuppressCount += 1
                    if clubPullSuppressCount % 60 == 1 {
                        print("Impact trigger suppressed: ball still at locked position (club pull-back, #\(clubPullSuppressCount))")
                    }
                    return
                }
                print("ROI IMPACT DETECTED — triggering capture")
                triggerHitCapture()
                return
            }

            if nearLock {
                if readyLostFrameCount > 0 {
                    print("READY maintained: valid ball near locked rect (was lost for \(readyLostFrameCount) frames)")
                }
                readyLostFrameCount = 0
            } else {
                readyLostFrameCount += 1
                if readyLostFrameCount % readyHoldLogInterval == 1 {
                    print("READY hold: missing/invalid frame count \(readyLostFrameCount)")
                }
                if readyLostFrameCount >= readyLostFrameLimit {
                    print("READY lost — ball absent/invalid for \(readyLostFrameCount) frames")
                    resetShotPipeline(to: .searching, status: "Looking for ball")
                }
            }
            return
        }

        guard let observation else {
            searchingStreak = 0
            // During tracking, tolerate a short run of nil frames (glare flicker, single
            // bad detection) so one missed frame doesn't reset 7 frames of stable count.
            if phase == .tracking {
                trackingMissCount += 1
                if trackingMissCount <= trackingMissLimit { return }
            }
            resetShotPipeline(to: .searching, status: "Looking for ball")
            return
        }
        trackingMissCount = 0

        lastPublishedDetectionTime = CACurrentMediaTime()

        // Outside .ready, filter implausible observations before they touch stability logic.
        guard isPlausibleBallObservation(observation) else {
            searchingStreak = 0
            return
        }

        switch phase {
        case .searching, .captured:
            // Only balls well inside the setup circle may start tracking at all. Previously an
            // out-of-circle ball entered .tracking, got a green circle drawn on it, and sat in
            // limbo forever — tracked but never able to reach ready.
            guard isWellInsideSearchROI(observation.center) else {
                searchingStreak = 0
                if currentBallRect != nil { currentBallRect = nil }
                if statusText != "Move ball into the circle" { statusText = "Move ball into the circle" }
                return
            }
            searchingStreak += 1
            guard searchingStreak >= searchingStreakRequired else { return }
            currentBallRect = observation.normalizedRect
            phase = .tracking
            statusText = "Ball found"
            stableRect = observation.normalizedRect
            stableFrameCount = 1

        case .tracking:
            // Ball must be well inside the setup circle — not near the edge or rolling in.
            // Checked BEFORE publishing the overlay rect so a ball outside the circle never
            // shows a tracking circle it can't convert into a lock.
            guard isWellInsideSearchROI(observation.center) else {
                if stableFrameCount > 0 {
                    stableFrameCount = 0
                    stableRect = nil
                }
                if currentBallRect != nil { currentBallRect = nil }
                if statusText != "Move ball into the circle" {
                    statusText = "Move ball into the circle"
                }
                return
            }
            // The rect genuinely moves a little every frame; publishing all 240 of those per
            // second re-invalidates the SwiftUI panel constantly. ~30Hz is visually identical.
            let now = CACurrentMediaTime()
            if now - lastOverlayPublishTime >= 1.0 / 30.0 {
                lastOverlayPublishTime = now
                currentBallRect = observation.normalizedRect
            }
            updateStability(with: observation.normalizedRect)
            let trackingStatus = "Tracking ball: \(stableFrameCount)/\(requiredStableFrames) stable frames"
            if statusText != trackingStatus { statusText = trackingStatus }
            if stableFrameCount >= requiredStableFrames {
                let rect = observation.normalizedRect
                let aspect = rect.width / rect.height
                lockedBallRect = rect
                currentBallRect = rect
                phase = .ready
                stableRect = rect
                readyLostFrameCount = 0
                lockedStateEnteredAt = Date()
                statusText = "READY — swing when ready"

                let impactROI = expandedImpactROI(from: rect)
                lockedImpactROI = impactROI
                impactLock.lock()
                _impactROI = impactROI
                impactLock.unlock()
                impactDetector.reset()
                print("Impact ROI: \(impactROI)")

                print("LOCKED valid ball rect: \(rect), aspect: \(String(format: "%.3f", aspect))")
                print("stableFrameCount: \(stableFrameCount)")
            }

        case .ready:
            break  // handled above

        case .reviewingShot:
            break  // blocked above
        }
    }

    // Center must sit within ~77% of the setup-circle radius (ellipse test in normalized
    // coords). Shared by the searching→tracking gate and the tracking stability gate.
    @MainActor
    private func isWellInsideSearchROI(_ center: CGPoint) -> Bool {
        roiLock.lock()
        let roi = _searchROI
        roiLock.unlock()
        guard roi.width > 0, roi.height > 0 else { return true }
        let dx = (center.x - roi.midX) / (roi.width  / 2)
        let dy = (center.y - roi.midY) / (roi.height / 2)
        return dx * dx + dy * dy <= 0.60
    }

    @MainActor
    private func isPlausibleBallObservation(_ observation: BallObservation) -> Bool {
        let rect = observation.normalizedRect
        guard rect.width  >= ballMinWidth,  rect.width  <= ballMaxWidth,
              rect.height >= ballMinHeight, rect.height <= ballMaxHeight else {
            logRejection(rect)
            return false
        }
        let aspect = rect.width / rect.height
        guard aspect >= ballMinAspect, aspect <= ballMaxAspect else {
            logRejection(rect)
            return false
        }
        guard observation.fillRatio >= ballMinFillRatio else {
            rejectedFrameCount += 1
            if rejectedFrameCount % rejectionLogInterval == 1 {
                print("Rejected non-round candidate: fill=\(String(format: "%.2f", observation.fillRatio)) < \(ballMinFillRatio) rect=\(rect) (rejection #\(rejectedFrameCount))")
            }
            return false
        }
        return true
    }

    @MainActor
    private func isObservationNearLockedBall(_ observation: BallObservation) -> Bool {
        guard let locked = lockedBallRect else { return false }
        let distance = normalizedDistance(locked.center, observation.normalizedRect.center)
        return distance <= readyNearThreshold
    }

    @MainActor
    private func logRejection(_ rect: CGRect) {
        rejectedFrameCount += 1
        if rejectedFrameCount % rejectionLogInterval == 1 {
            print("Rejected implausible ball rect: \(rect) (rejection #\(rejectedFrameCount))")
        }
    }

    @MainActor
    private func updateStability(with rect: CGRect) {
        guard let previous = stableRect else {
            stableRect = rect
            stableFrameCount = 1
            return
        }

        let distance = normalizedDistance(previous.center, rect.center)
        if distance <= stableCenterThreshold {
            stableFrameCount += 1
        } else {
            stableFrameCount = 1
        }
        stableRect = rect
    }

    @MainActor
    private func triggerHitCapture() {
        guard !pendingPostCapture, phase != .captured else { return }
        phase = .captured
        statusText = "Impact detected — capturing"
        pendingPostCapture = true
        remainingPostFrames = postHitFrames
        // suffix(preHitFrames + 1): 20 pre-impact frames + the impact frame itself.
        eventFrames = Array(rollingBuffer.suffix(preHitFrames + 1))
        let expectedFrameCount = preHitFrames + postHitFrames + 1
        print("Impact capture config: preHitFrames=\(preHitFrames) postHitFrames=\(postHitFrames) expectedFrameCount=\(expectedFrameCount)")
        print("Impact capture started")
        print("Started hit capture with \(eventFrames.count) pre/impact frames")
        impactDetector.reset()
        stableFrameCount = 0
        stableRect = nil
        readyLostFrameCount = 0
    }

    @MainActor
    private func analyzeCapturedFrames(_ frames: [CapturedFrame],
                                       lockedBallRect: CGRect?,
                                       lockedImpactROI: CGRect?) {
        guard !frames.isEmpty else { return }
        isAnalyzingShot = true
        analysisStatusText = "Analyzing shot..."
        // Present the result screen NOW — the cover shows an analyzing placeholder until the
        // (off-main) analysis lands, instead of sitting on the camera view for the whole
        // pipeline. Clear the previous shot first so stale metrics can't flash.
        latestShotAnalysis = nil
        showShotResult = true
        phase = .reviewingShot
        setLiveProcessingPaused(true)
        print("Shot analysis started with \(frames.count) frames")

        let preHit = preHitFrames
        let putterMode = isPutterMode

        // The heavy work (2× image normalization per frame + ball tracking + metrics) used to run
        // synchronously on the main actor, freezing the UI for the whole duration before the shot
        // screen could appear. Run it off-main and only touch @Published state back on the main actor.
        Task.detached(priority: .userInitiated) {
            let outcome = Self.computeAnalysis(frames: frames,
                                               lockedBallRect: lockedBallRect,
                                               lockedImpactROI: lockedImpactROI,
                                               preHitFrames: preHit,
                                               isPutterMode: putterMode)
            await MainActor.run {
                switch outcome {
                case .discard:
                    // No trustworthy metrics → false trigger or unreadable tracking. Dismiss the
                    // analyzing cover silently and tell the user why in the status line.
                    print("[ShotValidation] No valid metrics — discarding, resuming search")
                    self.isAnalyzingShot = false
                    self.showShotResult = false
                    self.setLiveProcessingPaused(false)
                    self.resetShotPipeline(to: .searching, status: "Bad tracking — shot discarded")
                case .repositioned:
                    // Ball was moved within the circle, not struck. Quietly re-arm and re-lock.
                    self.isAnalyzingShot = false
                    self.showShotResult = false
                    self.setLiveProcessingPaused(false)
                    self.resetShotPipeline(to: .searching, status: "Ball moved — re-locking")
                case .result(let result):
                    self.latestShotAnalysis = result
                    self.isAnalyzingShot = false
                    self.analysisStatusText = "Analysis complete"
                    print("Shot analysis complete: \(result.frames.count) frames, impact at index \(result.impactFrameIndex)")
                    print("Showing ShotResultView")
                    self.showShotResult = true
                    self.phase = .reviewingShot
                    self.reviewTriggerLogCount = 0
                    // Dev mode: real-time upload to Google Drive, only for shots that made it past
                    // the plausibility check above (not a discarded false trigger). No-op unless
                    // signed in and the toggle is on.
                    GoogleDriveUploadService.shared.uploadShotIfEnabled(
                        frames: result.frames.map { $0.originalFrame },
                        impactIndex: result.impactFrameIndex
                    )
                }
            }
        }
    }

    private enum AnalysisOutcome {
        case discard
        // The "shot" was the user repositioning the ball inside the circle (or the track never
        // really left the setup area) — not a strike. Resume searching and re-lock quietly.
        case repositioned
        case result(ShotAnalysisResult)
    }

    /// Pure compute: normalization → tracking → metrics validation. Touches no actor-isolated
    /// state, so it is safe to run off the main actor.
    nonisolated private static func computeAnalysis(frames: [CapturedFrame],
                                                    lockedBallRect: CGRect?,
                                                    lockedImpactROI: CGRect?,
                                                    preHitFrames: Int,
                                                    isPutterMode: Bool) -> AnalysisOutcome {
        let impactIndex     = min(preHitFrames, frames.count - 1)
        let originTimestamp = frames[impactIndex].timestamp
        let normalizer      = FrameNormalizer()

        // Step 1 — Normalize. Only the darkened-high-contrast variant is on the critical path
        // (it's what tracking scans); the "brightened" variant was cosmetic-only and doubled
        // the render count, so it's skipped — display/save fall back to the original frames.
        // Rendered in parallel: CIContext is thread-safe and this was the single biggest
        // chunk of the analyzing-screen latency (670ms serial under thermal throttle).
        let normStart = Date()
        var darkened = [UIImage?](repeating: nil, count: frames.count)
        darkened.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: frames.count) { i in
                buf[i] = normalizer.normalizedImage(from: frames[i].image, mode: .darkenedHighContrast)
            }
        }
        let prelimFrames: [AnalyzedShotFrame] = frames.enumerated().map { idx, frame in
            AnalyzedShotFrame(
                frameIndex: idx,
                timestamp: frame.timestamp,
                relativeTime: frame.timestamp - originTimestamp,
                originalFrame: frame,
                brightenedImage: nil,
                darkenedHighContrastImage: darkened[idx],
                ballObservation: nil,
                debugInfo: nil
            )
        }
        let normMs = Date().timeIntervalSince(normStart) * 1000
        print(String(format: "Frame normalization took %.1f ms", normMs))

        // Step 2 — Track
        var observationMap: [Int: ShotBallObservation] = [:]
        var debugInfoMap:   [Int: ShotFrameDebugInfo]  = [:]
        var effectiveImpactIndex = impactIndex
        var fallbackImpactIndex = impactIndex
        var impactDetectionReason = "no_locked_ball_rect"
        var initialBallCenter: CGPoint? = nil
        var movementThresholdNorm: CGFloat = 0
        if let lockedRect = lockedBallRect {
            let tracker = PostImpactBallTracker(
                configuration: isPutterMode ? .putterPreset : PostImpactBallTracker.Configuration()
            )
            let trackingResult = tracker.track(
                frames: prelimFrames,
                lockedBallRect: lockedRect,
                impactFrameIndex: impactIndex
            )
            effectiveImpactIndex = trackingResult.detectedImpactFrameIndex
            fallbackImpactIndex = trackingResult.fallbackImpactFrameIndex
            impactDetectionReason = trackingResult.impactDetectionReason
            initialBallCenter = trackingResult.initialBallCenter
            movementThresholdNorm = trackingResult.movementThresholdNorm
            for obs  in trackingResult.observations { observationMap[obs.frameIndex]  = obs }
            for info in trackingResult.debugInfos   { debugInfoMap[info.frameIndex]   = info }
        }

        // Step 3 — Merge into final frames
        let finalFrames: [AnalyzedShotFrame] = prelimFrames.map { frame in
            AnalyzedShotFrame(
                frameIndex: frame.frameIndex,
                timestamp: frame.timestamp,
                relativeTime: frame.relativeTime,
                originalFrame: frame.originalFrame,
                brightenedImage: frame.brightenedImage,
                darkenedHighContrastImage: frame.darkenedHighContrastImage,
                ballObservation: observationMap[frame.frameIndex],
                debugInfo: debugInfoMap[frame.frameIndex]
            )
        }

        // Reposition check: if the last tracked post-impact position is still inside the
        // impact ROI (the area right around where the ball was locked), nothing actually
        // launched — the user moved the ball within the circle. Skip metrics entirely and
        // go straight back to re-locking.
        if let impactROI = lockedImpactROI {
            let lastTracked: CGPoint? = finalFrames
                .filter { $0.frameIndex > effectiveImpactIndex }
                .compactMap { f -> CGPoint? in
                    guard let o = f.ballObservation, let x = o.centerX, let y = o.centerY else { return nil }
                    return CGPoint(x: x, y: y)
                }
                .last
            if let p = lastTracked, impactROI.contains(p) {
                print("[ShotValidation] Ball still inside the setup area after capture — reposition, not a shot")
                return .repositioned
            }
        }

        let analysisCreatedAt = Date()
        let baseResult = ShotAnalysisResult(
            frames: finalFrames,
            impactFrameIndex: effectiveImpactIndex,
            lockedBallRect: lockedBallRect,
            lockedImpactROI: lockedImpactROI,
            createdAt: analysisCreatedAt,
            fallbackImpactFrameIndex: fallbackImpactIndex,
            detectedImpactFrameIndex: effectiveImpactIndex,
            impactDetectionReason: impactDetectionReason,
            initialBallCenter: initialBallCenter,
            movementThresholdNorm: movementThresholdNorm
        )

        // Experimental: physically-calibrated metrics from the measured 58"x32" ground footprint.
        // Console-only — runs alongside the trained-model metrics for R10 validation, changes nothing.
        let groundPlaneResult = GroundPlaneMetricsCalculator().calculate(
            observations: finalFrames.compactMap { $0.ballObservation },
            impactFrameIndex: effectiveImpactIndex,
            groundCalibration: GroundCalibration.shared
        )

        var validMetrics: ShotMetricsResult? = nil
        if let metrics = ShotMetricsCalculator().calculate(for: baseResult, isPutterMode: isPutterMode) {
            // SANITY CHECK — reject physically impossible readings caused by
            // tracking noise, glare, or a second ball placement.
            let speedOK = metrics.ballLaunch.ballSpeedMph.map  { $0 >= 0.5 && $0 <= 200 } ?? true
            let hlaOK   = metrics.ballLaunch.hlaDegrees.map    { abs($0) <= 75          } ?? true
            let carryOK = metrics.distance.carryYards.map      { $0 >= 0   && $0 <= 375 } ?? true
            if speedOK && hlaOK && carryOK {
                validMetrics = metrics
            } else {
                print(String(format: "[ShotValidation] Implausible metrics suppressed — speed=%.1f hla=%.1f carry=%.1f",
                             metrics.ballLaunch.ballSpeedMph ?? 0,
                             metrics.ballLaunch.hlaDegrees ?? 0,
                             metrics.distance.carryYards ?? 0))
            }
            GroundPlaneMetricsCalculator.logResult(
                groundPlaneResult,
                existingSpeedMph: metrics.ballLaunch.ballSpeedMph,
                existingHLA: metrics.ballLaunch.hlaDegrees,
                existingVLA: metrics.ballLaunch.vlaDegrees
            )
        } else {
            GroundPlaneMetricsCalculator.logResult(
                groundPlaneResult, existingSpeedMph: nil, existingHLA: nil, existingVLA: nil
            )
        }

        guard let metrics = validMetrics else { return .discard }

        // A non-putter "shot" under 3 mph is a hand nudge, not a strike (the slowest real chip
        // is far faster). Putter mode keeps its own lower floor since slow taps are legitimate.
        if !isPutterMode, let speed = metrics.ballLaunch.ballSpeedMph, speed < 3.0 {
            print(String(format: "[ShotValidation] %.1f mph without putter selected — reposition, not a shot", speed))
            return .repositioned
        }

        let result = ShotAnalysisResult(
            frames: finalFrames,
            impactFrameIndex: effectiveImpactIndex,
            lockedBallRect: lockedBallRect,
            lockedImpactROI: lockedImpactROI,
            createdAt: analysisCreatedAt,
            fallbackImpactFrameIndex: fallbackImpactIndex,
            detectedImpactFrameIndex: effectiveImpactIndex,
            impactDetectionReason: impactDetectionReason,
            initialBallCenter: initialBallCenter,
            movementThresholdNorm: movementThresholdNorm,
            metrics: metrics
        )
        return .result(result)
    }

    @MainActor
    func dismissShotPresentation() {
        showShotResult = false
        showReview = false
        setLiveProcessingPaused(false)
        print("Shot result dismissed; shot pipeline re-armed")
        resetShotPipeline(to: .searching, status: "Looking for ball")
    }

    private func setLiveProcessingPaused(_ paused: Bool) {
        roiLock.lock()
        _liveProcessingPaused = paused
        roiLock.unlock()
    }

    /// Exposure drifted >1.5EV from the metering target (lighting changed since the lock).
    /// Re-runs the meter+lock cycle for the current preset — only while searching/tracking so
    /// a mid-swing or mid-analysis brightness change can never corrupt a capture.
    func relockExposureIfDrifted() {
        guard phase == .searching || phase == .tracking, !isAnalyzingShot else { return }
        guard Date().timeIntervalSince(lastExposureRelock) > 3.0 else { return }
        lastExposureRelock = Date()
        print("Exposure drifted — re-metering and re-locking preset \(selectedShutter.label)")
        applyShutter(selectedShutter)
    }

    @MainActor
    func dismissReview() {
        dismissShotPresentation()
    }

    @MainActor
    func simulateShot() {
        print("Simulate Shot requested")
        guard phase != .reviewingShot else {
            print("Simulate Shot ignored: review screen active")
            return
        }
        guard !isAnalyzingShot else {
            print("Simulate Shot ignored: analysis already running")
            return
        }
        do {
            let shot = try SampleShotLoader.loadRawFramesOnly()
            print("Simulate Shot: running fresh live analysis")
            statusText = "Simulating shot…"
            analyzeCapturedFrames(shot.frames,
                                  lockedBallRect: shot.lockedBallRect,
                                  lockedImpactROI: shot.lockedImpactROI)
        } catch {
            statusText = "Sample shot not found"
            print("Simulate Shot failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func resetShotPipeline(to newPhase: CameraPhase, status: String) {
        phase = newPhase
        statusText = status
        currentBallRect = nil
        lockedBallRect = nil
        lockedImpactROI = nil
        impactLock.lock()
        _impactROI = nil
        impactLock.unlock()
        impactDetector.reset()
        stableRect = nil
        stableFrameCount = 0
        searchingStreak = 0
        trackingMissCount = 0
        readyLostFrameCount = 0
        lockedStateEnteredAt = nil
    }

    nonisolated private func normalizedDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
