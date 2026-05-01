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

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.ballstrike.camera.session")
    private let videoQueue = DispatchQueue(label: "com.ballstrike.camera.video", qos: .userInteractive)
    private let detector = BallDetector()
    private let ciContext = CIContext()

    private var device: AVCaptureDevice?

    // ROI in normalized 1x-camera space; accessed from both main and video threads.
    private let roiLock = NSLock()
    nonisolated(unsafe) private var _searchROI: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

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
    private let requiredStableFrames = 8
    private let stableCenterThreshold: CGFloat = 0.025
    private let leaveSpotThreshold: CGFloat = 0.035

    private var pendingPostCapture = false
    private var eventFrames: [CapturedFrame] = []
    private var remainingPostFrames = 0
    private var lastPublishedDetectionTime = CACurrentMediaTime()

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
        let frame = makeCapturedFrame(from: pixelBuffer, timestamp: timestamp)

        Task { @MainActor in
            processFrame(frame, observation: observation)
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
    private func processFrame(_ frame: CapturedFrame?, observation: BallObservation?) {
        if let frame {
            rollingBuffer.append(frame)
            if rollingBuffer.count > rollingBufferLimit {
                rollingBuffer.removeFirst(rollingBuffer.count - rollingBufferLimit)
            }
        }

        if pendingPostCapture {
            if let frame { eventFrames.append(frame) }
            remainingPostFrames -= 1
            if remainingPostFrames <= 0 {
                capturedFrames = Array(eventFrames.prefix(preHitFrames + postHitFrames + 1))
                currentBallRect = nil
                phase = .captured
                statusText = "Captured \(capturedFrames.count) hit frames"
                pendingPostCapture = false
                eventFrames = []
            }
            return
        }

        guard let observation else {
            currentBallRect = nil
            if phase == .ready {
                triggerHitCapture()
            } else {
                phase = .searching
                statusText = "Looking for ball"
                stableFrameCount = 0
                stableRect = nil
            }
            return
        }

        currentBallRect = observation.normalizedRect
        lastPublishedDetectionTime = CACurrentMediaTime()

        switch phase {
        case .searching, .captured:
            phase = .tracking
            statusText = "Ball found"
            stableRect = observation.normalizedRect
            stableFrameCount = 1

        case .tracking:
            updateStability(with: observation.normalizedRect)
            statusText = "Tracking ball: \(stableFrameCount)/\(requiredStableFrames) stable frames"
            if stableFrameCount >= requiredStableFrames {
                phase = .ready
                stableRect = observation.normalizedRect
                statusText = "Ready — waiting for hit"
                print("LOCKED ball at rect: \(observation.normalizedRect)")
                print("stableFrameCount: \(stableFrameCount)")
            }

        case .ready:
            guard let stableRect else { return }
            let distance = normalizedDistance(stableRect.center, observation.normalizedRect.center)
            if distance > leaveSpotThreshold {
                triggerHitCapture()
            } else {
                self.stableRect = observation.normalizedRect
                statusText = "Ready — ball stationary"
            }
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
        guard !pendingPostCapture else { return }
        phase = .captured
        statusText = "Hit detected — collecting surrounding frames"
        pendingPostCapture = true
        remainingPostFrames = postHitFrames
        eventFrames = Array(rollingBuffer.suffix(preHitFrames))
        stableFrameCount = 0
        stableRect = nil
    }

    nonisolated private func normalizedDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
