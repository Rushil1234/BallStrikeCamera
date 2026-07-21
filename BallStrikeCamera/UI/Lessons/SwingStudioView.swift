import SwiftUI
import AVKit
import AudioToolbox

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
    /// Rep-based mastery: consecutive in-band swings this sitting (3 = lesson passes).
    @State private var currentStreak = 0
    @State private var showReport = false
    @State private var sessionRecorded = false
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
                streakRow
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
        .sheet(isPresented: $showReport) {
            SessionReportView(takes: takes, streak: currentStreak, cue: studio.focusCue) {
                sessionRecorded = true
                library.recordStudioSession(swingIds: takes.map(\.id),
                                            bestScore: takes.compactMap(\.overallScore).max())
                library.logJournal("session", "Studio session: \(takes.count) swings, best \(takes.compactMap(\.overallScore).max() ?? 0).")
                showReport = false
                onDone()
            }
            .tcAppearance()
        }
        .tcGuide(.swingStudio, showButton: false)
    }

    private func startStudio() {
        studio.focusCue = focusCueText()
        studio.start(source: mirrorMode ? .frontMirror : .backGuided) { clipURL in
            ingest(clipURL: clipURL)
        }
    }

    /// The ONE thought for this session — worst confident tendency, in coach words.
    private func focusCueText() -> String? {
        let cues: [String: String] = [
            "head_sway": "quiet head", "hip_slide": "turn, don't slide",
            "tempo_ratio": "smooth tempo", "lead_arm_top": "long lead arm",
            "delivery_plane": "let the club drop shallow", "takeaway_path": "one-piece takeaway",
            "early_extension": "stay in your posture", "weight_shift": "finish on the lead side",
            "stance_width": "shoulder-width base", "transition_seq": "hips start the downswing",
            "finish_balance": "hold the finish", "spine_tilt_address": "athletic posture",
        ]
        let mobility = library.profile?.limitedMobility ?? false
        // Lesson focus first, then whatever the player model says is most off.
        let candidates: [String]
        if let lessonId, let lesson = library.lesson(lessonId), !lesson.focusMetrics.isEmpty {
            candidates = lesson.focusMetrics
        } else {
            candidates = Array(library.playerModel.metricAverages.keys)
        }
        for key in candidates {
            guard let kind = SwingMetricKind(rawValue: key),
                  let avg = library.playerModel.metricAverages[key] else { continue }
            let band = SwingMetricsEngine.targetBand(kind, skill: library.effectiveSkill,
                                                     limitedMobility: mobility)
            if avg < band.0 || avg > band.1, let cue = cues[key] { return cue }
        }
        return nil
    }

    /// A rep counts when the lesson's focus metrics all land in band (or, with no
    /// lesson attached, when the overall score clears 70).
    private func isGoodRep(_ swing: SwingRecording) -> Bool {
        if let lessonId, let lesson = library.lesson(lessonId), !lesson.focusMetrics.isEmpty {
            let graded = swing.metrics.filter { lesson.focusMetrics.contains($0.kind.rawValue) }
            return !graded.isEmpty && graded.allSatisfy(\.inBand)
        }
        return (swing.overallScore ?? 0) >= 70
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    studio.stop()
                    // Walking out mid-session still counts — the sitting goes to history.
                    if lessonId == nil, !takes.isEmpty, !sessionRecorded {
                        sessionRecorded = true
                        library.recordStudioSession(swingIds: takes.map(\.id),
                                                    bestScore: takes.compactMap(\.overallScore).max())
                    }
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
        case .framing:             return "Step back for full-body analysis — or just tap record"
        case .waitingForAddress:   return "Hold still and it records itself — or tap the button"
        case .recording:           return "Recording — swing when ready (club optional)"
        case .saving:              return "Saving…"
        case .failed(let msg):     return msg
        }
    }

    /// Rep-mastery streak: three big dots — fill them in a row to pass the lesson.
    @ViewBuilder
    private var streakRow: some View {
        if lessonId != nil {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < min(currentStreak, 3) ? TCTheme.sage : Color.black.opacity(0.45))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
                }
                Text(currentStreak >= 3 ? "MASTERED" : "\(min(currentStreak, 3)) OF 3 IN A ROW")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Capsule().fill(currentStreak >= 3 ? TCTheme.sage.opacity(0.5) : Color.black.opacity(0.55)))
            .padding(.bottom, 6)
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
            // The record button is ALWAYS here, both cameras. Auto-capture is a
            // convenience on top — framing detection must never strand someone who
            // just wants to tap record and swing.
            Button { studio.manualToggleRecord() } label: {
                ZStack {
                    Circle().strokeBorder(Color.white, lineWidth: 3).frame(width: 64, height: 64)
                    RoundedRectangle(cornerRadius: studio.state == .recording ? 5 : 26)
                        .fill(Color.red)
                        .frame(width: studio.state == .recording ? 26 : 52,
                               height: studio.state == .recording ? 26 : 52)
                }
            }
            if takes.count >= requiredSwings && analyzing == 0 {
                Button {
                    studio.stop()
                    if lessonId == nil, !takes.isEmpty {
                        showReport = true       // free analysis: report card, then out
                    } else {
                        onDone()
                    }
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

        let skill = library.effectiveSkill      // auto-promoted from rolling scores
        let lefty = hitHandRaw == "L"
        let faults = library.faults
        let mobility = library.profile?.limitedMobility ?? false
        Task {
            let analyzed = await SwingAnalyzer.analyze(recording: rec, videoURL: dest,
                                                       skill: skill, isLefty: lefty,
                                                       faults: faults, limitedMobility: mobility)
            await MainActor.run {
                library.updateSwing(analyzed)
                if let i = takes.firstIndex(where: { $0.id == analyzed.id }) { takes[i] = analyzed }
                analyzing -= 1
                if analyzed.analyzed {
                    // Instant verdict from 10 feet away: tone + haptic the moment the
                    // analysis lands, then the coach reacts out loud.
                    let good = isGoodRep(analyzed)
                    AudioServicesPlaySystemSound(good ? 1057 : 1053)
                    UINotificationFeedbackGenerator().notificationOccurred(good ? .success : .warning)
                    if let lessonId {
                        currentStreak = library.recordRep(lessonId: lessonId, good: good)
                    } else {
                        currentStreak = good ? currentStreak + 1 : 0
                    }
                    if good {
                        studio.say(currentStreak >= 3 ? "That's three in a row. Mastered."
                                   : "Good rep. \(currentStreak) in a row.")
                    } else if let cue = studio.focusCue {
                        studio.say("Reset. Remember: \(cue).")
                    }
                    // Every swing is immediately followed by its replay + suggestions —
                    // the feedback loop IS the product.
                    reviewSwing = analyzed
                } else {
                    // Analysis failed. SILENCE here is the worst outcome — say so, out
                    // loud, and show the retake screen with what to fix.
                    AudioServicesPlaySystemSound(1053)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    studio.say("Couldn't read that swing. Make sure your whole body stays in the frame, then go again.")
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
    /// The player mirrors front-camera clips via preferredTransform, but the stored pose is
    /// in unmirrored Vision space — so the overlay must flip x to sit ON the body. Detected
    /// from the transform's determinant (negative = horizontally mirrored).
    @State private var videoMirrored = false
    @State private var slowMo = true
    @State private var showGhost = true
    /// nil = view default (club for down-the-line, hands face-on); user toggle overrides.
    @State private var preferClubTrail: Bool? = nil
    /// nil = per-view default (PATH down-the-line, SKELETON face-on).
    @State private var overlayMode: SwingOverlayMode? = nil
    @State private var showNoteEntry = false
    @State private var noteDraft = ""

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: TCTheme.sectionGap) {
                    oneThoughtCard
                    vsLastCard
                    videoSection
                    phaseChips
                    scoreSection
                    consistencySection
                    verdictChips
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
                    // Negative determinant = the displayed frame is horizontally mirrored
                    // (front-camera selfie recordings) → flip the pose overlay to match.
                    videoMirrored = (transform.a * transform.d - transform.b * transform.c) < 0
                    applyPlaybackRate()
                }
            }
        }
    }

    /// Coaches give ONE thought. The worst confident miss leads; everything else is
    /// below the fold.
    @ViewBuilder
    private var oneThoughtCard: some View {
        if let worst = swing.metrics.filter({ !$0.inBand && $0.confidence >= 0.4 })
            .max(by: { severity($0) < severity($1) }) {
            let verdict = worst.kind.verdict(for: worst)
            VStack(alignment: .leading, spacing: 6) {
                Text("ONE THOUGHT")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(TCTheme.gold).tracking(1.4)
                Text(verdict.label)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(TCTheme.textPrimary)
                if let fault = library.faults.first(where: { $0.metric == worst.kind.rawValue }) {
                    Text(library.currentDrill(for: fault))
                        .font(.system(size: 14))
                        .foregroundColor(TCTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tcCard(padding: 16)
        } else if swing.analyzed, let s = swing.overallScore, s >= 70 {
            Label("Everything in the window — groove THIS feel.", systemImage: "checkmark.seal.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(TCTheme.sage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tcCard(padding: 14)
        }
    }

    /// The iterate loop: THIS swing against the one before it — score delta plus the
    /// biggest metric moves, so every swing is a comparison, not an island.
    @ViewBuilder
    private var vsLastCard: some View {
        if swing.analyzed,
           let prev = library.swings
               .filter({ $0.analyzed && $0.id != swing.id && $0.viewAngle == swing.viewAngle
                         && $0.recordedAt < swing.recordedAt })
               .max(by: { $0.recordedAt < $1.recordedAt }),
           let score = swing.overallScore, let prevScore = prev.overallScore {
            let delta = score - prevScore
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("VS LAST SWING")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(TCTheme.textUltraMuted).tracking(1.2)
                    HStack(spacing: 6) {
                        Image(systemName: delta >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .foregroundColor(delta >= 0 ? TCTheme.sage : TCTheme.gold)
                        Text(delta == 0 ? "Same score" : "\(delta > 0 ? "+" : "")\(delta)")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(TCTheme.textPrimary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(metricDeltas(vs: prev).prefix(2), id: \.0) { name, better in
                        HStack(spacing: 4) {
                            Text(name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(TCTheme.textMuted)
                            Image(systemName: better ? "arrow.up" : "arrow.down")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(better ? TCTheme.sage : TCTheme.gold)
                        }
                    }
                }
            }
            .tcCard(padding: 14)
        }
    }

    /// Metric moves vs the previous swing, biggest change first (true = improved).
    private func metricDeltas(vs prev: SwingRecording) -> [(String, Bool)] {
        var out: [(name: String, better: Bool, magnitude: Double)] = []
        for m in swing.metrics {
            guard let pm = prev.metrics.first(where: { $0.kind == m.kind }) else { continue }
            func miss(_ v: SwingMetricValue) -> Double {
                let width = max(v.targetHigh - v.targetLow, 0.001)
                let over = v.value > v.targetHigh ? v.value - v.targetHigh
                         : v.value < v.targetLow ? v.targetLow - v.value : 0
                return over / width
            }
            let change = miss(pm) - miss(m)          // + = closer to the band now
            guard abs(change) > 0.12 else { continue }
            out.append((m.kind.displayName, change > 0, abs(change)))
        }
        return out.sorted { $0.magnitude > $1.magnitude }.map { ($0.name, $0.better) }
    }

    private func severity(_ m: SwingMetricValue) -> Double {
        let width = max(m.targetHigh - m.targetLow, 0.001)
        let over = m.value > m.targetHigh ? m.value - m.targetHigh : m.targetLow - m.value
        return over / width * m.confidence
    }

    private var usingClubTrail: Bool {
        // Club trail is DTL-only (face-on downswing club tracking isn't reliable —
        // face-on PATH always traces the hands). Same rule as the CLI renderer.
        guard swing.viewAngle == .downTheLine else { return false }
        return (preferClubTrail ?? true) && swing.clubTrail != nil
    }

    /// One analysis at a time. Down-the-line defaults to the club path (the tracer view);
    /// face-on defaults to the skeleton.
    private var activeOverlayMode: SwingOverlayMode {
        overlayMode ?? (swing.viewAngle == .downTheLine && swing.clubTrail != nil
                        ? .path : .skeleton)
    }

    /// Address anchors for the LINES-mode shaft plane: first club-trail point (clubhead at
    /// address) through the first hand-trail point (hands at address).
    private var planeAnchors: (hands: [Double], club: [Double])? {
        guard let club = swing.clubTrail?.first, club.count >= 2,
              let hands = swing.handTrail?.first, hands.count >= 2 else { return nil }
        return (hands, club)
    }

    private var activeTrail: [[Double]]? {
        if usingClubTrail { return swing.clubTrail }
        // Hands path draws only when the data is CLEAN — a jerky pose-noise line
        // teaches nothing (threshold calibrated on reference clips: clean ≈ 0.10,
        // jerky ≈ 0.27). Same rule as the CLI renderer.
        guard let hands = swing.handTrail,
              TrailQuality.roughness(hands) <= 0.20 else { return nil }
        return hands
    }

    /// Your best other swing from the SAME view — the ghost under this one.
    private var ghostTrail: [[Double]]? {
        guard showGhost else { return nil }
        return library.swings
            .filter { $0.analyzed && $0.id != swing.id && $0.viewAngle == swing.viewAngle
                      && $0.handTrail != nil }
            .max { ($0.overallScore ?? 0) < ($1.overallScore ?? 0) }?
            .handTrail
    }

    /// Head-travel box, drawn red only when sway actually missed on THIS swing.
    private var headBox: CGRect? {
        guard let sway = swing.metrics.first(where: { $0.kind == .headSway }), !sway.inBand,
              let trail = swing.headTrail, trail.count > 4 else { return nil }
        let xs = trail.map(\.[0]), ys = trail.map(\.[1])
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max()
        else { return nil }
        return CGRect(x: x0 - 0.01, y: y0 - 0.01, width: (x1 - x0) + 0.02, height: (y1 - y0) + 0.02)
    }

    /// Repeatability: the last 5 same-view hand paths on one canvas — coaches care about
    /// the spread more than any single swing.
    @ViewBuilder
    private var consistencySection: some View {
        let trails = library.swings
            .filter { $0.analyzed && $0.viewAngle == swing.viewAngle && $0.handTrail != nil }
            .suffix(5)
            .compactMap(\.handTrail)
        if trails.count >= 3 {
            VStack(alignment: .leading, spacing: 8) {
                TCSectionHeader(title: "Repeatability — last \(trails.count) swings")
                Canvas { ctx, size in
                    for (i, trail) in trails.enumerated() {
                        guard trail.count > 3 else { continue }
                        let alpha = 0.25 + 0.75 * Double(i + 1) / Double(trails.count)
                        var path = Path()
                        for (j, pt) in trail.enumerated() {
                            let p = CGPoint(x: pt[0] * size.width, y: (1 - pt[1]) * size.height)
                            if j == 0 { path.move(to: p) } else { path.addLine(to: p) }
                        }
                        ctx.stroke(path, with: .color(TCTheme.sage.opacity(alpha)),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
                .frame(height: 170)
                .background(TCTheme.panelDeep.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("Tight bundle = a repeating swing. The brightest line is this one.")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            .tcCard(padding: 14)
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
                                    trail: activeTrail,
                                    spineAngle: swing.metrics.first { $0.kind == .spineTiltAddress }?.value,
                                    videoRect: AVMakeRect(aspectRatio: videoPixelSize,
                                                          insideRect: CGRect(origin: .zero, size: geo.size)),
                                    mode: activeOverlayMode,
                                    trailLabel: usingClubTrail ? "CLUB PATH" : "HAND PATH",
                                    ghostTrail: usingClubTrail ? nil : ghostTrail,
                                    headBox: headBox,
                                    planeAnchors: planeAnchors,
                                    isFaceOn: swing.viewAngle == .faceOn,
                                    topTime: swing.phases?.times.flatMap { $0.count == 5 ? $0[2] : nil },
                                    mirrored: videoMirrored
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
        .overlay(alignment: .bottomLeading) {
            // The analysis picker: exactly one overlay at a time, like the reference apps'
            // Contour / Clubhead / Path tabs. Sub-toggles only appear for the active mode.
            VStack(alignment: .leading, spacing: 6) {
                if activeOverlayMode == .path {
                    HStack(spacing: 8) {
                        if swing.viewAngle == .downTheLine,
                           swing.clubTrail != nil, swing.handTrail != nil {
                            Button { preferClubTrail = !usingClubTrail } label: {
                                Text(usingClubTrail ? "CLUB" : "HANDS")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundColor(.cyan)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(Color.black.opacity(0.6)))
                            }
                            .buttonStyle(.plain)
                        }
                        if !usingClubTrail, ghostTrail != nil || !showGhost {
                            Button { showGhost.toggle() } label: {
                                Text(showGhost ? "GHOST ON" : "GHOST OFF")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundColor(showGhost ? Color(red: 1.0, green: 0.85, blue: 0.4) : .white.opacity(0.7))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(Color.black.opacity(0.6)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 6) {
                    ForEach(SwingOverlayMode.allCases, id: \.self) { m in
                        Button { overlayMode = m } label: {
                            Text(m.rawValue)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(activeOverlayMode == m ? .black : .white.opacity(0.85))
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .background(Capsule().fill(activeOverlayMode == m
                                                           ? Color.white.opacity(0.92)
                                                           : Color.black.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(10)
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
        if let selectedPhase,
           let phases = swing.phases,
           let idx = phases.labelled.firstIndex(where: { $0.label == selectedPhase }),
           idx < swing.keyPoses.count {
            return swing.keyPoses[idx]
        }
        // No phase picked yet → address pose, so SKELETON / LINES / ANGLES aren't blank.
        return swing.keyPoses.first
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
                if let note = swing.note, !note.isEmpty {
                    Label("\u{201C}\(note)\u{201D}", systemImage: "quote.opening")
                        .font(.system(size: 14, weight: .medium).italic())
                        .foregroundColor(TCTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button {
                        noteDraft = ""
                        showNoteEntry = true
                    } label: {
                        Label("Add how it felt", systemImage: "square.and.pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(TCTheme.sage)
                    }
                    .buttonStyle(.plain)
                }
            }
            .tcCard(padding: 16)
            .alert("How did that swing feel?", isPresented: $showNoteEntry) {
                TextField("felt like the lead arm stayed straight…", text: $noteDraft)
                Button("Save") {
                    var updated = swing
                    updated.note = noteDraft
                    library.updateSwing(updated)
                    library.logJournal("note", "Player on a \(swing.overallScore ?? 0)-score swing: \u{201C}\(noteDraft)\u{201D}")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your words become part of your coaching notes.")
            }
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

    @State private var showAllMetrics = false

    @ViewBuilder
    private var metricsSection: some View {
        if !swing.metrics.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation { showAllMetrics.toggle() }
                } label: {
                    HStack {
                        TCSectionHeader(title: "All Measurements")
                        Spacer()
                        Image(systemName: showAllMetrics ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(TCTheme.textUltraMuted)
                    }
                }
                .buttonStyle(.plain)
                if showAllMetrics {
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
/// Which single analysis the overlay draws. One at a time — stacking them all (skeleton +
/// gauges + trails + boxes) made the video unreadable. Modeled on the reference tools:
/// skeleton apps, plane-line compare apps, tracer apps, and posture-angle apps each show
/// exactly one idea, drawn big and clean.
enum SwingOverlayMode: String, CaseIterable {
    case skeleton = "SKELETON"   // clean cyan skeleton + joint dots
    case lines    = "LINES"      // shaft plane (address), spine, shoulder line
    case path     = "PATH"       // club/hand trace loop (+ ghost)
    case angles   = "ANGLES"     // posture angles with arcs and degree badges
}

struct RichPoseOverlay: View {
    let pose: StoredPose?
    let trail: [[Double]]?
    let spineAngle: Double?
    let videoRect: CGRect
    var mode: SwingOverlayMode = .skeleton
    /// What the ribbon traces — "HAND PATH" face-on, "CLUB PATH" down-the-line.
    var trailLabel: String = "HAND PATH"
    /// A second, fainter trail (your BEST swing) for ghost comparison.
    var ghostTrail: [[Double]]? = nil
    /// Normalized (Vision coords) box drawn in red — the head-travel band on a sway miss.
    var headBox: CGRect? = nil
    /// Address anchors for the LINES mode shaft plane: [hands, clubhead] normalized.
    var planeAnchors: (hands: [Double], club: [Double])? = nil
    /// Face-on gauges vs down-the-line hinge/flex arcs in ANGLES mode.
    var isFaceOn: Bool = true
    /// Top-of-backswing time: PATH mode draws the backswing and downswing in different
    /// colors when trail rows carry timestamps.
    var topTime: Double? = nil
    /// Horizontally flip all drawing (front-camera clips play mirrored, but the pose is in
    /// unmirrored space) so the skeleton/trail/gauges sit ON the displayed body.
    var mirrored: Bool = false

    // Reference-app palette: one hue per idea, not per body part.
    private static let boneColor  = Color(red: 0.25, green: 0.90, blue: 1.0)    // cyan
    private static let jointColor = Color(red: 1.0, green: 0.90, blue: 0.25)    // yellow
    private static let planeColor = Color(red: 1.0, green: 0.30, blue: 0.25)    // red
    private static let spineColor = Color(red: 1.0, green: 0.85, blue: 0.20)    // gold
    private static let bodyLineColor = Color(red: 0.35, green: 0.95, blue: 0.45) // green

    var body: some View {
        Canvas { ctx, _ in
            func toScreen(_ x: Double, _ y: Double) -> CGPoint {
                let mx = mirrored ? 1 - x : x
                return CGPoint(x: videoRect.minX + mx * videoRect.width,
                               y: videoRect.minY + (1 - y) * videoRect.height)
            }
            func pt(_ i: Int) -> CGPoint? {
                guard let pose, i < pose.points.count, pose.points[i][2] > 0.3 else { return nil }
                return toScreen(pose.points[i][0], pose.points[i][1])
            }

            switch mode {
            case .skeleton: drawSkeleton(ctx, pt: pt, toScreen: toScreen)
            case .lines:    drawLines(ctx, pt: pt, toScreen: toScreen)
            case .path:     drawPath(ctx, toScreen: toScreen)
            case .angles:   drawAngles(ctx, pt: pt)
            }
        }
    }

    // MARK: SKELETON — one color, thick smooth bones, small joint dots. Nothing else.

    private func drawSkeleton(_ ctx: GraphicsContext,
                              pt: (Int) -> CGPoint?,
                              toScreen: (Double, Double) -> CGPoint) {
        if let headBox {
            let boxMinX = mirrored ? 1 - headBox.maxX : headBox.minX
            let r = CGRect(x: videoRect.minX + boxMinX * videoRect.width,
                           y: videoRect.minY + (1 - headBox.maxY) * videoRect.height,
                           width: headBox.width * videoRect.width,
                           height: headBox.height * videoRect.height)
            ctx.stroke(Path(roundedRect: r, cornerRadius: 6),
                       with: .color(.red.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
            ctx.draw(Text("HEAD TRAVEL")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.red.opacity(0.9)),
                     at: CGPoint(x: r.midX, y: max(videoRect.minY + 8, r.minY - 10)))
        }
        guard pose != nil else { return }
        var bones = Path()
        for (a, b) in SwingSkeleton.bones {
            guard let pa = pt(a), let pb = pt(b) else { continue }
            bones.move(to: pa)
            bones.addLine(to: pb)
        }
        // Dark halo under the cyan so the skeleton reads on bright grass and pale sky alike.
        ctx.stroke(bones, with: .color(.black.opacity(0.35)),
                   style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        ctx.stroke(bones, with: .color(Self.boneColor.opacity(0.95)),
                   style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
        for i in 0..<14 {
            guard let p = pt(i) else { continue }
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                     with: .color(Self.jointColor))
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                       with: .color(.black.opacity(0.5)), lineWidth: 1)
        }
    }

    // MARK: LINES — three ideas max: address shaft plane (static), spine, shoulder line.

    private func drawLines(_ ctx: GraphicsContext,
                           pt: (Int) -> CGPoint?,
                           toScreen: (Double, Double) -> CGPoint) {
        func extended(_ a: CGPoint, _ b: CGPoint, by factor: CGFloat) -> (CGPoint, CGPoint) {
            let dx = b.x - a.x, dy = b.y - a.y
            return (CGPoint(x: a.x - dx * factor, y: a.y - dy * factor),
                    CGPoint(x: b.x + dx * factor, y: b.y + dy * factor))
        }
        func stroke(_ a: CGPoint, _ b: CGPoint, _ color: Color, width: CGFloat, dash: [CGFloat] = []) {
            var line = Path()
            line.move(to: a); line.addLine(to: b)
            ctx.stroke(line, with: .color(.black.opacity(0.3)),
                       style: StrokeStyle(lineWidth: width + 2.5, lineCap: .round, dash: dash))
            ctx.stroke(line, with: .color(color.opacity(0.95)),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))
        }
        // Shaft plane from ADDRESS (clubhead → hands, extended) — the line the club should
        // live around. DTL ONLY: face-on has no meaningful shaft plane (it degenerates to a
        // horizontal line through the hands). Static through the whole swing.
        if !isFaceOn, let anchors = planeAnchors,
           anchors.hands.count >= 2, anchors.club.count >= 2 {
            let hands = toScreen(anchors.hands[0], anchors.hands[1])
            let club  = toScreen(anchors.club[0], anchors.club[1])
            if hypot(hands.x - club.x, hands.y - club.y) > 20 {
                let (a, b) = extended(club, hands, by: 1.6)
                stroke(a, b, Self.planeColor, width: 3)
            }
        }
        // Spine: hips → shoulders, solid gold, with the degree badge.
        if let hipL = pt(8), let hipR = pt(9), let shL = pt(2), let shR = pt(3) {
            let hip = CGPoint(x: (hipL.x + hipR.x) / 2, y: (hipL.y + hipR.y) / 2)
            let sh  = CGPoint(x: (shL.x + shR.x) / 2, y: (shL.y + shR.y) / 2)
            let (a, b) = extended(hip, sh, by: 0.25)
            stroke(a, b, Self.spineColor, width: 3)
            if let spineAngle {
                ctx.draw(Text("\(Int(spineAngle))°")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(.white),
                         at: CGPoint(x: hip.x + 34, y: (hip.y + sh.y) / 2))
            }
            // Shoulder line, extended — the turn read.
            let (sa, sb) = extended(shL, shR, by: 0.9)
            stroke(sa, sb, Self.bodyLineColor, width: 2.5)
            // Face-on adds the hip line — turn + tilt at a glance, like the compare apps.
            if isFaceOn {
                let (ha, hb) = extended(hipL, hipR, by: 0.9)
                stroke(ha, hb, Self.planeColor, width: 2.5)
            }
        }
    }

    // MARK: PATH — the trace loop only, thick and smooth, with the ghost underneath.

    private func drawPath(_ ctx: GraphicsContext, toScreen: (Double, Double) -> CGPoint) {
        if let ghostTrail, ghostTrail.count > 3 {
            let pts = ghostTrail.map { toScreen($0[0], $0[1]) }
            var path = Path()
            path.move(to: pts[0])
            for q in pts.dropFirst() { path.addLine(to: q) }
            ctx.stroke(path, with: .color(Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.5)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))
            ctx.draw(Text("BEST SWING")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.4)),
                     at: CGPoint(x: pts[0].x, y: max(videoRect.minY + 8, pts[0].y - 12)))
        }
        guard let trail, trail.count > 3 else { return }
        // Backswing vs downswing in different colors, split at the top-of-swing time —
        // white going back, hot red coming down (the tracer-app look).
        let splitIdx: Int? = {
            guard let topTime, trail.first?.count ?? 0 >= 3 else { return nil }
            return trail.firstIndex { $0[2] > topTime }
        }()
        func smoothPath(_ pts: [CGPoint]) -> Path {
            var path = Path()
            guard pts.count > 1 else { return path }
            path.move(to: pts[0])
            guard pts.count > 2 else { path.addLine(to: pts[1]); return path }
            for i in 1..<pts.count - 1 {
                let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2,
                                  y: (pts[i].y + pts[i + 1].y) / 2)
                path.addQuadCurve(to: mid, control: pts[i])
            }
            path.addLine(to: pts[pts.count - 1])
            return path
        }
        let pts = trail.map { toScreen($0[0], $0[1]) }
        let back = splitIdx.map { Array(pts[0..<max($0, 2)]) } ?? pts
        let down = splitIdx.flatMap { $0 < pts.count ? Array(pts[(max($0, 1) - 1)...]) : nil }
        for (seg, color) in [(back, Color.white),
                             (down ?? [], Color(red: 1.0, green: 0.25, blue: 0.25))] {
            guard seg.count > 1 else { continue }
            let path = smoothPath(seg)
            ctx.stroke(path, with: .color(.black.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(color.opacity(0.92)),
                       style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        ctx.draw(Text(trailLabel)
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.white.opacity(0.9)),
                 at: CGPoint(x: pts[0].x, y: min(videoRect.maxY - 8, pts[0].y + 16)))
    }

    // MARK: ANGLES — posture numbers with visible geometry, nothing else.

    private func drawAngles(_ ctx: GraphicsContext, pt: (Int) -> CGPoint?) {
        guard let pose else { return }
        if isFaceOn {
            // Face-on: shoulder tilt + hip tilt gauges, head lean badge.
            let angles = SwingSkeleton.angles(from: pose)
            func tiltGauge(_ a: CGPoint, _ b: CGPoint, deg: Double, name: String) {
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let len = max(hypot(b.x - a.x, b.y - a.y), 1)
                let half = max(len / 2 + 12, 30)
                let ux = (b.x - a.x) / len, uy = (b.y - a.y) / len
                var line = Path()
                line.move(to: CGPoint(x: mid.x - ux * half, y: mid.y - uy * half))
                line.addLine(to: CGPoint(x: mid.x + ux * half, y: mid.y + uy * half))
                ctx.stroke(line, with: .color(.white.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
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
        } else {
            // Down-the-line: hip hinge + knee flex, the posture-app read — red joint
            // chain with an arc wedge and the degree at each vertex.
            func angleAt(_ vertex: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
                let v1 = CGVector(dx: a.x - vertex.x, dy: a.y - vertex.y)
                let v2 = CGVector(dx: b.x - vertex.x, dy: b.y - vertex.y)
                // Explicit Double: CGFloat + untyped literals left `acos` ambiguous on
                // the CI toolchain (x86_64) while resolving locally.
                let dot = Double(v1.dx * v2.dx + v1.dy * v2.dy)
                let mags = max(Double(hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy)), 1.0)
                return acos(max(-1.0, min(1.0, dot / mags))) * 180.0 / .pi
            }
            func wedge(at vertex: CGPoint, toward a: CGPoint, and b: CGPoint, deg: Double) {
                let r: CGFloat = 26
                let a1 = atan2(a.y - vertex.y, a.x - vertex.x)
                let a2 = atan2(b.y - vertex.y, b.x - vertex.x)
                var arc = Path()
                arc.move(to: vertex)
                arc.addArc(center: vertex, radius: r,
                           startAngle: .radians(a1), endAngle: .radians(a2),
                           clockwise: {
                               var d = a2 - a1
                               while d < 0 { d += 2 * .pi }
                               return d > .pi
                           }())
                arc.closeSubpath()
                ctx.fill(arc, with: .color(Self.planeColor.opacity(0.30)))
                ctx.draw(Text("\(Int(deg.rounded()))°")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundColor(.white),
                         at: CGPoint(x: vertex.x + 40, y: vertex.y), anchor: .leading)
            }
            // Use whichever side reads best (camera-side hip/knee/ankle).
            let sh = pt(2) ?? pt(3), hip = pt(8) ?? pt(9)
            let knee = pt(10) ?? pt(11), ankle = pt(12) ?? pt(13)
            if let sh, let hip, let knee, let ankle {
                var chain = Path()
                chain.move(to: sh)
                chain.addLine(to: hip)
                chain.addLine(to: knee)
                chain.addLine(to: ankle)
                ctx.stroke(chain, with: .color(.black.opacity(0.3)),
                           style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
                ctx.stroke(chain, with: .color(Self.planeColor.opacity(0.95)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                for p in [sh, hip, knee, ankle] {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                             with: .color(Self.jointColor))
                }
                wedge(at: hip, toward: sh, and: knee, deg: angleAt(hip, sh, knee))
                wedge(at: knee, toward: hip, and: ankle, deg: angleAt(knee, hip, ankle))
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



// MARK: - Session report card (what a coach hands you as you leave)

struct SessionReportView: View {
    let takes: [SwingRecording]
    let streak: Int
    let cue: String?
    let onDone: () -> Void

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Session Report")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(TCTheme.textPrimary)
                    .padding(.top, 26)

                HStack(spacing: 10) {
                    reportStat("\(takes.count)", "SWINGS")
                    reportStat(avgScore.map { "\($0)" } ?? "—", "AVG")
                    reportStat(takes.compactMap(\.overallScore).max().map { "\($0)" } ?? "—", "BEST")
                    reportStat("\(streak)", "STREAK")
                }
                .padding(.horizontal, TCTheme.hPad)

                if let headline = takes.compactMap({ $0.headline.isEmpty ? nil : $0.headline }).last {
                    Label(headline, systemImage: "hand.thumbsup.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TCTheme.sage)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, TCTheme.hPad)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEXT TIME")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(TCTheme.gold).tracking(1.4)
                    Text(cue.map { "One thought: \($0)." }
                         ?? "Keep stacking reps — consistency is the next skill.")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tcCard(padding: 16)
                .padding(.horizontal, TCTheme.hPad)

                Spacer()
                TCPrimaryGoldButton(title: "Done", icon: "checkmark") { onDone() }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.bottom, 24)
            }
        }
    }

    private var avgScore: Int? {
        let scores = takes.compactMap(\.overallScore)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / scores.count
    }

    private func reportStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(TCTheme.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(TCTheme.textMuted).tracking(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(TCTheme.panel)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TCTheme.borderMedium, lineWidth: 1)))
    }
}
