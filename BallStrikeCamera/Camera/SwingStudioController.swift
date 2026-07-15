import Foundation
import AVFoundation
import Vision
import UIKit

// MARK: - TrueCarry Coach: Swing Studio capture
//
// A COMPLETELY SEPARATE capture stack from CameraController (the 240fps landscape launch
// monitor with its load-bearing exposure locks). Portrait, person-framing, two modes:
//
//  • backGuided (default): back camera at the highest slo-mo rate the device offers. The
//    user can't see the screen, so framing + record are voice-guided and AUTOMATIC — a live
//    low-rate pose stream watches for full-body framing → address stillness → swing motion
//    → follow-through stillness, and starts/stops the clip itself. Zero mid-session taps.
//  • frontMirror: front camera with the live skeleton on screen for grip/posture drills.

@MainActor
final class SwingStudioController: NSObject, ObservableObject {

    enum StudioState: Equatable {
        case idle
        case starting
        case framing            // waiting for a full body in frame
        case waitingForAddress  // body framed; waiting for stillness
        case recording
        case saving
        case failed(String)
    }

    @Published var state: StudioState = .idle
    @Published var bodyInFrame = false
    /// Live joints (Vision normalized coords) for the mirror-mode skeleton overlay.
    @Published var liveJoints: [CGPoint] = []
    @Published var captureFPS: Double = 60

    let session = AVCaptureSession()
    var source: SwingCameraSource = .backGuided

    private let sessionQueue = DispatchQueue(label: "swingstudio.session")
    private let poseQueue = DispatchQueue(label: "swingstudio.pose")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let dataOutput = AVCaptureVideoDataOutput()
    private let speech = AVSpeechSynthesizer()
    private var onClipReady: ((URL) -> Void)?

    // Auto-record state machine (updated from the pose stream)
    private var lastWrist: CGPoint?
    private var lastPoseTime: TimeInterval = 0
    private var stillSince: TimeInterval?
    private var motionSeen = false
    private var recordStartedAt: TimeInterval = 0
    private var lastAnnouncement = ""
    private var shoulderScale: CGFloat = 0.12

    // MARK: Lifecycle

    func start(source: SwingCameraSource, onClipReady: @escaping (URL) -> Void) {
        self.source = source
        self.onClipReady = onClipReady
        state = .starting
        let useBack = source == .backGuided
        sessionQueue.async { [weak self] in
            self?.configureAndRun(useBack: useBack)
        }
    }

    func stop() {
        speech.stopSpeaking(at: .immediate)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
            if self.session.isRunning { self.session.stopRunning() }
        }
        state = .idle
    }

    /// Manual record toggle (mirror mode, or if the user prefers taps).
    func manualToggleRecord() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            } else {
                self.beginRecordingClip()
            }
        }
    }

    // MARK: Session config

    private nonisolated func configureAndRun(useBack: Bool) {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.sessionPreset = .inputPriority

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: useBack ? .back : .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            Task { @MainActor in self.state = .failed("Camera unavailable") }
            return
        }
        session.addInput(input)

        // Highest-fps format: prefer ≥180fps (slo-mo tempo math), else the best available.
        var fps: Double = 60
        if useBack {
            var best: (format: AVCaptureDevice.Format, rate: Double)? = nil
            for format in device.formats {
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                guard dims.height >= 720 else { continue }
                for range in format.videoSupportedFrameRateRanges {
                    let rate = range.maxFrameRate
                    if rate >= 120, rate > (best?.rate ?? 0) {
                        best = (format, rate)
                    }
                }
            }
            if let best {
                do {
                    try device.lockForConfiguration()
                    device.activeFormat = best.format
                    let clamped = min(best.rate, 240)
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(clamped))
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(clamped))
                    device.unlockForConfiguration()
                    fps = clamped
                } catch { fps = 60 }
            }
        }

        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        dataOutput.setSampleBufferDelegate(self, queue: poseQueue)
        dataOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(dataOutput) { session.addOutput(dataOutput) }

        for connection in [movieOutput.connection(with: .video), dataOutput.connection(with: .video)] {
            connection?.videoOrientation = .portrait
            if !useBack, connection?.isVideoMirroringSupported == true {
                connection?.isVideoMirrored = true
            }
        }
        session.commitConfiguration()
        session.startRunning()

        let finalFPS = fps
        Task { @MainActor in
            self.captureFPS = finalFPS
            self.state = .framing
            self.resetMachine()
            self.announce("Set the phone upright on a tripod, then step back until your whole body is in frame.")
        }
    }

    // MARK: Auto-record state machine (driven by the pose stream)

    private func resetMachine() {
        lastWrist = nil
        stillSince = nil
        motionSeen = false
    }

    fileprivate func handlePose(frame: SwingPoseFrame, at time: TimeInterval) {
        // Body framed = head AND both ankles visible with margin.
        let head = frame.joint(.nose) ?? frame.mid(.leftEar, .rightEar)
        let ankles = frame.mid(.leftAnkle, .rightAnkle)
        let framed = head != nil && ankles != nil
            && (head!.y < 0.96 && ankles!.y > 0.04)
        bodyInFrame = framed
        if let w = SwingPhaseSegmenter.shoulderWidth(frame) { shoulderScale = max(w, 0.05) }

        liveJoints = source == .frontMirror
            ? frame.joints.values.filter { $0.confidence > 0.3 }.map(\.point)
            : []

        let wrist = frame.mid(.leftWrist, .rightWrist)
            ?? frame.joint(.leftWrist) ?? frame.joint(.rightWrist)
        defer { lastWrist = wrist; lastPoseTime = time }

        switch state {
        case .framing:
            guard source == .backGuided else { return }
            if framed {
                state = .waitingForAddress
                stillSince = nil
                announce("Great. Take your address and hold still — recording starts by itself.")
            }
        case .waitingForAddress:
            guard framed else {
                state = .framing
                return
            }
            // Stillness: wrist barely moving for 1.2s → start the clip.
            if let wrist, let prev = lastWrist, lastPoseTime > 0 {
                let dt = max(time - lastPoseTime, 0.001)
                let speed = Double(hypot(wrist.x - prev.x, wrist.y - prev.y)) / dt
                if speed < Double(shoulderScale) * 0.5 {
                    if stillSince == nil { stillSince = time }
                    if time - stillSince! > 1.2 {
                        sessionQueue.async { [weak self] in self?.beginRecordingClip() }
                        state = .recording
                        recordStartedAt = time
                        motionSeen = false
                        stillSince = nil
                        announce("Recording. Swing when ready.")
                    }
                } else {
                    stillSince = nil
                }
            }
        case .recording:
            guard source == .backGuided else { return }
            // Watch for the swing (a motion burst), then stop after post-swing stillness
            // or a hard 10s cap.
            if let wrist, let prev = lastWrist, lastPoseTime > 0 {
                let dt = max(time - lastPoseTime, 0.001)
                let speed = Double(hypot(wrist.x - prev.x, wrist.y - prev.y)) / dt
                if speed > Double(shoulderScale) * 2.2 { motionSeen = true; stillSince = nil }
                if motionSeen, speed < Double(shoulderScale) * 0.5 {
                    if stillSince == nil { stillSince = time }
                    if time - stillSince! > 1.0 {
                        sessionQueue.async { [weak self] in
                            if self?.movieOutput.isRecording == true { self?.movieOutput.stopRecording() }
                        }
                    }
                }
            }
            if time - recordStartedAt > 10 {
                sessionQueue.async { [weak self] in
                    if self?.movieOutput.isRecording == true { self?.movieOutput.stopRecording() }
                }
            }
        default:
            break
        }
    }

    private nonisolated func beginRecordingClip() {
        guard !movieOutput.isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swing_\(Int(Date().timeIntervalSince1970)).mov")
        try? FileManager.default.removeItem(at: url)
        movieOutput.startRecording(to: url, recordingDelegate: self)
    }

    private func announce(_ text: String) {
        guard text != lastAnnouncement else { return }
        lastAnnouncement = text
        guard source == .backGuided else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        speech.speak(utterance)
    }
}

// MARK: - Pose stream (low-rate live framing)

extension SwingStudioController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        // ~10Hz is plenty for framing + the auto-record state machine.
        let now = CACurrentMediaTime()
        if now - _lastLivePose < 0.1 { return }
        _lastLivePose = now
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectHumanBodyPoseRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up).perform([request])
        var joints: [VNHumanBodyPoseObservation.JointName: SwingJoint] = [:]
        if let obs = request.results?.first,
           let recognized = try? obs.recognizedPoints(.all) {
            for (name, pt) in recognized where pt.confidence > 0.1 {
                joints[name] = SwingJoint(point: pt.location, confidence: Double(pt.confidence))
            }
        }
        let frame = SwingPoseFrame(index: 0, time: now, joints: joints)
        Task { @MainActor in
            self.handlePose(frame: frame, at: now)
        }
    }
}

// Throttle timestamp for the live pose stream (nonisolated context).
private nonisolated(unsafe) var _lastLivePose: TimeInterval = 0

// MARK: - Recording delegate

extension SwingStudioController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        Task { @MainActor in
            if let error {
                self.state = .failed(error.localizedDescription)
                return
            }
            self.state = .saving
            self.announce("Got it. Analyzing.")
            self.onClipReady?(outputFileURL)
            // Ready for the next take.
            self.resetMachine()
            self.state = self.source == .backGuided ? .waitingForAddress : .framing
        }
    }
}
