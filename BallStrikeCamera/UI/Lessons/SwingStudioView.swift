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
    @State private var mirrorMode = false
    @State private var viewAngle: SwingViewAngle = .faceOn

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreviewView(session: studio.session)
                .ignoresSafeArea()

            // Mirror-mode live skeleton dots
            if mirrorMode {
                GeometryReader { geo in
                    ForEach(Array(studio.liveJoints.enumerated()), id: \.offset) { _, p in
                        Circle()
                            .fill(TCTheme.sage.opacity(0.9))
                            .frame(width: 8, height: 8)
                            .position(x: p.x * geo.size.width,
                                      y: (1 - p.y) * geo.size.height)
                    }
                }
                .allowsHitTesting(false)
            }

            VStack {
                topBar
                Spacer()
                statusPill
                setupHint
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
    }

    private func startStudio() {
        studio.start(source: mirrorMode ? .frontMirror : .backGuided) { clipURL in
            ingest(clipURL: clipURL)
        }
    }

    private var topBar: some View {
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
                viewAngle = viewAngle == .faceOn ? .downTheLine : .faceOn
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .bold))
                    Text("Studio · \(viewAngle.displayName)")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.55)))
            }
            Spacer()
            Button {
                mirrorMode.toggle()
                studio.stop()
                startStudio()
            } label: {
                Image(systemName: mirrorMode ? "camera.rotate.fill" : "camera.rotate")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(studio.state == .recording ? Color.red : (studio.bodyInFrame ? TCTheme.sage : TCTheme.gold))
                .frame(width: 9, height: 9)
            Text(statusText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .padding(.bottom, 4)
    }

    /// Per-angle tripod setup guidance, shown until a body is framed.
    @ViewBuilder
    private var setupHint: some View {
        if !studio.bodyInFrame, analyzing == 0 {
            Text(viewAngle == .faceOn
                 ? "Tripod to your SIDE, chest-height, phone upright — camera sees your whole body and the club."
                 : "Tripod 6 FEET BEHIND you on the target line, camera at hand height, looking at the target.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.55)))
                .padding(.horizontal, 30)
                .padding(.bottom, 6)
        }
    }

    private var statusText: String {
        if analyzing > 0 { return "Analyzing swing…" }
        switch studio.state {
        case .idle, .starting:     return "Starting camera…"
        case .framing:             return "Step back — whole body in frame"
        case .waitingForAddress:   return "Take your address and hold still"
        case .recording:           return "Recording — swing away"
        case .saving:              return "Saving clip…"
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
            player = AVPlayer(url: library.videoURL(for: swing))
        }
    }

    private var videoSection: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        if showSkeleton, let pose = currentPose {
                            GeometryReader { geo in
                                SkeletonOverlay(pose: pose, size: geo.size)
                            }
                            .allowsHitTesting(false)
                        }
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { showSkeleton.toggle() } label: {
                Image(systemName: showSkeleton ? "figure.walk.circle.fill" : "figure.walk.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .padding(8)
            }
        }
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
                    ForEach(phases.labelled, id: \.label) { item in
                        Button {
                            selectedPhase = item.label
                            let t = Double(item.frame) / max(phases.frameRate, 1)
                            player?.pause()
                            player?.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                                         toleranceBefore: .zero, toleranceAfter: .zero)
                        } label: {
                            Text(item.label)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(selectedPhase == item.label ? TCTheme.onPrimary : TCTheme.textMuted)
                                .padding(.horizontal, 12).padding(.vertical, 7)
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
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(verdict.good ? TCTheme.sage : Color(red: 0.9, green: 0.35, blue: 0.3))
                        Text(verdict.label)
                            .font(.system(size: 12, weight: .bold))
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
                        VStack(spacing: 2) {
                            Text("\(val)")
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundColor(TCTheme.textPrimary)
                            Text(cat.uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(TCTheme.textUltraMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(TCTheme.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                if !swing.headline.isEmpty {
                    Label(swing.headline, systemImage: "hand.thumbsup.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TCTheme.sage)
                }
                if !swing.focusPoint.isEmpty {
                    Label(swing.focusPoint, systemImage: "target")
                        .font(.system(size: 13))
                        .foregroundColor(TCTheme.textPrimary)
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
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(TCTheme.textPrimary)
                        Spacer()
                        Text(m.kind == .tempoRatio
                             ? String(format: "%.1f%@", m.value, m.kind.unit)
                             : "\(Int(m.value))\(m.kind.unit)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(m.inBand ? TCTheme.sage : TCTheme.gold)
                        Text(m.kind == .tempoRatio
                             ? String(format: "target %.1f–%.1f", m.targetLow, m.targetHigh)
                             : "target \(Int(m.targetLow))–\(Int(m.targetHigh))\(m.kind.unit)")
                            .font(.system(size: 10))
                            .foregroundColor(TCTheme.textUltraMuted)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
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
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(TCTheme.gold)
                        Text(fault.explanation)
                            .font(.system(size: 13))
                            .foregroundColor(TCTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Label(fault.drill, systemImage: "figure.golf")
                            .font(.system(size: 12, weight: .semibold))
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

/// Draws a stored key pose over the video (Vision coords: origin bottom-left, y up).
private struct SkeletonOverlay: View {
    let pose: StoredPose
    let size: CGSize

    var body: some View {
        Canvas { ctx, _ in
            func pt(_ i: Int) -> CGPoint? {
                guard i < pose.points.count, pose.points[i][2] > 0.25 else { return nil }
                return CGPoint(x: pose.points[i][0] * size.width,
                               y: (1 - pose.points[i][1]) * size.height)
            }
            for (a, b) in SwingSkeleton.bones {
                guard let pa = pt(a), let pb = pt(b) else { continue }
                var line = Path()
                line.move(to: pa); line.addLine(to: pb)
                ctx.stroke(line, with: .color(TCTheme.sage.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            for i in pose.points.indices {
                guard let p = pt(i) else { continue }
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                         with: .color(.white))
            }
        }
    }
}
