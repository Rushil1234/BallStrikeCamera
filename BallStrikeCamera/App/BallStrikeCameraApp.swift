import SwiftUI
import CoreNFC

@main
struct BallStrikeCameraApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = AuthSessionStore()
    @StateObject private var camera  = CameraController()

    init() {
        // Install crash/error reporting first so early failures are captured.
        // Reads an optional Sentry DSN from Secrets.plist (`SentryDSN`); nil = first-party only.
        CrashReporter.shared.configure(dsn: CrashReporter.secretsDSN())
        WatchConnectivityBridge.shared.activate()
        // Touch the singleton so CBCentralManager is created and begins scanning
        // as soon as Bluetooth is available — before any camera screen opens.
        _ = RFIDHubManager.shared

        #if DEBUG
        // Coach clip harness (simulator): analyze real user-supplied videos with the
        // EXACT production pipeline and write annotated stills back next to them.
        //   TC_SWING_CLIPS=<host folder> — swing videos → phase stills + skeleton + trail
        //   TC_GRIP_CLIPS=<host folder>  — grip videos  → shaft/hand detection frames
        if let swingDir = ProcessInfo.processInfo.environment["TC_SWING_CLIPS"] {
            Task.detached(priority: .userInitiated) {
                await CoachClipHarness.runSwingClips(dir: swingDir)
                exit(0)
            }
        }
        if let gripDir = ProcessInfo.processInfo.environment["TC_GRIP_CLIPS"] {
            Task.detached(priority: .userInitiated) {
                await CoachClipHarness.runGripClips(dir: gripDir)
                exit(0)
            }
        }
        // Headless replay for simulator/CI: TC_REPLAY_EXPORTS=1 runs every export in
        // Documents/ShotExports + AllFramesArchive through the live-parity pipeline,
        // prints the full diagnostics, then exits. Nothing else in the app starts mattering.
        if ProcessInfo.processInfo.environment["TC_REPLAY_EXPORTS"] == "1" {
            Task.detached(priority: .userInitiated) {
                let loader = TestFrameLoader()
                let exports = loader.listAvailableExports()
                print("[Replay] headless mode — \(exports.count) export(s) found")
                for url in exports.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    do {
                        let seq = try loader.loadSequence(from: url)
                        print("\n[Replay] ================ \(seq.sourceName) (\(seq.frames.count) frames, impact=\(seq.impactFrameIndex)) ================")
                        _ = LiveParityTestRunner().run(sequence: seq)
                    } catch {
                        print("[Replay] FAILED to load \(url.lastPathComponent): \(error)")
                    }
                }
                print("\n[Replay] headless run complete — exiting")
                exit(0)
            }
        }
        #endif
    }

    // TC_OPEN_TESTER=1 (simulator/dev): boot straight into the Ball Tracking Tester so saved
    // shots can be replayed with overlays without navigating the app shell.
    private var openTesterDirectly: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["TC_OPEN_TESTER"] == "1"
        #else
        return false
        #endif
    }

    // TC_SNAPSHOT_VIEW=<name> (simulator/dev): boot straight into a single view for
    // visual verification screenshots — no auth, no navigation.
    private var snapshotViewName: String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["TC_SNAPSHOT_VIEW"]
        #else
        return nil
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if let snapshotViewName {
                #if DEBUG
                DebugSnapshotHarness(name: snapshotViewName)
                #endif
            } else if openTesterDirectly {
                #if DEBUG
                BallTrackingTestView(onDismiss: {})
                #endif
            } else {
            ContentView()
                .environmentObject(session)
                .environmentObject(camera)
                .task {
                    // Wire crash/error telemetry to the backend + report any prior crash.
                    CrashReporter.shared.attach(backend: session.backend)
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .background {
                        // Natural "done hitting" moment: push archived shots to Drive
                        // (verified, then freed locally) so the phone stays light.
                        GoogleDriveUploadService.shared.autoOffloadIfNeeded()
                        return
                    }
                    guard phase == .active else { return }
                    Task { await session.refreshSessionAndEntitlement() }
                }
                // Silent NFC club detection — two delivery paths:
                // 1. URL routing: truecarry://nfc/{uuid} when app is backgrounded
                .onOpenURL { url in
                    if url.scheme == "truecarry" { print("[DeepLink] onOpenURL: \(url.absoluteString)") }
                    // QR pairing: truecarry://livesim?code=XXXXXXXXX from the web sim.
                    if url.host == "livesim",
                       let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                           .queryItems?.first(where: { $0.name == "code" })?.value,
                       (6...10).contains(code.count), code.allSatisfy(\.isNumber) {
                        // State, not a fire-once notification: @Published re-emits to
                        // late subscribers, so the shell routes correctly no matter
                        // whether the URL beat the views to the party (cold start) or
                        // the tab content mounts lazily after this fires (warm scan).
                        DeepLinkRouter.shared.pendingSimCode = code
                        return
                    }
                    NFCManager.shared.handleNFCURL(url)
                }
                // 2. NSUserActivity: delivered directly to foreground app with zero UI
                // (requires NSUserActivityTypes in Info.plist)
                .onContinueUserActivity("com.apple.corenfc.tag") { activity in
                    print("[NFC] NSUserActivity received — records: \(activity.ndefMessagePayload.records.count)")
                    for record in activity.ndefMessagePayload.records {
                        print("[NFC] record typeNameFormat=\(record.typeNameFormat.rawValue)")
                        if let url = record.wellKnownTypeURIPayload() {
                            print("[NFC] URI: \(url.absoluteString)")
                            NFCManager.shared.handleNFCURL(url)
                            return
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
import AVFoundation
import Vision

// MARK: - Coach clip harness (ground-truth testing on real footage)
//
// Runs the PRODUCTION analysis/detection code on videos the user drops in a host folder,
// and writes annotated PNGs back — so "is the impact still the real impact?" and "does the
// shaft lock onto the actual club?" are answered by looking, not guessing.
enum CoachClipHarness {

    private static let videoExts = ["mov", "mp4", "m4v"]

    private static func clips(in dir: String) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { videoExts.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .map { URL(fileURLWithPath: dir).appendingPathComponent($0) }
    }

    private static func outDir(for dir: String) -> String {
        let out = (dir as NSString).appendingPathComponent("_analysis")
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        return out
    }

    // MARK: Swing clips → phase stills + skeleton + hand trail + metric report

    static func runSwingClips(dir: String) async {
        let urls = clips(in: dir)
        let out = outDir(for: dir)
        print("[CoachHarness] \(urls.count) swing clip(s) in \(dir)")
        for url in urls { await analyzeSwingClip(url: url, outDir: out) }
        print("[CoachHarness] swing run complete → \(out)")
    }

    private static func analyzeSwingClip(url: URL, outDir: String) async {
        let base = url.deletingPathExtension().lastPathComponent
        do {
            let (frames, fps) = try await SwingPoseExtractor.extract(videoURL: url)
            print("\n[CoachHarness] ── \(base): \(frames.count) pose frames @ \(String(format: "%.1f", fps))fps")
            guard var phases = SwingPhaseSegmenter.segment(frames: frames, fps: fps) else {
                // Show WHY: pose coverage stats + a few annotated sample frames of
                // whatever Vision did see.
                let withBody = frames.filter { $0.joints.count >= 6 }.count
                let withWrist = frames.filter {
                    $0.joint(.leftWrist) != nil || $0.joint(.rightWrist) != nil
                }.count
                print("[CoachHarness]   NO SWING SEGMENTED — frames with a body: \(withBody)/\(frames.count), with a wrist: \(withWrist)")
                let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                gen.appliesPreferredTrackTransform = true
                gen.requestedTimeToleranceBefore = .zero
                gen.requestedTimeToleranceAfter = .zero
                let n5 = frames.count / 5
                let sampleIdxs: [Int] = [n5, 2 * n5, 3 * n5, 4 * n5]
                for (n, idx) in sampleIdxs.enumerated() {
                    let f = frames[idx]
                    guard let cg = try? gen.copyCGImage(at: CMTime(seconds: f.time, preferredTimescale: 600),
                                                        actualTime: nil) else { continue }
                    let img = annotateSwing(cg: cg, pose: SwingSkeleton.stored(from: f, at: idx),
                                            trail: nil,
                                            label: "NO SEGMENT  t=\(String(format: "%.2f", f.time))s  joints=\(f.joints.count)")
                    let dest = URL(fileURLWithPath: outDir)
                        .appendingPathComponent("\(base)_nosegment_\(n).png")
                    try? img.pngData()?.write(to: dest)
                }
                return
            }
            phases.times = [phases.address, phases.takeaway, phases.top, phases.impact, phases.finish]
                .map { frames[min($0, frames.count - 1)].time }

            for (i, item) in phases.labelled.enumerated() {
                print(String(format: "[CoachHarness]   %-9@ frame %4d   t=%6.3fs",
                             item.label as NSString, item.frame, phases.seconds(forPhaseAt: i)))
            }
            if let tempo = phases.tempoRatio {
                print(String(format: "[CoachHarness]   tempo %.2f:1  (back %.2fs, down %.2fs)",
                             tempo, phases.backswingSeconds, phases.downswingSeconds))
            }
            for view in [SwingViewAngle.faceOn, .downTheLine] {
                let metrics = SwingMetricsEngine.compute(frames: frames, phases: phases,
                                                         skill: .intermediate, isLefty: false,
                                                         viewAngle: view)
                let line = metrics.map {
                    "\($0.kind.rawValue)=\(String(format: "%.1f", $0.value))\($0.inBand ? "" : " ⚠︎")"
                }.joined(separator: "   ")
                print("[CoachHarness]   [\(view.displayName)] \(line)")
            }

            let trailRange = phases.address...min(phases.finish, frames.count - 1)
            let trail: [CGPoint] = trailRange.compactMap {
                frames[$0].mid(.leftWrist, .rightWrist)
                    ?? frames[$0].joint(.leftWrist) ?? frames[$0].joint(.rightWrist)
            }

            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
            for (i, item) in phases.labelled.enumerated() {
                let t = phases.seconds(forPhaseAt: i)
                guard let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600),
                                                    actualTime: nil) else { continue }
                let pose = SwingSkeleton.stored(from: frames[min(item.frame, frames.count - 1)],
                                                at: item.frame)
                let img = annotateSwing(cg: cg, pose: pose, trail: i >= 3 ? trail : nil,
                                        label: "\(i + 1) \(item.label)  t=\(String(format: "%.2f", t))s")
                let dest = URL(fileURLWithPath: outDir).appendingPathComponent("\(base)_\(i + 1)_\(item.label).png")
                try? img.pngData()?.write(to: dest)
            }
            print("[CoachHarness]   stills → \(outDir)/\(base)_*.png")
        } catch {
            print("[CoachHarness]   FAILED: \(error.localizedDescription)")
        }
    }

    /// Skeleton + trail drawn straight into video-pixel space — poses are normalized to
    /// the (upright) frame, so any misalignment visible here is a real pipeline error.
    private static func annotateSwing(cg: CGImage, pose: StoredPose,
                                      trail: [CGPoint]?, label: String) -> UIImage {
        let size = CGSize(width: cg.width, height: cg.height)
        return UIGraphicsImageRenderer(size: size).image { rc in
            let c = rc.cgContext
            UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
            func P(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: x * size.width, y: (1 - y) * size.height)
            }
            let lw = max(3, size.width / 240)
            c.setLineCap(.round); c.setLineJoin(.round)

            if let trail, trail.count > 3 {
                c.setStrokeColor(UIColor.cyan.withAlphaComponent(0.8).cgColor)
                c.setLineWidth(lw * 0.75)
                c.beginPath()
                c.move(to: P(Double(trail[0].x), Double(trail[0].y)))
                for p in trail.dropFirst() { c.addLine(to: P(Double(p.x), Double(p.y))) }
                c.strokePath()
            }

            func joint(_ i: Int) -> CGPoint? {
                guard i < pose.points.count, pose.points[i][2] > 0.25 else { return nil }
                return P(pose.points[i][0], pose.points[i][1])
            }
            for (a, b) in SwingSkeleton.bones {
                guard let pa = joint(a), let pb = joint(b) else { continue }
                c.setStrokeColor(UIColor.systemGreen.withAlphaComponent(0.9).cgColor)
                c.setLineWidth(lw)
                c.beginPath(); c.move(to: pa); c.addLine(to: pb); c.strokePath()
            }
            for i in pose.points.indices {
                guard let p = joint(i) else { continue }
                c.setFillColor(UIColor.white.cgColor)
                c.fillEllipse(in: CGRect(x: p.x - lw, y: p.y - lw, width: lw * 2, height: lw * 2))
            }
            NSString(string: label).draw(at: CGPoint(x: 24, y: 24), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: max(30, size.width / 20)),
                .foregroundColor: UIColor.yellow
            ])
        }
    }

    // MARK: Grip clips → shaft + hand detection frames + verify timeline

    static func runGripClips(dir: String) async {
        let urls = clips(in: dir)
        let out = outDir(for: dir)
        print("[CoachHarness] \(urls.count) grip clip(s) in \(dir)")
        for url in urls { await analyzeGripClip(url: url, outDir: out) }
        print("[CoachHarness] grip run complete → \(out)")
    }

    private static func analyzeGripClip(url: URL, outDir: String) async {
        let base = url.deletingPathExtension().lastPathComponent
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else {
            print("[CoachHarness] \(base): unreadable"); return
        }
        print("\n[CoachHarness] ── \(base): \(String(format: "%.1f", duration))s")
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero

        var holdStart: Double? = nil
        var verifiedAt: Double? = nil
        var lastShaft: (butt: CGPoint, tip: CGPoint)? = nil
        var frameIdx = 0
        for t in stride(from: 0.0, to: duration, by: 0.3) {
            guard let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600),
                                                actualTime: nil) else { continue }
            let aspect = CGFloat(cg.width) / CGFloat(cg.height)
            func aspAdj(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }

            let handReq = VNDetectHumanHandPoseRequest()
            handReq.maximumHandCount = 2
            let contourReq = VNDetectContoursRequest()
            contourReq.maximumImageDimension = 512
            contourReq.contrastAdjustment = 1.6
            try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([handReq, contourReq])

            var hands: [CGPoint] = []
            var spans: [CGFloat] = []
            for obs in handReq.results ?? [] {
                guard let wrist = try? obs.recognizedPoint(.wrist), wrist.confidence > 0.3 else { continue }
                var center = wrist.location
                if let mcp = try? obs.recognizedPoint(.middleMCP), mcp.confidence > 0.3 {
                    center = CGPoint(x: (center.x + mcp.location.x) / 2,
                                     y: (center.y + mcp.location.y) / 2)
                    let w = aspAdj(wrist.location), k = aspAdj(mcp.location)
                    spans.append(hypot(w.x - k.x, w.y - k.y))
                }
                hands.append(center)
            }
            let handsMid: CGPoint? = hands.isEmpty ? nil
                : CGPoint(x: hands.map(\.x).reduce(0, +) / CGFloat(hands.count),
                          y: hands.map(\.y).reduce(0, +) / CGFloat(hands.count))
            if let contours = contourReq.results?.first,
               let cand = GripCheckController.bestShaftCandidate(in: contours, aspect: aspect,
                                                                 near: handsMid) {
                lastShaft = cand
            }

            // Same verify math as GripCheckController (span-scaled thresholds).
            let span = spans.isEmpty ? 0.05 : spans.reduce(0, +) / CGFloat(spans.count)
            var stacked = false
            var onClub = false
            if hands.count >= 2 {
                let a = aspAdj(hands[0]), b = aspAdj(hands[1])
                stacked = hypot(a.x - b.x, a.y - b.y) < min(max(1.9 * span, 0.05), 0.13)
            }
            if let s = lastShaft, hands.count >= 2 {
                let a = aspAdj(s.butt), b = aspAdj(s.tip)
                let thresh = min(max(1.1 * span, 0.03), 0.08)
                onClub = hands.allSatisfy { h in
                    let ap = aspAdj(h)
                    let abx = b.x - a.x, aby = b.y - a.y
                    let len2 = max(abx * abx + aby * aby, 1e-6)
                    let tt = max(0, min(1, ((ap.x - a.x) * abx + (ap.y - a.y) * aby) / len2))
                    return hypot(ap.x - (a.x + abx * tt), ap.y - (a.y + aby * tt)) < thresh
                }
            }
            if lastShaft != nil && stacked && onClub {
                if holdStart == nil { holdStart = t }
                if verifiedAt == nil, t - holdStart! >= 1.5 { verifiedAt = t }
            } else {
                holdStart = nil
            }

            let status = "t=\(String(format: "%4.1f", t))s  club=\(lastShaft != nil ? "LOCK" : "—")  hands=\(hands.count)  stacked=\(stacked ? "Y" : "n")  onClub=\(onClub ? "Y" : "n")\(verifiedAt != nil ? "  ✓VERIFIED" : "")"
            print("[CoachHarness]   \(status)")

            let img = annotateGrip(cg: cg, shaft: lastShaft, hands: hands, status: status)
            let dest = URL(fileURLWithPath: outDir)
                .appendingPathComponent(String(format: "%@_%03d.png", base, frameIdx))
            try? img.pngData()?.write(to: dest)
            frameIdx += 1
        }
        if let verifiedAt {
            print(String(format: "[CoachHarness]   VERIFIED at %.1fs", verifiedAt))
        } else {
            print("[CoachHarness]   never verified — check the frames for why")
        }
        print("[CoachHarness]   frames → \(outDir)/\(base)_NNN.png")
    }

    private static func annotateGrip(cg: CGImage, shaft: (butt: CGPoint, tip: CGPoint)?,
                                     hands: [CGPoint], status: String) -> UIImage {
        let size = CGSize(width: cg.width, height: cg.height)
        return UIGraphicsImageRenderer(size: size).image { rc in
            let c = rc.cgContext
            UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
            func P(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height) }
            let lw = max(3, size.width / 240)
            c.setLineCap(.round)

            if let shaft {
                let b = P(shaft.butt), t = P(shaft.tip)
                c.setStrokeColor(UIColor.systemGreen.withAlphaComponent(0.85).cgColor)
                c.setLineWidth(lw)
                c.beginPath(); c.move(to: b); c.addLine(to: t); c.strokePath()
                c.setStrokeColor(UIColor.systemYellow.cgColor)
                c.setLineWidth(lw * 0.8)
                c.strokeEllipse(in: CGRect(x: b.x - lw * 4, y: b.y - lw * 4,
                                           width: lw * 8, height: lw * 8))
            }
            for h in hands {
                let p = P(h)
                c.setStrokeColor(UIColor.white.cgColor)
                c.setLineWidth(lw * 0.8)
                c.strokeEllipse(in: CGRect(x: p.x - lw * 5, y: p.y - lw * 5,
                                           width: lw * 10, height: lw * 10))
            }
            NSString(string: status).draw(at: CGPoint(x: 24, y: 24), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: max(24, size.width / 30)),
                .foregroundColor: UIColor.yellow
            ])
        }
    }
}

/// Boots directly into one view for screenshot verification (TC_SNAPSHOT_VIEW=<name>).
private struct DebugSnapshotHarness: View {
    let name: String

    var body: some View {
        switch name {
        case "gripdemo":
            VStack {
                GripHandsDemo()
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TCTheme.background)
        case "gripdiagram":
            ZStack {
                TrueCarryBackground().ignoresSafeArea()
                ScrollView {
                    GripDiagram(variant: .neutral)
                        .padding(20)
                }
            }
        case "dispersion":
            // Noah's bug scenario: one wild 100yd-right shot among normal ones,
            // plus a long-hitter set — axis labels must stay ≤6 per side.
            VStack(spacing: 16) {
                TCRangeFinderDispersion(shots: [
                    .init(carry: 230, lateral: 8), .init(carry: 245, lateral: -12),
                    .init(carry: 238, lateral: 15), .init(carry: 250, lateral: -5),
                    .init(carry: 242, lateral: 3), .init(carry: 55, lateral: 100),
                    .init(carry: 228, lateral: 22), .init(carry: 251, lateral: -18),
                ]).frame(height: 300)
                TCRangeFinderDispersion(shots: [
                    .init(carry: 330, lateral: 12), .init(carry: 345, lateral: -20),
                    .init(carry: 355, lateral: 25), .init(carry: 310, lateral: -8),
                    .init(carry: 362, lateral: 5),
                ]).frame(height: 300)
            }
            .padding(16)
            .background(Color.black)
        case "coachhome":
            NavigationStack {
                LessonsHomeView()
                    .environmentObject(AuthSessionStore())
            }
        case "shotedit":
            // Hole shots editor: club menus, add-missed-shot form.
            shotEditSample(addOpen: false)
        case "shoteditadd":
            shotEditSample(addOpen: true)
        case "shotmapedit":
            // History map editor: numbered shot pins on the hole, tap/move/add on the image.
            shotMapEditSample
        default:
            Text("Unknown snapshot view: \(name)")
        }
    }

    private var shotMapEditSample: some View {
        let uid = UUID()
        // Pebble-adjacent coastline so the satellite view has real turf to show.
        let tee   = Coordinate(latitude: 36.5690, longitude: -121.9490)
        let mid   = Coordinate(latitude: 36.5706, longitude: -121.9477)
        let edge  = Coordinate(latitude: 36.5718, longitude: -121.9463)
        let green = Coordinate(latitude: 36.5720, longitude: -121.9460)
        var gh = GolfHole(number: 7, par: 4)
        gh.teeCoordinate = tee
        gh.greenCenterCoordinate = green
        gh.pathCoordinates = [tee, mid, green]
        func shot(_ idx: Int, _ s: Coordinate, _ e: Coordinate, _ club: String,
                  _ cat: ShotClub.ClubCategory) -> TrackedShot {
            var t = TrackedShot(roundId: UUID(), holeNumber: 7, shotIndex: idx, userId: uid,
                                startCoordinate: s, endCoordinate: e,
                                club: ShotClub(clubId: nil, name: club, category: cat))
            t.recomputeDistance()
            return t
        }
        var round = CourseRound(userId: uid, courseId: "sample", courseName: "Sample Links",
                                teeBoxName: "White")
        round.holes = [RoundHole(holeNumber: 7, par: 4, score: 5, putts: 2, trackedShots: [
            shot(1, tee, mid, "Driver", .driver),
            shot(2, mid, edge, "7 Iron", .iron),
            shot(3, edge, green, "Putter", .putter),
        ])]
        let clubs = [
            UserClub(userId: uid, name: "Driver", type: .driver, expectedCarryYards: 250, expectedTotalYards: 270),
            UserClub(userId: uid, name: "7 Iron", type: .iron, expectedCarryYards: 160, expectedTotalYards: 168),
            UserClub(userId: uid, name: "Putter", type: .putter, expectedCarryYards: 0, expectedTotalYards: 0),
        ]
        return ShotMapEditHarness(round: round, clubs: clubs, hole: gh)
    }

    private struct ShotMapEditHarness: View {
        @State var round: CourseRound
        let clubs: [UserClub]
        let hole: GolfHole
        var body: some View {
            RoundHoleMapEditSheet(round: $round, holeNumber: 7, clubs: clubs,
                                  hole: hole, teeBoxName: "White")
        }
    }

    private func shotEditSample(addOpen: Bool) -> some View {
        let uid = UUID(), rid = UUID()
        let tee   = Coordinate(latitude: 37.0000, longitude: -122.0000)
        let mid   = Coordinate(latitude: 37.0020, longitude: -122.0000)
        let green = Coordinate(latitude: 37.0036, longitude: -121.9990)
        func shot(_ idx: Int, _ s: Coordinate, _ e: Coordinate, _ club: String, _ cat: ShotClub.ClubCategory, _ lie: ShotLie) -> TrackedShot {
            var t = TrackedShot(roundId: rid, holeNumber: 7, shotIndex: idx, userId: uid,
                                startCoordinate: s, endCoordinate: e,
                                club: ShotClub(clubId: nil, name: club, category: cat), lie: lie)
            t.recomputeDistance()
            return t
        }
        let clubs = [
            UserClub(userId: uid, name: "Driver", type: .driver, expectedCarryYards: 250, expectedTotalYards: 270),
            UserClub(userId: uid, name: "3 Wood", type: .fairwayWood, expectedCarryYards: 225, expectedTotalYards: 240),
            UserClub(userId: uid, name: "7 Iron", type: .iron, expectedCarryYards: 160, expectedTotalYards: 168),
            UserClub(userId: uid, name: "Pitching Wedge", type: .wedge, expectedCarryYards: 115, expectedTotalYards: 118),
        ]
        return HoleShotsEditSheet(
            holeNumber: 7, par: 4, score: 5,
            shots: [
                // Forgot to log the tee shot: shot "1" was really the approach, so its
                // origin sits 250 yds down the fairway — the add-form's tee slot has span.
                shot(1, mid, green, "7 Iron", .iron, .fairway),
                shot(2, green, green, "Pitching Wedge", .wedge, .green),
            ],
            clubs: clubs,
            teeCoordinate: tee,
            greenCoordinate: green,
            onDelete: { _ in },
            onChangeClub: { _, _ in },
            onAddShot: { _, _, _, _ in },
            startWithAddForm: addOpen
        )
    }
}
#endif
