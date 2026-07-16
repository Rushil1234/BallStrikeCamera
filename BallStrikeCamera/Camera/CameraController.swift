import AVFoundation
import SwiftUI
import CoreImage
import CoreMedia
import UIKit
import QuartzCore

final class CameraController: NSObject, ObservableObject {
    @Published var phase: CameraPhase = .searching {
        didSet { syncFramesNeeded() }
    }
    @Published var selectedShutter: ShutterPreset = .oneThousand
    /// Live per-preset lighting fitness + the fastest clean choice, for the picker's badges.
    @Published var shutterFitness: [ShutterPreset: ShutterFitness] = [:]
    @Published var recommendedShutter: ShutterPreset? = nil
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

    // Frame-event staging: the capture delegate must return FAST — a synchronous GPU render
    // inside it stalls buffer release, exhausts the camera's pixel-buffer pool, and the
    // session drops frames in bursts (the 2-4-period gaps in every archived shot). Renders
    // run on a dedicated serial queue (order-preserving); events are batched to the main
    // actor through one in-flight drain task instead of 240 Tasks/second.
    private let renderQueue = DispatchQueue(label: "com.ballstrike.camera.render", qos: .userInteractive)
    private let eventLock = NSLock()
    nonisolated(unsafe) private var _stagedFrameEvents: [(CapturedFrame?, BallObservation?, Bool)] = []
    nonisolated(unsafe) private var _frameDrainScheduled = false
    nonisolated(unsafe) private var _rendersInFlight = 0
    // Set (under roiLock) when a ball lock lands; the video queue consumes it on the next
    // frame and runs the one-shot stride-1 tight-fit scan around the padded lock rect.
    nonisolated(unsafe) private var _pendingTightRefineRect: CGRect? = nil
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
    // window (~630ms vs ~171ms at 240fps). The post-impact window is the putt engine's whole
    // observation of the roll: break curvature grows with the square of observed time, so 100
    // post frames (0.42s) quadruples the bend signal vs the old 50. rollingBufferLimit (120)
    // already covers preHitFrames+1 in both cases; post frames are appended live.
    private var preHitFrames: Int { isPutterMode ? 50 : 20 }
    private var postHitFrames: Int { isPutterMode ? 100 : 20 }

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
    // exposureTargetOffset observed right after the current lock settled (written on
    // sessionQueue, read on videoQueue). The shutter-first lock intentionally runs under
    // metered exposure, so "drift" is distance from THIS baseline, not from 0EV.
    // NaN = lock in progress, drift check suspended.
    nonisolated(unsafe) private var _lockedExposureOffsetEV: Double = .nan

    /// Capture-health warning shown as a banner. Frame drops corrupt every velocity the
    /// tracker measures (July 12: 92% of shots had gaps), so degradation must be VISIBLE
    /// at the range, not discovered at analysis time. Set when two consecutive stats
    /// windows run below 225fps or above 5% drops, or the device reports serious thermals.
    @Published var captureHealthWarning: String? = nil
    nonisolated(unsafe) private var _badStatsWindows = 0
    // Windows counted since capture start — the first two always read low (session spin-up,
    // autofocus/exposure settling) and must not trip the health banner on every launch.
    nonisolated(unsafe) private var _statsWindowsSeen = 0
    private var thermalObserver: NSObjectProtocol?
    private let readyLostFrameLimit = 120   // ~0.5 s at 240 fps
    private let readyNearThreshold: CGFloat = 0.06
    private let readyHoldLogInterval = 240  // throttle "hold" prints (~1 s at 240 fps)

    private var pendingPostCapture = false {
        didSet { syncFramesNeeded() }
    }

    // Mirrors "does any consumer need rendered frames right now" onto the video queue.
    // While SEARCHING (no ball locked) nothing consumes the rolling buffer — the impact
    // trigger can't fire until 0.25s after a lock — so the per-frame CIContext render +
    // UIImage creation (the single largest steady CPU cost at 240fps, and a prime
    // overheating suspect) is skipped entirely. Buffering resumes at .tracking, a full
    // stability window (~20 frames + 0.25s) before any capture could trigger.
    nonisolated(unsafe) private var _framesNeeded = false

    private func syncFramesNeeded() {
        let needed = phase == .tracking || phase == .ready || pendingPostCapture
        roiLock.lock()
        _framesNeeded = needed
        roiLock.unlock()
    }
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
        // Console lines are heavily abbreviated so full sessions survive paste/size limits.
        print("""
        [LOG] legend — BD=BallDetector RDY=ready-phase IMP=ImpactDetector EXP=exposure FPS=frame-stats
        [LOG]   NCF=no candidate  CAND=candidate found  REJ=rejected  rej#=cluster rejected
        [LOG]   w=bright white-ish px  c=bright colored px (glare)  b/c/t/n=baseline/current/threshold/consecutive
        """)
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
                guard let self else { return }
                self.configureSessionIfNeeded()
                // Re-assert 240fps on EVERY start, not just first configure: activeFormat is
                // shared hardware state on the back camera, and any other capture session on
                // the same device (Swing Studio pose analysis, the grip-check camera step, QR
                // scanning) resets it to a 30fps format. Cool phone + "camera running at
                // 30fps" banner = exactly this.
                if let device = self.device {
                    self.reassertHighFPSIfNeeded(device, reason: "session start")
                }
                self.session.startRunning()
                Task { @MainActor in
                    self.applyShutter(.oneThousand)
                    self.observeThermalState()
                }
            }
        }
    }

    /// Serious/critical thermals throttle the CPU and are the prime suspect for the
    /// July 12 frame drops — warn the user before the captures silently degrade.
    @MainActor
    private func observeThermalState() {
        guard thermalObserver == nil else { return }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                switch ProcessInfo.processInfo.thermalState {
                case .serious:
                    self.captureHealthWarning = "Phone is running hot — frame rate may drop. Shade the phone between shots."
                case .critical:
                    self.captureHealthWarning = "Phone is overheating — captures will degrade until it cools."
                default:
                    if self.captureHealthWarning?.hasPrefix("Phone") == true {
                        self.captureHealthWarning = nil
                    }
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

            // Baseline is unknown until the new lock settles — park it so the drift
            // check in logFrameTiming can't fire against a stale value mid-converge.
            self._lockedExposureOffsetEV = .nan

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

            // isAdjustingExposure does NOT flip on synchronously when auto re-engages from a
            // custom lock — polling it immediately read "settled after 0.00s" and snapshotted
            // the PREVIOUS lock as the metering (observed: re-lock to 1/8000 "metered" the old
            // 1/1000×66 lock and stacked its ISO cap on top of it). Wait for AE to visibly
            // start adjusting before trusting "not adjusting"; if it never starts within
            // 0.35s the current exposure genuinely matches the scene and that reading is fine.
            let convergeStart = CACurrentMediaTime()
            var waited = 0.0
            let timeout = 1.0
            var sawAdjusting = false
            while waited < timeout {
                if device.isAdjustingExposure {
                    sawAdjusting = true
                } else if sawAdjusting || waited >= 0.35 {
                    break
                }
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

                // SHUTTER-FIRST lock: the preset duration is sacred. Every detector downstream
                // thresholds on brightness against a darker background, so a crisp slightly-dark
                // ball beats a bright streak every time. The AE metering above is used only to
                // pick a sane ISO: boost at most one stop over metered so frames land ~1-2 stops
                // under instead of pitch black, but NEVER slow the shutter to buy brightness.
                // (The previous brightness-preserving fallback silently locked 1/250-1/500 in
                // ordinary light — a 150mph ball smears ~10in during a 1/250 exposure, and that
                // motion blur is what collapsed in-flight tracking.)
                let meteredISO    = Double(device.iso)
                let autoSeconds   = autoConvergedDuration.seconds
                let presetSeconds = 1.0 / Double(preset.denominator)
                var neededISO     = meteredISO
                if autoSeconds > 0, presetSeconds > 0 {
                    neededISO = meteredISO * autoSeconds / presetSeconds
                }

                if neededISO < minISO {
                    // Preset is slower than the scene needs and ISO can't drop below the floor —
                    // locking the preset would overexpose. The AE duration is FASTER here, so
                    // honoring it keeps frames crisp and properly exposed.
                    print(String(format: "BallDetector exposure: preset %@ would overexpose at floor ISO (%.1f) — using auto-converged duration 1/%.0f instead",
                                 preset.label, minISO, autoSeconds > 0 ? 1.0 / autoSeconds : 0))
                    duration = autoConvergedDuration
                    neededISO = meteredISO
                }

                // Aim TWO STOPS UNDER the metered scene — the field-validated operating regime
                // (July 10 session, full sun @ 1/8000): the white ball stays decisively the
                // brightest object (tracker candidates br 141-158 vs background 95-110, matching
                // the bright-tier calibration) while grass/mat glare drops out entirely (live
                // c-counts fell ~700 → 0 at this offset). ISO is additionally ceilinged at 4×
                // metered so sensor noise stays bounded — a fast preset in dim light lands even
                // darker than −2EV rather than grainy, which the pipeline tolerates far better.
                let idealISO = neededISO / 4.0
                let isoNoiseCeiling = meteredISO * 4.0
                let targetISO = Float(min(max(idealISO, minISO), min(isoNoiseCeiling, maxISO)))
                let stopsUnder = neededISO > 0 && Double(targetISO) > 0
                    ? max(0, log2(neededISO / Double(targetISO)))
                    : 0
                if stopsUnder > 0.1 {
                    print(String(format: "BallDetector exposure: holding shutter %@ at %.1f stops under metered (iso %.0f, target -2.0, noise ceiling %.0f)",
                                 preset.label, stopsUnder, targetISO, isoNoiseCeiling))
                }
                print(String(format: "BallDetector exposure: LOCKING preset=%@ iso=%.1f (metered %.1f @ 1/%.0f, range %.0f-%.0f) duration=1/%.0f",
                             preset.label, targetISO, meteredISO,
                             autoSeconds > 0 ? 1.0 / autoSeconds : 0,
                             minISO, maxISO,
                             duration.seconds > 0 ? 1.0 / duration.seconds : 0))
                device.setExposureModeCustom(duration: duration, iso: targetISO, completionHandler: nil)
                device.unlockForConfiguration()

                // A deliberately-underexposed lock keeps exposureTargetOffset at a constant
                // negative value forever. Snapshot that settled value as the drift baseline —
                // the relock check must measure movement AWAY from it, not distance from 0,
                // or it would re-meter every few seconds for the whole session.
                self.sessionQueue.asyncAfter(deadline: .now() + 0.3) { [weak self, weak device] in
                    guard let self, let device else { return }
                    self._lockedExposureOffsetEV = Double(device.exposureTargetOffset)
                    print(String(format: "BallDetector exposure: post-lock offset baseline %+.2fEV", self._lockedExposureOffsetEV))
                }
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

    private var _lastFormatReassert: CFTimeInterval = 0

    /// Re-applies the 240fps format + pinned frame durations if the device has drifted off
    /// them (another session used the camera). No-op when everything is already right, so
    /// it's safe to call on every session start; 30s cooldown guards the recovery path.
    private func reassertHighFPSIfNeeded(_ camera: AVCaptureDevice, reason: String) {
        let maxRate = camera.activeFormat.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        let minDur = camera.activeVideoMinFrameDuration
        let pinned = minDur.value > 0 && Double(minDur.timescale) / Double(minDur.value) >= 239
        guard maxRate < 240 || !pinned else { return }
        let now = CACurrentMediaTime()
        guard now - _lastFormatReassert > 30 else { return }
        _lastFormatReassert = now
        print(String(format: "[FPS] device format degraded (max %.0f fps, pinned=%@; %@) — re-applying 240fps configuration",
                     maxRate, pinned ? "yes" : "no", reason))
        configureCameraForHighFPS(camera)
        // A format change resets exposure — re-lock the user's shutter preset on top of it.
        Task { @MainActor in
            self.applyShutter(self.selectedShutter)
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

        // One-shot tight fit of a fresh ball lock (ball is stationary, so any frame works).
        // Consumed only while live so a request can't be dropped during an analysis pause.
        roiLock.lock()
        let tightRefineRect = _pendingTightRefineRect
        if tightRefineRect != nil { _pendingTightRefineRect = nil }
        roiLock.unlock()
        if let tightRefineRect {
            let tight = detector.tightRect(in: pixelBuffer, around: tightRefineRect)
            Task { @MainActor in
                self.applyTightLockRect(tight, paddedRect: tightRefineRect)
            }
        }

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

        roiLock.lock()
        let framesNeeded = _framesNeeded
        roiLock.unlock()

        // The delegate returns HERE — before any GPU work — so the camera gets its pixel
        // buffer back within the frame budget. Every event (with or without an image) goes
        // through the same serial render queue so frames, detections, and impact flags reach
        // processFrame strictly in capture order.
        if framesNeeded {
            eventLock.lock()
            let backlogged = _rendersInFlight >= 3
            if !backlogged { _rendersInFlight += 1 }
            eventLock.unlock()
            if backlogged {
                // GPU can't keep up (thermal): sacrifice THIS frame's image, keep its
                // detection/impact event and, crucially, keep the camera itself flowing —
                // one archive gap beats a multi-frame pool-starvation burst.
                renderQueue.async { [weak self] in
                    self?.stageFrameEvent(nil, observation, impactDetected)
                }
            } else {
                renderQueue.async { [weak self] in
                    guard let self else { return }
                    let frame = self.makeCapturedFrame(from: pixelBuffer, timestamp: timestamp)
                    self.eventLock.lock()
                    self._rendersInFlight -= 1
                    self.eventLock.unlock()
                    self.stageFrameEvent(frame, observation, impactDetected)
                }
            }
        } else {
            renderQueue.async { [weak self] in
                self?.stageFrameEvent(nil, observation, impactDetected)
            }
        }
    }

    /// Appends a frame event and guarantees exactly one main-actor drain task is in flight.
    nonisolated private func stageFrameEvent(_ frame: CapturedFrame?,
                                             _ observation: BallObservation?,
                                             _ impactDetected: Bool) {
        eventLock.lock()
        _stagedFrameEvents.append((frame, observation, impactDetected))
        let schedule = !_frameDrainScheduled
        if schedule { _frameDrainScheduled = true }
        eventLock.unlock()
        if schedule {
            Task { @MainActor in self.drainFrameEvents() }
        }
    }

    @MainActor
    private func drainFrameEvents() {
        while true {
            eventLock.lock()
            let events = _stagedFrameEvents
            _stagedFrameEvents.removeAll(keepingCapacity: true)
            if events.isEmpty {
                _frameDrainScheduled = false
                eventLock.unlock()
                return
            }
            eventLock.unlock()
            for e in events {
                processFrame(e.0, observation: e.1, impactDetected: e.2)
            }
        }
    }

    nonisolated private func logFrameTiming(timestamp: Double) {
        let expectedDuration = 1.0 / targetFPS

        // Initialise window on first frame.
        if lastFrameStatsPrintTime < 0 {
            lastFrameStatsPrintTime = timestamp
            frameStatsWindowStartTime = timestamp
            _statsWindowsSeen = 0
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

            print(String(format: "[FPS] seen=%d drop=%.1f%% fps=%.1f",
                         totalFramesSeen, dropRate, windowFPS))

            // Capture-health check: one bad window is a blip (autofocus hunt, brief
            // contention); two consecutive means sustained degradation worth surfacing.
            // 225fps ≈ 6% frame loss at target 240 — beyond that, flight velocities
            // start losing whole samples on a 2-frame-visible drive.
            let windowDropRate = windowDuration > 0
                ? max(0, (240.0 - windowFPS) / 240.0 * 100) : 0
            _statsWindowsSeen += 1
            if _statsWindowsSeen <= 2 {
                // Warmup grace: the first windows after start always read low (34–41% drops
                // in the field) while the session spins up — never count them as "bad".
                _badStatsWindows = 0
            } else if windowFPS < 225 || windowDropRate > 5 {
                _badStatsWindows += 1
            } else {
                _badStatsWindows = 0
            }
            let bad = _badStatsWindows
            let thermal = ProcessInfo.processInfo.thermalState
            if bad >= 2, thermal == .nominal || thermal == .fair {
                // Sustained low fps on a COOL phone isn't throttling — it's the device
                // format drifting off 240 (another camera user). Recover automatically.
                sessionQueue.async { [weak self] in
                    guard let self, let device = self.device else { return }
                    self.reassertHighFPSIfNeeded(device, reason: "sustained low fps, cool thermals")
                }
            }
            Task { @MainActor in
                if bad >= 2 {
                    let advice = (thermal == .serious || thermal == .critical)
                        ? "Let the phone cool / close other apps."
                        : "Re-locking 240fps…"
                    self.captureHealthWarning = String(
                        format: "Camera running at %.0f fps — tracking accuracy degraded. %@", windowFPS, advice)
                } else if bad == 0, self.captureHealthWarning?.hasPrefix("Camera running") == true {
                    self.captureHealthWarning = nil
                }
            }

            // Live exposure state — lets us see if the custom lock actually held (mode
            // should stay .custom) and how far the current fixed exposure is from what
            // auto-exposure would pick for the current scene (targetOffset far from 0
            // means the locked exposure is wrong for what's currently in frame).
            if let device {
                let modeStr = device.exposureMode == .custom ? "custom" : "mode\(device.exposureMode.rawValue)"
                let offset = device.exposureTargetOffset
                print(String(format: "[EXP] %@ iso=%.0f 1/%.0f off=%+.2fEV%@",
                             modeStr, device.iso,
                             device.exposureDuration.seconds > 0 ? 1.0 / device.exposureDuration.seconds : 0,
                             offset, device.isAdjustingExposure ? " ADJUSTING" : ""))
                // Conditions drifted badly since the lock (cloud/sun change) — a whole session
                // once ran at +2.5EV blown out / 3 stops under and every shot was garbage.
                // Drift is measured against the settled post-lock baseline (the shutter-first
                // lock sits at a constant negative offset by design). Re-meter and re-lock,
                // but only while idle (never mid-ready or mid-analysis).
                let baseline = _lockedExposureOffsetEV
                if !baseline.isNaN, abs(Double(offset) - baseline) > 1.5 {
                    Task { @MainActor in self.relockExposureIfDrifted() }
                }

                // Per-preset lighting fitness: the current lock's ISO·seconds corrected by
                // the measured offset gives the correct-exposure light product; each
                // preset's required ISO follows directly. Published so the shutter picker
                // can badge every button live — choosing a shutter the light can't support
                // used to be silent until the frames came out grainy or streaked.
                let curISO = Double(device.iso)
                let curDur = device.exposureDuration.seconds
                if curISO > 0, curDur > 0 {
                    let hCorrect = curISO * curDur * pow(2.0, -Double(offset))
                    let minISO = Double(device.activeFormat.minISO)
                    let maxISO = Double(device.activeFormat.maxISO)
                    var fitness: [ShutterPreset: ShutterFitness] = [:]
                    for preset in ShutterPreset.allCases {
                        let needed = hCorrect * Double(preset.denominator)
                        let target = needed / 4.0    // the -2EV operating point
                        if needed < minISO { fitness[preset] = .tooBright }
                        else if target > maxISO { fitness[preset] = .tooDark }
                        else if target > 1600 { fitness[preset] = .grainy }
                        else { fitness[preset] = .good }
                    }
                    let order: [ShutterPreset] = [.eightThousand, .fourThousand, .twoThousand, .oneThousand]
                    let rec = order.first { fitness[$0] == .good } ?? order.first { fitness[$0] == .grainy }
                    Task { @MainActor in
                        self.shutterFitness = fitness
                        self.recommendedShutter = rec
                    }
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
                FrameArchiveService.shared.archive(frames: capturedFrames, impactIndex: preHitFrames,
                                                   lockedBallRect: lockedBallRect,
                                                   lockedImpactROI: lockedImpactROI)
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
                // Short dropouts (1-9 frames) are constant background chatter — only losses
                // long enough to matter get a line, in compact [RDY] form.
                if readyLostFrameCount >= 10 {
                    print("[RDY] re-acq after \(readyLostFrameCount) lost")
                }
                readyLostFrameCount = 0
            } else {
                readyLostFrameCount += 1
                if readyLostFrameCount == 30 || readyLostFrameCount == 90 {
                    print("[RDY] ball missing x\(readyLostFrameCount) — holding lock")
                }
                if readyLostFrameCount >= readyLostFrameLimit {
                    print("[RDY] LOST — ball absent \(readyLostFrameCount) frames, re-searching")
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

                // Cosmetic + metric polish: the lock rect above is padded 1.35× and stride-
                // quantized. Ask the video queue to tight-fit it around the actual ball on the
                // next frame so the on-screen circle hugs the ball and the tracker's locked
                // pixel diameter is the real one.
                roiLock.lock()
                _pendingTightRefineRect = rect
                roiLock.unlock()
            }

        case .ready:
            break  // handled above

        case .reviewingShot:
            break  // blocked above
        }
    }

    /// Swap the padded lock rect for the stride-1 tight fit measured on the video queue.
    /// Deliberately does NOT touch the impact ROI or the ImpactDetector baseline — those were
    /// armed from the padded rect and the trigger behavior should stay exactly as validated.
    @MainActor
    private func applyTightLockRect(_ tight: CGRect?, paddedRect: CGRect) {
        // The lock may have been lost or replaced between request and result — only apply
        // to the exact lock that asked for it.
        guard phase == .ready, lockedBallRect == paddedRect else { return }
        guard let tight else {
            print("[BD] TIGHT no-fit — keeping padded lock rect")
            return
        }
        lockedBallRect = tight
        currentBallRect = tight
        stableRect = tight
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
                print(String(format: "[BD] REJ round fill=%.2f<%.2f (%.3f,%.3f %.3fx%.3f) #%d",
                             observation.fillRatio, ballMinFillRatio,
                             rect.minX, rect.minY, rect.width, rect.height, rejectedFrameCount))
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
            print(String(format: "[BD] REJ size (%.3f,%.3f %.3fx%.3f) #%d",
                         rect.minX, rect.minY, rect.width, rect.height, rejectedFrameCount))
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
                // Any Simulate Shot hand override ends with its analysis.
                HitDirection.overrideIsLefty = nil
                // Dev mode: upload EVERY capture to Google Drive regardless of verdict —
                // discarded/false-trigger shots are exactly the footage needed to debug the
                // tracker. No-op unless signed in and the toggle is on.
                GoogleDriveUploadService.shared.uploadShotIfEnabled(frames: frames, impactIndex: preHit,
                                                                    lockedBallRect: lockedBallRect,
                                                                    lockedImpactROI: lockedImpactROI)
                switch outcome {
                case .discard(let reason):
                    // No trustworthy metrics → false trigger or unreadable tracking. Dismiss the
                    // analyzing cover and tell the user WHY — a real shot silently vanishing is
                    // indistinguishable from the trigger never firing.
                    print("[ShotValidation] ❌ SHOT DISCARDED — \(reason)")
                    self.isAnalyzingShot = false
                    self.showShotResult = false
                    self.setLiveProcessingPaused(false)
                    self.resetShotPipeline(to: .searching, status: "Shot discarded: \(reason)")
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
                }
            }
        }
    }

    private enum AnalysisOutcome {
        case discard(reason: String)
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

        // Step 2.5 — V2-primary track: when the label-trained detector produces a usable
        // track, its per-frame sightings REPLACE the legacy observations (97.4% vs 86% on
        // the labeled archive). Legacy stays for putter mode and as the no-V2 fallback.
        let v2Primary = V2PrimaryTrack.run(
            prelimFrames: prelimFrames,
            legacyObservations: observationMap,
            lockedBallRect: lockedBallRect,
            legacyImpactIndex: effectiveImpactIndex,
            impactHint: impactIndex,
            isPutterMode: isPutterMode
        )
        if v2Primary.active {
            observationMap = v2Primary.observations
            effectiveImpactIndex = v2Primary.impactFrameIndex
            impactDetectionReason = "v2_ball_motion"
            print("[V2Primary] track active — \(v2Primary.observations.values.filter { $0.centerX != nil }.count) sightings, impact f\(effectiveImpactIndex)")
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

        // Zero-flight check: not a single post-impact frame tracked the ball → there is
        // nothing to measure. Showing a result screen for these was pure noise (blank or
        // fabricated numbers) — treat exactly like a rejected shot and snap straight back
        // to hitting.
        let postImpactTracked = finalFrames.filter {
            $0.frameIndex > effectiveImpactIndex && $0.ballObservation?.centerX != nil
        }.count
        if postImpactTracked == 0 {
            print("[ShotValidation] no post-impact ball points — auto-discarding to hitting mode")
            return .discard(reason: "no ball flight detected")
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
            movementThresholdNorm: movementThresholdNorm,
            v2Output: v2Primary.v2
        )

        // Experimental: physically-calibrated metrics from the measured 58"x32" ground footprint.
        // Console-only — runs alongside the trained-model metrics for R10 validation, changes nothing.
        let groundPlaneResult = GroundPlaneMetricsCalculator().calculate(
            observations: finalFrames.compactMap { $0.ballObservation },
            impactFrameIndex: effectiveImpactIndex,
            groundCalibration: GroundCalibration.shared
        )

        var validMetrics: ShotMetricsResult? = nil
        var discardReason = "metrics calculation failed (no calibration)"
        if let metrics = ShotMetricsCalculator().calculate(for: baseResult, isPutterMode: isPutterMode) {
            // SANITY CHECK — reject physically impossible readings caused by
            // tracking noise, glare, or a second ball placement.
            let speedOK = metrics.ballLaunch.ballSpeedMph.map  { $0 >= 0.5 && $0 <= 200 } ?? true
            let hlaOK   = metrics.ballLaunch.hlaDegrees.map    { abs($0) <= 75          } ?? true
            let carryOK = metrics.distance.carryYards.map      { $0 >= 0   && $0 <= 375 } ?? true
            if speedOK && hlaOK && carryOK {
                validMetrics = metrics
                if metrics.ballLaunch.ballSpeedMph == nil {
                    // Shown anyway (composite still has diagnostic value) but say why the
                    // numbers are blank instead of leaving an unexplained "—" screen.
                    print("[ShotValidation] ⚠️ metrics incomplete — \(metrics.ballLaunch.warnings.joined(separator: "; "))")
                }
            } else {
                var failed: [String] = []
                if !speedOK { failed.append(String(format: "speed=%.1f mph", metrics.ballLaunch.ballSpeedMph ?? 0)) }
                if !hlaOK   { failed.append(String(format: "HLA=%.1f°",      metrics.ballLaunch.hlaDegrees ?? 0)) }
                if !carryOK { failed.append(String(format: "carry=%.0f yd",  metrics.distance.carryYards ?? 0)) }
                discardReason = "implausible metrics (\(failed.joined(separator: ", "))) — tracker likely followed glare/noise, see [TrackSummary]"
                print("[ShotValidation] Implausible metrics suppressed — \(failed.joined(separator: ", "))")
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

        guard let metrics = validMetrics else { return .discard(reason: discardReason) }

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
            metrics: metrics,
            v2Output: v2Primary.v2
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

    /// Exposure drifted >1.5EV from the settled post-lock baseline (lighting changed since the lock).
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
            // The bundled sample is a RIGHTY capture and its frames are never lefty-rotated —
            // analyzing it under a lefty hand setting sent every direction consumer the wrong
            // way (tracker latched onto the club). Cleared when the analysis completes.
            HitDirection.overrideIsLefty = false
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
