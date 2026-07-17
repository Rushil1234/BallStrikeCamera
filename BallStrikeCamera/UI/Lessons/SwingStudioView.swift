import SwiftUI
import AVKit

// MARK: - TrueCarry Coach: Swing Studio (capture screen)

struct SwingStudioView: View {
    let lessonId: String?
    let requiredSwings: Int
    let onDone: () -> Void

    @EnvironmentObject var session: AuthSessionStore
    @ObservedObject private var library = LessonLibrary.shared
    @StateObject private var studio = SwingStudioController()
    @AppStorage("tc_hitting_hand") private var hitHandRaw = "R"

    @State private var takes: [SwingRecording] = []
    @State private var analyzing = 0
    // Front camera is the default: coach mode is interactive — the player sees themself,
    // the live skeleton, and the instructions all at once. Back camera is the labeled
    // "friend films you" mode.
    @State private var mirrorMode = true
    /// The just-analyzed swing — presented automatically so every swing is immediately
    /// followed by its replay + suggestions.
    @State private var reviewSwing: SwingRecording? = nil
    /// Explicit, persisted camera-angle choice — it decides which metric tracker runs,
    /// so the player picks it, sees it, and gets exactly that analysis. No auto-guessing.
    @AppStorage("tc_swing_view_angle") private var viewAngleRaw = SwingViewAngle.faceOn.rawValue

    private var viewAngle: SwingViewAngle { SwingViewAngle(rawValue: viewAngleRaw) ?? .faceOn }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreviewView(session: studio.session)
                .ignoresSafeArea()

            // Mirror-mode live skeleton (side-colored bones, Sportsbox-style).
            // Must share the preview's full-screen coordinate space AND its aspect-fill
            // mapping, or the skeleton lands beside the body.
            if mirrorMode, let pose = studio.liveSkeleton {
                GeometryReader { geo in
                    RichPoseOverlay(pose: pose, trail: nil, spineAngle: nil,
                                    videoRect: aspectFillRect(content: studio.bufferSize,
                                                              in: geo.size))
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Giant framing direction — readable from across the room, no small words.
            if !studio.bodyInFrame, analyzing == 0,
               studio.state == .framing || studio.state == .waitingForAddress {
                FramingGuideOverlay(hint: studio.framingHint)
                    .allowsHitTesting(false)
            }

            VStack {
                topBar
                Spacer()
                statusPill
                takesRow
                bottomBar
            }
        }
        .statusBarHidden(true)
        .onAppear {
            OrientationManager.shared.lockPortrait()
            startStudio()
        }
        .onDisappear {
            studio.stop()
            OrientationManager.shared.unlockAllButUpsideDown()
        }
        // Post-swing replay + suggestions, automatically. Dismissing returns to the studio
        // ready for the next swing (the controller re-arms itself after each clip).
        .fullScreenCover(item: $reviewSwing) { swing in
            NavigationStack {
                SwingReplayView(swing: swing)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                reviewSwing = nil
                            } label: {
                                Text("Next Swing")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(TCTheme.sage)
                            }
                        }
                    }
            }
            .tcAppearance()
        }
        .tcGuide(.swingStudio, showButton: false)
    }

    private func startStudio() {
        studio.start(source: mirrorMode ? .frontMirror : .backGuided) { clipURL in
            ingest(clipURL: clipURL)
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    studio.stop()
                    onDone()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .tcShowGuide, object: GuideScreen.swingStudio.rawValue)
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
            }
            // Two explicit choices, spelled out: which ANGLE the analysis assumes, and
            // which CAMERA is filming. The picked angle is exactly the tracker that runs.
            HStack(spacing: 10) {
                segmentedPill(
                    options: [("Face-On", "person.fill"), ("Down-Line", "figure.golf")],
                    selected: viewAngle == .faceOn ? 0 : 1
                ) { idx in
                    let newAngle = idx == 0 ? SwingViewAngle.faceOn : .downTheLine
                    viewAngleRaw = newAngle.rawValue
                    // Down-the-line: the phone sits BEHIND you (can't watch the screen
                    // anyway) and the clubhead tracker wants 240fps — auto-switch to the
                    // voice-guided high-speed back camera.
                    if newAngle == .downTheLine, mirrorMode {
                        mirrorMode = false
                        studio.stop()
                        startStudio()
                    }
                }
                segmentedPill(
                    options: [("Selfie", "iphone"), ("Friend Films", "camera.fill")],
                    selected: mirrorMode ? 0 : 1
                ) { idx in
                    let wantMirror = idx == 0
                    guard wantMirror != mirrorMode else { return }
                    mirrorMode = wantMirror
                    studio.stop()
                    startStudio()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func segmentedPill(options: [(String, String)], selected: Int,
                               action: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 3) {
            ForEach(options.indices, id: \.self) { i in
                Button { action(i) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: options[i].1)
                            .font(.system(size: 11, weight: .bold))
                        Text(options[i].0)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(i == selected ? .black : .white.opacity(0.85))
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(Capsule().fill(i == selected ? Color.white : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }

    // Big banner, not a pill — the player reads this from several feet away.
    private var statusPill: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(studio.state == .recording ? Color.red : (studio.bodyInFrame ? TCTheme.sage : TCTheme.gold))
                .frame(width: 14, height: 14)
            Text(statusText)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.65)))
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var statusText: String {
        if analyzing > 0 { return "Analyzing your swing…" }
        switch studio.state {
        case .idle, .starting:     return "Starting camera…"
        case .framing:             return "Step back until your WHOLE body is in frame"
        case .waitingForAddress:   return "Get set up and hold still — recording starts by itself"
        case .recording:           return "Recording — swing when ready (club optional)"
        case .saving:              return "Saving…"
        case .failed(let msg):     return msg
        }
    }

    private var takesRow: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(requiredSwings, takes.count), id: \.self) { i in
                ZStack {
                    Circle()
                        .fill(i < takes.count ? TCTheme.sage : Color.black.opacity(0.5))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                    if i < takes.count {
                        if let s = takes[i].overallScore {
                            Text("\(s)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: takes[i].analyzed ? "checkmark" : "hourglass")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    } else {
                        Text("\(i + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(.bottom, 10)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if mirrorMode {
                Button { studio.manualToggleRecord() } label: {
                    ZStack {
                        Circle().strokeBorder(Color.white, lineWidth: 3).frame(width: 64, height: 64)
                        RoundedRectangle(cornerRadius: studio.state == .recording ? 5 : 26)
                            .fill(Color.red)
                            .frame(width: studio.state == .recording ? 26 : 52,
                                   height: studio.state == .recording ? 26 : 52)
                    }
                }
            }
            if takes.count >= requiredSwings && analyzing == 0 {
                Button {
                    studio.stop()
                    onDone()
                } label: {
                    Text("Done — \(takes.count) swing\(takes.count == 1 ? "" : "s") captured")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 22).padding(.vertical, 13)
                        .background(Capsule().fill(TCTheme.gold))
                }
            }
        }
        .padding(.bottom, 26)
    }

    // MARK: Clip ingest → analyze → persist

    private func ingest(clipURL: URL) {
        guard let uid = session.currentUser?.id else { return }
        let dir = LessonLibrary.swingsDir(userId: uid)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "swing_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 100...999))"
        let dest = dir.appendingPathComponent("\(name).mov")
        try? FileManager.default.moveItem(at: clipURL, to: dest)

        var rec = SwingRecording(
            userId: uid,
            viewAngle: viewAngle,
            source: mirrorMode ? .frontMirror : .backGuided,
            fps: studio.captureFPS,
            videoPath: "\(name).mov",
            lessonId: lessonId
        )
        let thumb = dir.appendingPathComponent("\(name).jpg")
        SwingAnalyzer.makeThumbnail(videoURL: dest, to: thumb)
        rec.thumbnailPath = "\(name).jpg"
        library.addSwing(rec)
        takes.append(rec)
        analyzing += 1

        let skill = library.profile?.skillLevel ?? .beginner
        let lefty = hitHandRaw == "L"
        let faults = library.faults
        Task {
            let analyzed = await SwingAnalyzer.analyze(recording: rec, videoURL: dest,
                                                       skill: skill, isLefty: lefty, faults: faults)
            await MainActor.run {
                library.updateSwing(analyzed)
                if let i = takes.firstIndex(where: { $0.id == analyzed.id }) { takes[i] = analyzed }
                analyzing -= 1
                // Every swing is immediately followed by its replay + suggestions — the
                // feedback loop IS the product; nobody should have to dig for it.
                if analyzed.analyzed {
                    reviewSwing = analyzed
                }
            }
        }
    }
}

// MARK: - Swing replay (video + phases + skeleton + scores)

struct SwingReplayView: View {
    let swing: SwingRecording

    @ObservedObject private var library = LessonLibrary.shared
    @State private var player: AVPlayer?
    @State private var selectedPhase: String?
    @State private var showSkeleton = true
    /// Real pixel size of the clip (transform applied) — the overlay maps poses into the
    /// video's aspect-FIT rect, not the player's frame, so skeletons sit ON the body.
    @State private var videoPixelSize = CGSize(width: 1080, height: 1920)
    /// True capture rate; high-fps clips default to slow-motion playback (240fps shown
    /// at 30fps = 8× slow — the whole point of capturing DTL at speed).
    @State private var videoFPS: Double = 30
    @State private var slowMo = true

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: TCTheme.sectionGap) {
                    videoSection
                    phaseChips
                    verdictChips
                    scoreSection
                    metricsSection
                    faultsSection
                    Spacer(minLength: 60)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 10)
            }
        }
        .navigationTitle("Swing Replay")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let url = library.videoURL(for: swing)
            player = AVPlayer(url: url)
            Task {
                let asset = AVURLAsset(url: url)
                if let track = try? await asset.loadTracks(withMediaType: .video).first,
                   let (natural, transform, fps) = try? await track.load(.naturalSize, .preferredTransform, .nominalFrameRate) {
                    let s = natural.applying(transform)
                    videoPixelSize = CGSize(width: abs(s.width), height: abs(s.height))
                    videoFPS = Double(fps)
                    applyPlaybackRate()
                }
            }
        }
    }

    private var videoSection: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        if showSkeleton {
                            GeometryReader { geo in
                                RichPoseOverlay(
                                    pose: currentPose,
                                    trail: swing.clubTrail ?? swing.handTrail,
                                    spineAngle: swing.metrics.first { $0.kind == .spineTiltAddress }?.value,
                                    videoRect: AVMakeRect(aspectRatio: videoPixelSize,
                                                          insideRect: CGRect(origin: .zero, size: geo.size)),
                                    trailLabel: swing.clubTrail != nil ? "CLUB PATH" : "HAND PATH"
                                )
                            }
                            .allowsHitTesting(false)
                        }
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if let selectedPhase {
                Text(selectedPhase.uppercased())
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .padding(10)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { showSkeleton.toggle() } label: {
                Image(systemName: showSkeleton ? "figure.walk.circle.fill" : "figure.walk.circle")
                    .font(.system(size: 26))
                    .foregroundColor(.white)
                    .padding(8)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // High-fps clips play slow by default — that's why they were captured fast.
            if videoFPS >= 100 {
                Button {
                    slowMo.toggle()
                    applyPlaybackRate()
                } label: {
                    Text(slowMo ? "\(Int((videoFPS / 30).rounded()))× SLOW" : "1×")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func applyPlaybackRate() {
        let rate: Float = (slowMo && videoFPS >= 100) ? Float(30 / videoFPS) : 1
        player?.defaultRate = rate
        if let player, player.rate != 0 { player.rate = rate }
    }

    private var currentPose: StoredPose? {
        guard let selectedPhase,
              let phases = swing.phases,
              let idx = phases.labelled.firstIndex(where: { $0.label == selectedPhase }),
              idx < swing.keyPoses.count else { return nil }
        return swing.keyPoses[idx]
    }

    @ViewBuilder
    private var phaseChips: some View {
        if let phases = swing.phases {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(phases.labelled.enumerated()), id: \.element.label) { idx, item in
                        Button {
                            selectedPhase = item.label
                            // Exact stored timestamp — index ÷ nominal fps drifts on slo-mo
                            // clips and lands the still on the wrong moment.
                            let t = phases.seconds(forPhaseAt: idx)
                            player?.pause()
                            player?.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                                         toleranceBefore: .zero, toleranceAfter: .zero)
                        } label: {
                            Text(item.label)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(selectedPhase == item.label ? TCTheme.onPrimary : TCTheme.textMuted)
                                .padding(.horizontal, 15).padding(.vertical, 10)
                                .background(selectedPhase == item.label
                                            ? AnyShapeStyle(TCTheme.primaryFill)
                                            : AnyShapeStyle(TCTheme.panel))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(
                                    selectedPhase == item.label ? Color.clear : TCTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Good/bad position call-outs ("Club On Plane at Delivery" / "Club Steep") — the
    /// at-a-glance verdicts, confidence-gated so shaky measurements stay quiet.
    @ViewBuilder
    private var verdictChips: some View {
        let verdicts = swing.metrics.filter { $0.confidence >= 0.4 }
            .map { ($0.kind.verdict(for: $0), $0.kind.rawValue) }
        if !verdicts.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(verdicts, id: \.1) { verdict, _ in
                    HStack(spacing: 6) {
                        Image(systemName: verdict.good ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(verdict.good ? TCTheme.sage : Color(red: 0.9, green: 0.35, blue: 0.3))
                        Text(verdict.label)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(TCTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(TCTheme.panel)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(
                        (verdict.good ? TCTheme.sage : Color(red: 0.9, green: 0.35, blue: 0.3)).opacity(0.5), lineWidth: 1.2))
                }
            }
        }
    }

    @ViewBuilder
    private var scoreSection: some View {
        if let score = swing.overallScore {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SWING SCORE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(TCTheme.textMuted)
                            .tracking(1.4)
                        Text("\(score)")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundColor(score >= 70 ? TCTheme.sage : TCTheme.gold)
                    }
                    Spacer()
                    if let ratio = swing.phases?.tempoRatio {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("TEMPO")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(TCTheme.textMuted).tracking(1.4)
                            Text(String(format: "%.1f:1", ratio))
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundColor(TCTheme.textPrimary)
                        }
                    }
                }
                HStack(spacing: 8) {
                    ForEach(swing.categoryScores.sorted(by: { $0.key < $1.key }), id: \.key) { cat, val in
                        VStack(spacing: 3) {
                            Text("\(val)")
                                .font(.system(size: 19, weight: .bold, design: .monospaced))
                                .foregroundColor(TCTheme.textPrimary)
                            Text(cat.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(TCTheme.textUltraMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(TCTheme.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                if !swing.headline.isEmpty {
                    Label(swing.headline, systemImage: "hand.thumbsup.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TCTheme.sage)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !swing.focusPoint.isEmpty {
                    Label(swing.focusPoint, systemImage: "target")
                        .font(.system(size: 15))
                        .foregroundColor(TCTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tcCard(padding: 16)
        } else if !swing.analyzed {
            VStack(spacing: 8) {
                Text(swing.headline.isEmpty ? "Not analyzed yet" : swing.headline)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                Text(swing.focusPoint)
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .tcCard(padding: 16)
        }
    }

    @ViewBuilder
    private var metricsSection: some View {
        if !swing.metrics.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                TCSectionHeader(title: "Measurements")
                ForEach(swing.metrics) { m in
                    HStack {
                        Circle()
                            .fill(m.inBand ? TCTheme.sage : TCTheme.gold)
                            .frame(width: 8, height: 8)
                        Text(m.kind.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(TCTheme.textPrimary)
                        Spacer()
                        Text(m.kind == .tempoRatio
                             ? String(format: "%.1f%@", m.value, m.kind.unit)
                             : "\(Int(m.value))\(m.kind.unit)")
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundColor(m.inBand ? TCTheme.sage : TCTheme.gold)
                        Text(m.kind == .tempoRatio
                             ? String(format: "target %.1f–%.1f", m.targetLow, m.targetHigh)
                             : "target \(Int(m.targetLow))–\(Int(m.targetHigh))\(m.kind.unit)")
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textUltraMuted)
                            .frame(width: 110, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                }
            }
            .tcCard(padding: 14)
        }
    }

    @ViewBuilder
    private var faultsSection: some View {
        let faults = swing.faults.compactMap { library.fault($0) }
        if !faults.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                TCSectionHeader(title: "What to Work On")
                ForEach(faults) { fault in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(fault.title, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(TCTheme.gold)
                        Text(fault.explanation)
                            .font(.system(size: 15))
                            .foregroundColor(TCTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Label(fault.drill, systemImage: "figure.golf")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(TCTheme.sage)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(TCTheme.panelRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .tcCard(padding: 14)
        }
    }
}

/// The Sportsbox/SwingVision-style overlay: hand-path ribbon, side-colored bones
/// (lead side cool blue, trail side warm red, torso green), glowing joints, and an angle
/// badge — instead of bare dots.
///
/// `videoRect` is the rect the VIDEO PIXELS occupy in this view's coordinates — aspect-FIT
/// for the replay player, aspect-FILL for the live preview. Poses are normalized to the
/// video frame, so mapping through the wrong rect is exactly the "skeleton doesn't line up"
/// bug; every caller must pass the real one.
struct RichPoseOverlay: View {
    let pose: StoredPose?
    let trail: [[Double]]?
    let spineAngle: Double?
    let videoRect: CGRect
    /// What the ribbon traces — "HAND PATH" face-on, "CLUB PATH" down-the-line.
    var trailLabel: String = "HAND PATH"

    private static let leftJoints: Set<Int> = [2, 4, 6, 8, 10, 12]
    private static let rightJoints: Set<Int> = [3, 5, 7, 9, 11, 13]

    var body: some View {
        Canvas { ctx, _ in
            func toScreen(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: videoRect.minX + x * videoRect.width,
                        y: videoRect.minY + (1 - y) * videoRect.height)
            }

            // ── Hand-path ribbon (cyan→magenta), smoothed + labeled so it's clearly
            // the HANDS being traced, not a clubhead guess ──
            if let trail, trail.count > 3 {
                let pts = trail.map { toScreen($0[0], $0[1]) }
                var path = Path()
                path.move(to: pts[0])
                for i in 1..<pts.count - 1 {
                    let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2,
                                      y: (pts[i].y + pts[i + 1].y) / 2)
                    path.addQuadCurve(to: mid, control: pts[i])
                }
                path.addLine(to: pts[pts.count - 1])
                ctx.stroke(path, with: .linearGradient(
                    Gradient(colors: [Color.cyan.opacity(0.85), Color(red: 1.0, green: 0.3, blue: 0.9).opacity(0.85)]),
                    startPoint: pts.first!, endPoint: pts.last!),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                ctx.draw(Text(trailLabel)
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.cyan.opacity(0.9)),
                         at: CGPoint(x: pts[0].x, y: min(videoRect.maxY - 8, pts[0].y + 16)))
            }

            guard let pose else { return }
            func pt(_ i: Int) -> CGPoint? {
                guard i < pose.points.count, pose.points[i][2] > 0.25 else { return nil }
                return toScreen(pose.points[i][0], pose.points[i][1])
            }

            // ── Bones, colored by body side ──
            for (a, b) in SwingSkeleton.bones {
                guard let pa = pt(a), let pb = pt(b) else { continue }
                let color: Color
                if Self.leftJoints.contains(a) && Self.leftJoints.contains(b) {
                    color = Color(red: 0.35, green: 0.65, blue: 1.0)      // lead/left side
                } else if Self.rightJoints.contains(a) && Self.rightJoints.contains(b) {
                    color = Color(red: 1.0, green: 0.38, blue: 0.35)      // trail/right side
                } else {
                    color = Color(red: 0.35, green: 0.9, blue: 0.5)       // torso/head
                }
                var line = Path()
                line.move(to: pa); line.addLine(to: pb)
                ctx.stroke(line, with: .color(color.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            }

            // ── Spine line + angle badge ──
            if let hipL = pt(8), let hipR = pt(9), let shL = pt(2), let shR = pt(3) {
                let hip = CGPoint(x: (hipL.x + hipR.x)/2, y: (hipL.y + hipR.y)/2)
                let sh  = CGPoint(x: (shL.x + shR.x)/2, y: (shL.y + shR.y)/2)
                var spine = Path(); spine.move(to: hip); spine.addLine(to: sh)
                ctx.stroke(spine, with: .color(.yellow.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                if let spineAngle {
                    let label = Text("\(Int(spineAngle))°")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    ctx.draw(label, at: CGPoint(x: hip.x + 34, y: (hip.y + sh.y)/2))
                }
            }

            // ── Joints: white core + colored glow ──
            for i in pose.points.indices {
                guard let p = pt(i) else { continue }
                let glow: Color = Self.leftJoints.contains(i)
                    ? Color(red: 0.35, green: 0.65, blue: 1.0)
                    : Self.rightJoints.contains(i) ? Color(red: 1.0, green: 0.38, blue: 0.35)
                    : Color(red: 0.35, green: 0.9, blue: 0.5)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                         with: .color(glow.opacity(0.4)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                         with: .color(.white))
            }

            // ── Live angle read-outs (face-on): shoulder tilt, hip tilt, head lean ──
            // Each is a solid line through the joints + a dashed horizontal reference,
            // so the number visibly IS the angle between them.
            let angles = SwingSkeleton.angles(from: pose)
            func tiltGauge(_ a: CGPoint, _ b: CGPoint, deg: Double, name: String) {
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let half = max(hypot(b.x - a.x, b.y - a.y) / 2 + 12, 30)
                let ux = (b.x - a.x) / max(hypot(b.x - a.x, b.y - a.y), 1)
                let uy = (b.y - a.y) / max(hypot(b.x - a.x, b.y - a.y), 1)
                var line = Path()
                line.move(to: CGPoint(x: mid.x - ux * half, y: mid.y - uy * half))
                line.addLine(to: CGPoint(x: mid.x + ux * half, y: mid.y + uy * half))
                ctx.stroke(line, with: .color(.white.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
                var ref = Path()
                ref.move(to: CGPoint(x: mid.x - half, y: mid.y))
                ref.addLine(to: CGPoint(x: mid.x + half, y: mid.y))
                ctx.stroke(ref, with: .color(.white.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                ctx.draw(Text("\(name) \(abs(Int(deg.rounded())))°")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.white),
                         at: CGPoint(x: mid.x + half + 4, y: mid.y), anchor: .leading)
            }
            if let deg = angles.shoulderTilt, let l = pt(2), let r = pt(3) {
                tiltGauge(r, l, deg: deg, name: "SHLDR")
            }
            if let deg = angles.hipTilt, let l = pt(8), let r = pt(9) {
                tiltGauge(r, l, deg: deg, name: "HIP")
            }
            if let deg = angles.headLean, let nose = pt(0) {
                ctx.draw(Text("HEAD \(abs(Int(deg.rounded())))°")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.white),
                         at: CGPoint(x: nose.x, y: nose.y - 18))
            }
        }
    }
}

/// Rect a `content`-sized video occupies when aspect-FILLED into `container` (preview
/// layers crop; the overlay must crop identically).
private func aspectFillRect(content: CGSize, in container: CGSize) -> CGRect {
    guard content.width > 0, content.height > 0 else {
        return CGRect(origin: .zero, size: container)
    }
    let s = max(container.width / content.width, container.height / content.height)
    let size = CGSize(width: content.width * s, height: content.height * s)
    return CGRect(x: (container.width - size.width) / 2,
                  y: (container.height - size.height) / 2,
                  width: size.width, height: size.height)
}

/// Room-scale framing direction: one giant animated arrow + a single huge word.
struct FramingGuideOverlay: View {
    let hint: SwingStudioController.FramingHint
    @State private var pulse = false

    private var arrow: String? {
        switch hint {
        case .stepBack:  return "arrow.down.backward.and.arrow.up.forward"
        case .moveLeft:  return "arrow.left"
        case .moveRight: return "arrow.right"
        case .searching: return nil
        case .good:      return nil
        }
    }

    private var word: String {
        switch hint {
        case .stepBack:  return "STEP BACK"
        case .moveLeft:  return "MOVE LEFT"
        case .moveRight: return "MOVE RIGHT"
        case .searching: return "STAND IN VIEW"
        case .good:      return ""
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            if let arrow {
                Image(systemName: arrow)
                    .font(.system(size: 88, weight: .black))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 8)
                    .scaleEffect(pulse ? 1.12 : 0.92)
                    .offset(x: hint == .moveLeft ? (pulse ? -18 : 6)
                              : hint == .moveRight ? (pulse ? 18 : -6) : 0)
            } else {
                Image(systemName: "figure.stand")
                    .font(.system(size: 88, weight: .black))
                    .foregroundColor(.white.opacity(pulse ? 1 : 0.5))
                    .shadow(color: .black.opacity(0.6), radius: 8)
            }
            Text(word)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.7), radius: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

