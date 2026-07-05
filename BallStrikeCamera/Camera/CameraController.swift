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

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.ballstrike.camera.session")
    private let videoQueue = DispatchQueue(label: "com.ballstrike.camera.video", qos: .userInteractive)
    private let detector = BallDetector()
    private let impactDetector = ImpactDetector()
    private let ciContext = CIContext()

    private var device: AVCaptureDevice?

    // ROI in normalized 1x-camera space; accessed from both main and video threads.
    private let roiLock = NSLock()
    nonisolated(unsafe) private var _searchROI: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

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
    private let preHitFrames = 20
    private let postHitFrames = 20

    private var stableRect: CGRect?
    private var stableFrameCount = 0
    private var trackingMissCount = 0
    private let trackingMissLimit = 5   // tolerate brief gaps before resetting stable count
    private var lockedBallRect: CGRect?
    private var lockedStateEnteredAt: Date?
    private let requiredStableFrames = 20
    private let stableCenterThreshold: CGFloat = 0.025
    private let leaveSpotThreshold: CGFloat = 0.035

    // How many consecutive missing/invalid frames are tolerated before leaving .ready.
    private var readyLostFrameCount = 0
    private let readyLostFrameLimit = 120   // ~0.5 s at 240 fps
    private let readyNearThreshold: CGFloat = 0.06
    private let readyHoldLogInterval = 240  // throttle "hold" prints (~1 s at 240 fps)

    private var pendingPostCapture = false
    private var eventFrames: [CapturedFrame] = []
    private var remainingPostFrames = 0
    private var lastPublishedDetectionTime = CACurrentMediaTime()
    private var reviewTriggerLogCount: Int = 0

    // Plausibility thresholds — based on observed good rects (w≈0.021–0.038, h≈0.037–0.067)
    // and bad false locks (w≈0.21–0.24, h≈0.37–0.43).
    private let ballMinWidth:  CGFloat = 0.012
    private let ballMaxWidth:  CGFloat = 0.070
    private let ballMinHeight: CGFloat = 0.020
    private let ballMaxHeight: CGFloat = 0.120
    private let ballMinAspect: CGFloat = 0.35   // width / height
    private let ballMaxAspect: CGFloat = 0.95

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
            do {
                try device.lockForConfiguration()
                let duration = CMTime(value: 1, timescale: preset.denominator)
                let minISO = device.activeFormat.minISO
                let maxISO = device.activeFormat.maxISO

                // Let ISO float near the current exposure, but clamp to the active format.
                let targetISO = min(max(device.iso, minISO), maxISO)
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

        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .landscapeRight
            connection.isVideoMirrored = false
        }

        session.commitConfiguration()
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
        roiLock.unlock()
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
            currentBallRect = lockedBallRect
            statusText = "READY — watching for impact"

            if impactDetected {
                let lockAge = lockedStateEnteredAt.map { Date().timeIntervalSince($0) } ?? 0
                guard lockAge >= 0.6 else {
                    // Suppress — ball is still being positioned
                    return
                }
                print("ROI IMPACT DETECTED — triggering capture")
                triggerHitCapture()
                return
            }

            let observationValid = observation.map { isPlausibleBallObservation($0) } ?? false
            let nearLock = observationValid && observation.map { isObservationNearLockedBall($0) } ?? false

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
        guard isPlausibleBallObservation(observation) else { return }

        switch phase {
        case .searching, .captured:
            currentBallRect = observation.normalizedRect
            phase = .tracking
            statusText = "Ball found"
            stableRect = observation.normalizedRect
            stableFrameCount = 1

        case .tracking:
            currentBallRect = observation.normalizedRect
            // Ball must be well inside the setup circle — not near the edge or rolling in.
            // This prevents a ball being slid/rolled across the boundary from accumulating
            // stable frames and causing a false lock + false trigger.
            let isWellInsideROI: Bool = {
                roiLock.lock()
                let roi = _searchROI
                roiLock.unlock()
                guard roi.width > 0, roi.height > 0 else { return true }
                let dx = (observation.center.x - roi.midX) / (roi.width  / 2)
                let dy = (observation.center.y - roi.midY) / (roi.height / 2)
                return dx * dx + dy * dy <= 0.60  // center must be within ~77% of radius
            }()
            guard isWellInsideROI else {
                if stableFrameCount > 0 {
                    stableFrameCount = 0
                    stableRect = nil
                }
                statusText = "Move ball to center of circle"
                return
            }
            updateStability(with: observation.normalizedRect)
            statusText = "Tracking ball: \(stableFrameCount)/\(requiredStableFrames) stable frames"
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
        print("Shot analysis started with \(frames.count) frames")

        let preHit = preHitFrames

        // The heavy work (2× image normalization per frame + ball tracking + metrics) used to run
        // synchronously on the main actor, freezing the UI for the whole duration before the shot
        // screen could appear. Run it off-main and only touch @Published state back on the main actor.
        Task.detached(priority: .userInitiated) {
            let outcome = Self.computeAnalysis(frames: frames,
                                               lockedBallRect: lockedBallRect,
                                               lockedImpactROI: lockedImpactROI,
                                               preHitFrames: preHit)
            await MainActor.run {
                switch outcome {
                case .discard:
                    // No trustworthy metrics → almost certainly a false trigger (glare, a hand, a
                    // bad lock). Don't flash a blank shot screen — go straight back to searching.
                    print("[ShotValidation] No valid metrics — discarding false trigger, resuming search")
                    self.isAnalyzingShot = false
                    self.resetShotPipeline(to: .searching, status: "Looking for ball")
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
        case result(ShotAnalysisResult)
    }

    /// Pure compute: normalization → tracking → metrics validation. Touches no actor-isolated
    /// state, so it is safe to run off the main actor.
    nonisolated private static func computeAnalysis(frames: [CapturedFrame],
                                                    lockedBallRect: CGRect?,
                                                    lockedImpactROI: CGRect?,
                                                    preHitFrames: Int) -> AnalysisOutcome {
        let impactIndex     = min(preHitFrames, frames.count - 1)
        let originTimestamp = frames[impactIndex].timestamp
        let normalizer      = FrameNormalizer()

        // Step 1 — Normalize
        let normStart = Date()
        let prelimFrames: [AnalyzedShotFrame] = frames.enumerated().map { idx, frame in
            AnalyzedShotFrame(
                frameIndex: idx,
                timestamp: frame.timestamp,
                relativeTime: frame.timestamp - originTimestamp,
                originalFrame: frame,
                brightenedImage: normalizer.normalizedImage(from: frame.image, mode: .brightened),
                darkenedHighContrastImage: normalizer.normalizedImage(from: frame.image, mode: .darkenedHighContrast),
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
            let tracker = PostImpactBallTracker()
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

        var validMetrics: ShotMetricsResult? = nil
        if let metrics = ShotMetricsCalculator().calculate(for: baseResult) {
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
        }

        guard let metrics = validMetrics else { return .discard }

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
        print("Shot result dismissed; shot pipeline re-armed")
        resetShotPipeline(to: .searching, status: "Looking for ball")
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
