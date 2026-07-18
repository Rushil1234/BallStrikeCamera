import SwiftUI
import SceneKit
import AVFoundation
import Vision

// MARK: - TrueCarry Coach: lesson player (renders the 6 step kinds)

struct LessonPlayerView: View {
    let lesson: Lesson
    let onClose: () -> Void

    @ObservedObject private var library = LessonLibrary.shared
    @State private var stepIndex = 0
    @State private var sessionRecord: LessonSessionRecord?
    @State private var showStudio = false
    @State private var capturedThisStep: [SwingRecording] = []
    @State private var quizSelections: [String: Int] = [:]
    @State private var lessonScore: Int?
    @State private var check3DPassed = false

    private var step: LessonStep { lesson.steps[min(stepIndex, lesson.steps.count - 1)] }
    private var isLast: Bool { stepIndex >= lesson.steps.count - 1 }

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: TCTheme.sectionGap) {
                        stepContent
                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 16)
                }
                footer
            }
        }
        .onAppear {
            if sessionRecord == nil { sessionRecord = library.beginLesson(lesson) }
        }
        .fullScreenCover(isPresented: $showStudio) {
            SwingStudioView(lessonId: lesson.id,
                            requiredSwings: step.swingCount ?? 1) {
                showStudio = false
                capturedThisStep = library.swings.filter {
                    $0.lessonId == lesson.id && $0.analyzed
                }.suffix(step.swingCount ?? 1).map { $0 }
                let best = capturedThisStep.compactMap(\.overallScore).max()
                if let best { lessonScore = max(lessonScore ?? 0, best) }
                sessionRecord?.swingIds.append(contentsOf: capturedThisStep.map(\.id))
            }
            .tcAppearance()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    // Partial work still counts as a session — history keeps it.
                    if let record = sessionRecord, stepIndex > 0 {
                        library.abandonLesson(session: record, stepsCompleted: stepIndex)
                    }
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(TCTheme.panelRaised))
                }
                Spacer()
                Text(lesson.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Spacer()
                Text("\(stepIndex + 1)/\(lesson.steps.count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(TCTheme.textMuted)
                    .frame(width: 36)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(TCTheme.panelRaised)
                    Capsule().fill(TCTheme.gold)
                        .frame(width: geo.size.width * CGFloat(stepIndex + 1) / CGFloat(max(lesson.steps.count, 1)))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            TCPrimaryGoldButton(title: continueTitle, icon: isLast ? "checkmark" : "arrow.right") {
                advance()
            }
            .disabled(!stepSatisfied)
            .opacity(stepSatisfied ? 1 : 0.5)
            .padding(.horizontal, TCTheme.hPad)
            .padding(.vertical, 12)
        }
        .background(TCTheme.panel.opacity(0.92))
    }

    private var continueTitle: String {
        if step.kind == .swingCapture && !stepSatisfied {
            if (step.swingCount ?? 1) >= 3, !lesson.focusMetrics.isEmpty {
                let st = library.streak(for: lesson.id)
                return st.current > 0 ? "\(st.current) of 3 in a row — keep going"
                                      : "Pass 3 in a row to master this"
            }
            return "Record your swings first"
        }
        if step.kind == .check3D && !stepSatisfied { return "Show the camera (or tick the checklist)" }
        return isLast ? "Finish Lesson" : "Continue"
    }

    private var stepSatisfied: Bool {
        switch step.kind {
        case .explainer, .video, .model3D:
            return true
        case .check3D:
            return check3DPassed
        case .swingCapture:
            // Rep-based mastery: multi-swing graded steps pass on 3 IN-BAND swings in a
            // row, not on attendance. Small holds (1-2 swings) keep the count rule.
            if (step.swingCount ?? 1) >= 3, !lesson.focusMetrics.isEmpty {
                return library.streak(for: lesson.id).current >= 3
            }
            return capturedThisStep.count >= (step.swingCount ?? 1)
        case .quiz:
            return step.quiz.allSatisfy { quizSelections[$0.question] == $0.correctIndex }
        }
    }

    private func advance() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        library.completeStep(step, in: lesson)
        if isLast {
            if let record = sessionRecord {
                library.completeLesson(lesson, session: record, score: lessonScore)
            }
            onClose()
        } else {
            stepIndex += 1
            capturedThisStep = []
            check3DPassed = false
        }
    }

    // MARK: Step renderers

    @ViewBuilder
    private var stepContent: some View {
        switch step.kind {
        case .explainer:  explainerStep
        case .video:      videoStep
        case .model3D:    Model3DStepView(step: step)
        case .check3D:    GripCheckStepView(step: step, passed: $check3DPassed)
        case .swingCapture: swingCaptureStep
        case .quiz:       quizStep
        }
    }

    private var explainerStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step.title)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundColor(TCTheme.textPrimary)
            // Tripod-distance readability: the phone often sits 6+ feet away during lessons.
            Text(step.body)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(TCTheme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(step.points, id: \.self) { point in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(TCTheme.sage)
                        .padding(.top, 2)
                    Text(point)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(TCTheme.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tcCard(padding: 18)
    }

    private var videoStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            // Video catalog resolves to real films later — until then, an illustrated placeholder.
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TCTheme.panelRaised)
                    .frame(height: 200)
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(TCTheme.gold.opacity(0.7))
                    Text("Coaching video coming soon")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TCTheme.textMuted)
                }
            }
            if !step.body.isEmpty {
                Text(step.body)
                    .font(.system(size: 14))
                    .foregroundColor(TCTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tcCard(padding: 18)
    }

    private var swingCaptureStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            Text(step.body)
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(0..<(step.swingCount ?? 1), id: \.self) { i in
                    ZStack {
                        Circle()
                            .fill(i < capturedThisStep.count ? TCTheme.sage : TCTheme.panelRaised)
                            .frame(width: 34, height: 34)
                        if i < capturedThisStep.count {
                            if let s = capturedThisStep[i].overallScore {
                                Text("\(s)")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            } else {
                                Image(systemName: "checkmark").foregroundColor(.white)
                            }
                        } else {
                            Text("\(i + 1)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(TCTheme.textUltraMuted)
                        }
                    }
                }
                Spacer()
            }
            ForEach(capturedThisStep) { swing in
                if !swing.focusPoint.isEmpty {
                    Text("• \(swing.headline)")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.sage)
                }
            }
            TCPrimaryGoldButton(title: capturedThisStep.isEmpty ? "Open Swing Studio" : "Record another",
                                icon: "video.fill") {
                showStudio = true
            }
        }
        .tcCard(padding: 18)
    }

    private var quizStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(step.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            ForEach(step.quiz) { q in
                VStack(alignment: .leading, spacing: 8) {
                    Text(q.question)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    ForEach(Array(q.answers.enumerated()), id: \.offset) { idx, answer in
                        let picked = quizSelections[q.question] == idx
                        let correct = picked && idx == q.correctIndex
                        Button { quizSelections[q.question] = idx } label: {
                            HStack {
                                Text(answer)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(TCTheme.textPrimary)
                                Spacer()
                                if picked {
                                    Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(correct ? TCTheme.sage : .red.opacity(0.8))
                                }
                            }
                            .padding(12)
                            .background(TCTheme.panelRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(picked ? (correct ? TCTheme.sage : Color.red.opacity(0.6)) : TCTheme.border, lineWidth: 1.4))
                        }
                        .buttonStyle(.plain)
                    }
                    if quizSelections[q.question] == q.correctIndex && !q.why.isEmpty {
                        Text(q.why)
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.sage)
                    }
                }
            }
        }
        .tcCard(padding: 18)
    }
}

// MARK: - model3D step (USDZ when the asset ships; annotated fallback until then)

private struct Model3DStepView: View {
    let step: LessonStep
    @State private var checked: Set<String> = []

    private var sceneURL: URL? {
        guard let name = step.asset3D else { return nil }
        return Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: "Lessons3D")
            ?? Bundle.main.url(forResource: name, withExtension: "usdz")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            // Commissioned USDZ wins when present. Grip steps render the illustrated
            // diagram (the procedural 3D grip read as blobs); other assets keep the
            // procedural scene so the step works with zero external files.
            if let scene = (sceneURL.flatMap { try? SCNScene(url: $0) }) {
                SceneKitView(scene: scene)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Drag to rotate · pinch to zoom")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textUltraMuted)
            } else if let variant = GripDiagram.Variant(asset: step.asset3D) {
                GripDiagram(variant: variant)
            } else if let scene = step.asset3D.flatMap({ LessonSceneFactory.scene(for: $0) }) {
                SceneKitView(scene: scene)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Drag to rotate · pinch to zoom")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            if !step.body.isEmpty {
                Text(step.body)
                    .font(.system(size: 14))
                    .foregroundColor(TCTheme.textSecondary)
            }
            ForEach(step.checkpoints, id: \.self) { cp in
                Button {
                    if checked.contains(cp) { checked.remove(cp) } else { checked.insert(cp) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: checked.contains(cp) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundColor(checked.contains(cp) ? TCTheme.sage : TCTheme.textUltraMuted)
                            .padding(.top, 1)
                        Text(cp)
                            .font(.system(size: 14))
                            .foregroundColor(TCTheme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .tcCard(padding: 18)
    }
}

// MARK: - Procedural 3D teaching scenes (no external assets; USDZ overrides when shipped)

enum LessonSceneFactory {

    static func scene(for name: String) -> SCNScene? {
        switch name {
        case "address_posture":  return addressScene()
        case "alignment_tracks": return alignmentScene()
        default: return nil
        }
    }

    private static func mat(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.roughness.contents = 0.7
        return m
    }

    private static func node(_ geo: SCNGeometry, _ color: UIColor,
                             pos: SCNVector3, euler: SCNVector3 = SCNVector3(0, 0, 0)) -> SCNNode {
        geo.materials = [mat(color)]
        let n = SCNNode(geometry: geo)
        n.position = pos
        n.eulerAngles = euler
        return n
    }

    private static func baseScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.08, alpha: 1)
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.position = SCNVector3(0, 0.15, 1.1)
        scene.rootNode.addChildNode(cam)
        return scene
    }

    /// Capsule mannequin in athletic address posture with the spine-angle guide line.
    private static func addressScene() -> SCNScene {
        let scene = baseScene()
        let body = UIColor(red: 0.45, green: 0.65, blue: 0.85, alpha: 1)
        let root = SCNNode()
        root.addChildNode(node(SCNBox(width: 1.2, height: 0.02, length: 0.8, chamferRadius: 0), UIColor(red: 0.15, green: 0.3, blue: 0.15, alpha: 1), pos: SCNVector3(0, -0.45, 0)))
        // Legs (flexed), torso hinged ~35°, head, arms hanging.
        root.addChildNode(node(SCNCapsule(capRadius: 0.035, height: 0.36), body, pos: SCNVector3(-0.08, -0.27, 0), euler: SCNVector3(0.15, 0, 0.05)))
        root.addChildNode(node(SCNCapsule(capRadius: 0.035, height: 0.36), body, pos: SCNVector3(0.08, -0.27, 0), euler: SCNVector3(0.15, 0, -0.05)))
        let spineTilt: Float = 0.6   // ~35°
        root.addChildNode(node(SCNCapsule(capRadius: 0.05, height: 0.4), body, pos: SCNVector3(0, 0.02, 0.1), euler: SCNVector3(spineTilt, 0, 0)))
        root.addChildNode(node(SCNSphere(radius: 0.06), body, pos: SCNVector3(0, 0.22, 0.22)))
        root.addChildNode(node(SCNCapsule(capRadius: 0.022, height: 0.34), body, pos: SCNVector3(-0.11, -0.0, 0.24), euler: SCNVector3(0.25, 0, 0.1)))
        root.addChildNode(node(SCNCapsule(capRadius: 0.022, height: 0.34), body, pos: SCNVector3(0.11, -0.0, 0.24), euler: SCNVector3(0.25, 0, -0.1)))
        // Club to the ball + spine guide line (gold).
        root.addChildNode(node(SCNCylinder(radius: 0.008, height: 0.5), .lightGray, pos: SCNVector3(0, -0.22, 0.36), euler: SCNVector3(0.9, 0, 0)))
        root.addChildNode(node(SCNSphere(radius: 0.02), .white, pos: SCNVector3(0, -0.43, 0.52)))
        root.addChildNode(node(SCNCylinder(radius: 0.004, height: 0.62), UIColor(red: 0.85, green: 0.68, blue: 0.25, alpha: 1), pos: SCNVector3(0.14, -0.02, 0.13), euler: SCNVector3(spineTilt, 0, 0)))
        scene.rootNode.addChildNode(root)
        return scene
    }

    /// Train tracks: target line through the ball, parallel toe line, flag downrange.
    private static func alignmentScene() -> SCNScene {
        let scene = baseScene()
        let root = SCNNode()
        root.addChildNode(node(SCNBox(width: 1.6, height: 0.02, length: 1.2, chamferRadius: 0), UIColor(red: 0.15, green: 0.3, blue: 0.15, alpha: 1), pos: SCNVector3(0, -0.3, 0)))
        // Target line (white) through the ball; toe line (sage) parallel.
        root.addChildNode(node(SCNBox(width: 0.02, height: 0.005, length: 1.1, chamferRadius: 0), .white, pos: SCNVector3(0.12, -0.285, 0)))
        root.addChildNode(node(SCNBox(width: 0.02, height: 0.005, length: 1.1, chamferRadius: 0), UIColor(red: 0.45, green: 0.65, blue: 0.35, alpha: 1), pos: SCNVector3(-0.18, -0.285, 0)))
        root.addChildNode(node(SCNSphere(radius: 0.022), .white, pos: SCNVector3(0.12, -0.26, 0.1)))
        // Feet on the toe line.
        for z in [Float(0.16), -0.16] {
            root.addChildNode(node(SCNCapsule(capRadius: 0.03, height: 0.12), UIColor(white: 0.2, alpha: 1), pos: SCNVector3(-0.26, -0.27, z), euler: SCNVector3(0, 0, 1.57)))
        }
        // Flag downrange on the target line.
        root.addChildNode(node(SCNCylinder(radius: 0.006, height: 0.3), .lightGray, pos: SCNVector3(0.12, -0.15, -0.52)))
        root.addChildNode(node(SCNBox(width: 0.1, height: 0.06, length: 0.005, chamferRadius: 0), UIColor(red: 0.85, green: 0.68, blue: 0.25, alpha: 1), pos: SCNVector3(0.17, -0.05, -0.52)))
        scene.rootNode.addChildNode(root)
        return scene
    }
}

private struct SceneKitView: UIViewRepresentable {
    let scene: SCNScene
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = scene
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = true
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

// MARK: - check3D step (back camera on the tripod: finds the club, walks ghost hands
// onto the user's own grip, and verifies hands-stacked-on-the-club live)

private struct GripCheckStepView: View {
    let step: LessonStep
    @Binding var passed: Bool
    @StateObject private var checker = GripCheckController()
    @State private var checked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            Text(step.body)
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ZStack {
                CameraPreviewView(session: checker.session)
                GripCoachOverlay(checker: checker, passed: passed)

                if passed {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 44))
                            .foregroundColor(TCTheme.sage)
                        Text("Grip verified!")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.55)))
                }

                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: statusIcon)
                            .foregroundColor(checker.gripLatched || passed ? TCTheme.sageBright : .white)
                        // Tripod-distance readability: this line is read from 6+ feet away.
                        Text(passed ? "Nailed it — continue when ready." : checker.statusText)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
                }
            }
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onAppear { checker.start() }
            .onDisappear { checker.stop() }
            .onChange(of: checker.verified) { verified in
                if verified && !passed {
                    passed = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }

            ForEach(step.checkpoints, id: \.self) { cp in
                Button {
                    if checked.contains(cp) { checked.remove(cp) } else { checked.insert(cp) }
                    if checked.count == step.checkpoints.count { passed = true }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: checked.contains(cp) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundColor(checked.contains(cp) ? TCTheme.sage : TCTheme.textUltraMuted)
                        Text(cp)
                            .font(.system(size: 14))
                            .foregroundColor(TCTheme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .tcCard(padding: 18)
    }

    private var statusIcon: String {
        if passed || checker.verified { return "checkmark.seal.fill" }
        if checker.holdProgress > 0 { return "timer" }
        if checker.shaft == nil { return "viewfinder" }
        return "hand.raised.fill"
    }
}

// MARK: Live overlay — everything is anchored to the DETECTED club, not screen offsets.

/// Maps Vision-normalized points (origin bottom-left) into the aspect-fill preview.
private struct PreviewMap {
    let offset: CGPoint
    let disp: CGSize

    init(buffer: CGSize, view: CGSize) {
        let s = max(view.width / max(buffer.width, 1), view.height / max(buffer.height, 1))
        disp = CGSize(width: buffer.width * s, height: buffer.height * s)
        offset = CGPoint(x: (view.width - disp.width) / 2, y: (view.height - disp.height) / 2)
    }

    func point(_ n: CGPoint) -> CGPoint {
        CGPoint(x: offset.x + n.x * disp.width, y: offset.y + (1 - n.y) * disp.height)
    }
}

private struct GripCoachOverlay: View {
    @ObservedObject var checker: GripCheckController
    let passed: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let map = PreviewMap(buffer: checker.bufferSize, view: size)
                let t = timeline.date.timeIntervalSinceReferenceDate

                if let shaft = checker.shaft {
                    let butt = map.point(shaft.butt)
                    let tip = map.point(shaft.tip)
                    drawShaftLock(ctx, butt: butt, tip: tip)
                    // Ghost hands walk onto the grip until the user's own hands are there.
                    if !passed && !checker.gripLatched {
                        drawGhostHands(ctx, butt: butt, tip: tip, t: t)
                    }
                } else if !passed {
                    drawScanSweep(ctx, size: size, t: t)
                }

                // The user's detected hands — proof the camera sees them.
                for hand in checker.handPoints {
                    let p = map.point(hand)
                    let color: Color = checker.handsOnClub ? TCTheme.sageBright : .white
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)),
                               with: .color(color.opacity(0.85)), lineWidth: 2)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)),
                             with: .color(color))
                }

                // Hold-to-verify ring between the stacked hands.
                if !passed, checker.holdProgress > 0, checker.handPoints.count >= 2 {
                    let a = map.point(checker.handPoints[0])
                    let b = map.point(checker.handPoints[1])
                    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    var track = Path()
                    track.addArc(center: mid, radius: 27, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
                    ctx.stroke(track, with: .color(.white.opacity(0.25)), lineWidth: 5)
                    var arc = Path()
                    arc.addArc(center: mid, radius: 27, startAngle: .degrees(-90),
                               endAngle: .degrees(-90 + 360 * checker.holdProgress), clockwise: false)
                    ctx.stroke(arc, with: .color(TCTheme.gold),
                               style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Lock-on treatment along the detected shaft + gold band marking the grip zone.
    private func drawShaftLock(_ ctx: GraphicsContext, butt: CGPoint, tip: CGPoint) {
        var line = Path()
        line.move(to: butt)
        line.addLine(to: tip)
        ctx.stroke(line, with: .color(TCTheme.sageBright.opacity(0.16)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
        ctx.stroke(line, with: .color(TCTheme.sageBright.opacity(0.8)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

        let gripEnd = CGPoint(x: butt.x + (tip.x - butt.x) * 0.32, y: butt.y + (tip.y - butt.y) * 0.32)
        var zone = Path()
        zone.move(to: butt)
        zone.addLine(to: gripEnd)
        ctx.stroke(zone, with: .color(TCTheme.gold.opacity(0.3)), style: StrokeStyle(lineWidth: 11, lineCap: .round))

        ctx.stroke(Path(ellipseIn: CGRect(x: butt.x - 9, y: butt.y - 9, width: 18, height: 18)),
                   with: .color(TCTheme.gold.opacity(0.9)), lineWidth: 2)
    }

    /// Looping choreography: lead hand slides down the shaft into the grip zone, the
    /// trail hand follows and stacks snug underneath, both settle, fade, repeat.
    private func drawGhostHands(_ ctx: GraphicsContext, butt: CGPoint, tip: CGPoint, t: TimeInterval) {
        let dx = tip.x - butt.x, dy = tip.y - butt.y
        let len = max(hypot(dx, dy), 1)
        let u = CGVector(dx: dx / len, dy: dy / len)
        let angle = atan2(dy, dx)
        let handH = min(max(len * 0.13, 34), 64)
        let span = handH / len              // one hand's height, in shaft fractions

        let period = 4.4
        let p = t.truncatingRemainder(dividingBy: period) / period
        let fadeAll = p > 0.9 ? max(0, (1 - p) / 0.1) : 1
        let pulse: CGFloat = (0.6...0.68).contains(p) ? 1 + 0.05 * CGFloat(sin(.pi * (p - 0.6) / 0.08)) : 1

        func easeOut(_ x: Double) -> Double { 1 - pow(1 - min(max(x, 0), 1), 3) }
        func along(_ s: CGFloat) -> CGPoint { CGPoint(x: butt.x + u.dx * s * len, y: butt.y + u.dy * s * len) }

        // Trail hand (gold) drawn first so the lead hand stacks on top of it visually.
        let trailProgress = easeOut((p - 0.32) / 0.26)
        let trailS = 0.72 - (0.72 - (0.14 + Double(span) * 0.95)) * trailProgress
        let trailAlpha = p < 0.30 ? 0 : min(1, (p - 0.30) / 0.1) * fadeAll
        drawGhostHand(ctx, at: along(CGFloat(trailS)), angle: angle, height: handH * pulse,
                      tint: TCTheme.gold, alpha: trailAlpha)

        let leadProgress = easeOut((p - 0.06) / 0.28)
        let leadS = 0.55 - (0.55 - 0.14) * leadProgress
        let leadAlpha = min(1, max(0, (p - 0.04) / 0.1)) * fadeAll
        drawGhostHand(ctx, at: along(CGFloat(leadS)), angle: angle, height: handH * pulse,
                      tint: TCTheme.sageBright, alpha: leadAlpha)
    }

    /// One tinted gripping hand from the shared artwork (fingers wrapped over the shaft,
    /// thumb running down it), drawn in a local frame where the shaft is vertical.
    private func drawGhostHand(_ ctx: GraphicsContext, at point: CGPoint, angle: CGFloat,
                               height: CGFloat, tint: Color, alpha: Double) {
        guard alpha > 0.01 else { return }
        var c = ctx
        c.addFilter(.shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2))
        c.translateBy(x: point.x, y: point.y)
        c.rotate(by: Angle(radians: Double(angle) - .pi / 2))
        let k = height / 90
        c.scaleBy(x: k, y: k)
        c.translateBy(x: -14, y: 0)   // center the wrapped hand on the shaft line
        GhostHandArt.draw(c, pose: .grip, style: .tinted(tint), alpha: alpha)
    }

    /// Gold sweep while we look for the club in frame.
    private func drawScanSweep(_ ctx: GraphicsContext, size: CGSize, t: TimeInterval) {
        let x = size.width * (0.5 + 0.42 * CGFloat(sin(t * 1.1)))
        var sweep = Path()
        sweep.move(to: CGPoint(x: x, y: 14))
        sweep.addLine(to: CGPoint(x: x, y: size.height - 14))
        ctx.stroke(sweep, with: .color(TCTheme.gold.opacity(0.35)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round))

        let inset = CGRect(x: 10, y: 10, width: size.width - 20, height: size.height - 20)
        ctx.stroke(Path(roundedRect: inset, cornerRadius: 12),
                   with: .color(.white.opacity(0.18)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [7, 7]))
    }
}

/// Distance from a point to a segment, plus where along the segment it lands (0 = a).
private func segmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> (dist: CGFloat, t: CGFloat) {
    let abx = b.x - a.x, aby = b.y - a.y
    let len2 = max(abx * abx + aby * aby, 1e-6)
    let t = max(0, min(1, ((p.x - a.x) * abx + (p.y - a.y) * aby) / len2))
    let q = CGPoint(x: a.x + abx * t, y: a.y + aby * t)
    return (hypot(p.x - q.x, p.y - q.y), t)
}

// MARK: Grip coach controller

/// Back-camera grip coach: finds the club shaft (the long, thin, tilted contour —
/// disambiguated by proximity to the hands), tracks both hands, and verifies
/// "hands stacked ON the grip" held steady. Checklist remains the human fallback.
@MainActor
final class GripCheckController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    struct ShaftLine: Equatable {
        var butt: CGPoint    // grip end (upper), Vision-normalized, origin bottom-left
        var tip: CGPoint     // clubhead end (lower)
    }

    @Published var handsDetected = 0
    @Published var handPoints: [CGPoint] = []     // hand centers, Vision-normalized
    @Published var shaft: ShaftLine?
    @Published var handsStacked = false
    @Published var handsOnClub = false
    @Published var holdProgress: Double = 0       // 0…1 while verifying
    @Published var verified = false
    @Published var bufferSize = CGSize(width: 1080, height: 1920)

    var gripLatched: Bool { handsOnClub && handsStacked }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "gripcoach")

    var statusText: String {
        if verified { return "Grip verified — that's it." }
        if holdProgress > 0 { return "Hold it right there…" }
        if shaft == nil {
            if handsStacked { return "Hands look good — now show the whole club" }
            return "Show me your club — full shaft in frame"
        }
        if handsDetected == 0 { return "Club locked. Bring both hands to the grip" }
        if handsDetected == 1 { return "One hand on — now add the other" }
        if !handsOnClub { return "Slide your hands onto the grip" }
        return "Bring your hands together — no gap"
    }

    func start() {
        queue.async { [self] in
            _gcShaft = nil
            _gcShaftSeenAt = 0
            _gcHoldStart = nil
            _gcVerified = false
            if session.inputs.isEmpty {
                // Tripod flow: the phone faces the player SCREEN-OUT (they watch the ghost
                // hands + status while gripping), so the FRONT camera is the coach.
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                guard let device,
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else {
                    if !session.isRunning { session.startRunning() }
                    return
                }
                session.beginConfiguration()
                session.sessionPreset = .high
                session.addInput(input)
                let out = AVCaptureVideoDataOutput()
                out.setSampleBufferDelegate(self, queue: queue)
                out.alwaysDiscardsLateVideoFrames = true
                if session.canAddOutput(out) { session.addOutput(out) }
                if let conn = out.connection(with: .video) {
                    conn.videoOrientation = .portrait
                    if device.position == .front, conn.isVideoMirroringSupported {
                        conn.isVideoMirrored = true   // match the mirrored front preview
                    }
                }
                session.commitConfiguration()
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        if now - _gcLastProcess < 0.18 { return }
        _gcLastProcess = now
        if _gcVerified { return }
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let bw = CGFloat(CVPixelBufferGetWidth(pb))
        let bh = CGFloat(CVPixelBufferGetHeight(pb))
        let aspect = bw / max(bh, 1)
        // All geometry below happens in "aspect space" (x scaled by width/height) so
        // distances and angles are true, in units of frame height.
        func asp(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }

        let handRequest = VNDetectHumanHandPoseRequest()
        handRequest.maximumHandCount = 2
        let contourRequest = VNDetectContoursRequest()
        contourRequest.maximumImageDimension = 512
        contourRequest.contrastAdjustment = 1.6
        try? VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up)
            .perform([handRequest, contourRequest])

        var hands: [CGPoint] = []
        var handSpans: [CGFloat] = []     // wrist↔knuckle size, aspect space — distance proxy
        for obs in handRequest.results ?? [] {
            guard let wrist = try? obs.recognizedPoint(.wrist), wrist.confidence > 0.3 else { continue }
            var center = wrist.location
            if let mcp = try? obs.recognizedPoint(.middleMCP), mcp.confidence > 0.3 {
                center = CGPoint(x: (center.x + mcp.location.x) / 2, y: (center.y + mcp.location.y) / 2)
                let w = asp(wrist.location), k = asp(mcp.location)
                handSpans.append(hypot(w.x - k.x, w.y - k.y))
            }
            hands.append(center)
        }
        let handsMid: CGPoint? = hands.isEmpty ? nil
            : CGPoint(x: hands.map(\.x).reduce(0, +) / CGFloat(hands.count),
                      y: hands.map(\.y).reduce(0, +) / CGFloat(hands.count))

        if let contours = contourRequest.results?.first,
           let candidate = Self.bestShaftCandidate(in: contours, aspect: aspect, near: handsMid) {
            if let prev = _gcShaft,
               hypot(prev.butt.x - candidate.butt.x, prev.butt.y - candidate.butt.y) < 0.35 {
                // Smooth against jitter while the lock holds.
                _gcShaft = (CGPoint(x: prev.butt.x * 0.65 + candidate.butt.x * 0.35,
                                    y: prev.butt.y * 0.65 + candidate.butt.y * 0.35),
                            CGPoint(x: prev.tip.x * 0.65 + candidate.tip.x * 0.35,
                                    y: prev.tip.y * 0.65 + candidate.tip.y * 0.35))
            } else {
                _gcShaft = candidate
            }
            _gcShaftSeenAt = now
        } else if now - _gcShaftSeenAt > 1.6 {
            _gcShaft = nil   // lock survives brief occlusion (hands crossing the shaft)
        }

        // Thresholds scale with apparent hand size, so standing a few steps back from the
        // tripod (hands small in frame) is just as verifiable as filling the frame.
        let span = handSpans.isEmpty ? 0.05 : handSpans.reduce(0, +) / CGFloat(handSpans.count)
        let stackedThresh = min(max(1.9 * span, 0.05), 0.13)
        let onClubThresh = min(max(1.1 * span, 0.03), 0.08)
        var stacked = false
        var onClub = false
        if hands.count >= 2 {
            let a = asp(hands[0]), b = asp(hands[1])
            stacked = hypot(a.x - b.x, a.y - b.y) < stackedThresh
        }
        if let s = _gcShaft, hands.count >= 2 {
            let a = asp(s.butt), b = asp(s.tip)
            let hits = hands.map { segmentDistance(asp($0), a, b) }
            onClub = hits.allSatisfy { $0.dist < onClubThresh }
                && (hits.map(\.t).reduce(0, +) / CGFloat(hits.count)) < 0.6   // grip half, not the hosel
        }

        // Hold-to-verify: the full check needs the club; hands-only is the slower fallback
        // for cluttered scenes where the shaft never locks.
        var progress = 0.0
        let fullCheck = _gcShaft != nil && stacked && onClub
        let fallbackCheck = _gcShaft == nil && stacked
        if fullCheck || fallbackCheck {
            if _gcHoldStart == nil { _gcHoldStart = now }
            progress = min(1, (now - _gcHoldStart!) / (fullCheck ? 1.5 : 3.2))
            if progress >= 1 { _gcVerified = true }
        } else {
            _gcHoldStart = nil
        }

        let shaftOut = _gcShaft.map { ShaftLine(butt: $0.butt, tip: $0.tip) }
        let handsOut = hands
        let stackedOut = stacked
        let onClubOut = onClub
        let progressOut = progress
        let verifiedOut = _gcVerified
        Task { @MainActor in
            self.bufferSize = CGSize(width: bw, height: bh)
            self.handsDetected = handsOut.count
            self.handPoints = handsOut
            self.shaft = shaftOut
            self.handsStacked = stackedOut
            self.handsOnClub = onClubOut
            self.holdProgress = progressOut
            if verifiedOut { self.verified = true }
        }
    }

    /// The club shaft is the longest thin, straight, tilted contour — scored up when its
    /// upper end sits near the hands. Runs on ≤512px frames at ~5Hz.
    /// Internal (not private) so the DEBUG clip harness can exercise it on real footage.
    nonisolated static func bestShaftCandidate(in observation: VNContoursObservation,
                                                       aspect: CGFloat,
                                                       near handsMid: CGPoint?) -> (butt: CGPoint, tip: CGPoint)? {
        var contours: [VNContour] = []
        var pending = observation.topLevelContours
        while let contour = pending.popLast(), contours.count < 300 {
            contours.append(contour)
            pending.append(contentsOf: contour.childContours)
        }

        var best: (score: CGFloat, butt: CGPoint, tip: CGPoint)?
        for contour in contours where contour.pointCount >= 24 {
            let raw = contour.normalizedPoints
            let step = max(1, raw.count / 120)
            var sample: [(x: CGFloat, y: CGFloat)] = []
            var i = 0
            while i < raw.count {
                sample.append((CGFloat(raw[i].x) * aspect, CGFloat(raw[i].y)))
                i += step
            }
            let n = CGFloat(sample.count)
            guard n >= 12 else { continue }

            let mx = sample.map(\.x).reduce(0, +) / n
            let my = sample.map(\.y).reduce(0, +) / n
            var sxx: CGFloat = 0, sxy: CGFloat = 0, syy: CGFloat = 0
            for (x, y) in sample {
                let dx = x - mx, dy = y - my
                sxx += dx * dx; sxy += dx * dy; syy += dy * dy
            }
            sxx /= n; sxy /= n; syy /= n

            // 2×2 PCA: major axis = shaft direction, minor spread = shaft thickness.
            let half = (sxx + syy) / 2
            let root = sqrt(max(0, half * half - (sxx * syy - sxy * sxy)))
            let thin = sqrt(max(0, half - root))
            guard thin < 0.02 else { continue }

            let theta = 0.5 * atan2(2 * sxy, sxx - syy)
            let ux = cos(theta), uy = sin(theta)
            let tiltDeg = abs(atan2(uy, ux)) * 180 / .pi
            let tilt = tiltDeg > 90 ? 180 - tiltDeg : tiltDeg
            // A held club is tilted or near-vertical — never horizontal (walls, benches).
            guard tilt > 28, tilt < 89.5 else { continue }

            var minP = CGFloat.infinity, maxP = -CGFloat.infinity
            for (x, y) in sample {
                let p = (x - mx) * ux + (y - my) * uy
                minP = min(minP, p); maxP = max(maxP, p)
            }
            let length = maxP - minP
            guard length > 0.22, length < 1.05 else { continue }

            var upper = CGPoint(x: mx + ux * minP, y: my + uy * minP)
            var lower = CGPoint(x: mx + ux * maxP, y: my + uy * maxP)
            if upper.y < lower.y { swap(&upper, &lower) }   // butt = higher in frame

            var score = length
            if let hm = handsMid {
                let d = hypot(upper.x - hm.x * aspect, upper.y - hm.y)
                score += max(0, 0.4 - d) * 1.4
            }
            if best == nil || score > best!.score {
                best = (score,
                        CGPoint(x: upper.x / aspect, y: upper.y),
                        CGPoint(x: lower.x / aspect, y: lower.y))
            }
        }
        return best.map { ($0.butt, $0.tip) }
    }
}

// Queue-confined worker state for the grip coach (one active checker at a time,
// matching the codebase's nonisolated-delegate idiom).
private nonisolated(unsafe) var _gcLastProcess: TimeInterval = 0
private nonisolated(unsafe) var _gcShaft: (butt: CGPoint, tip: CGPoint)?
private nonisolated(unsafe) var _gcShaftSeenAt: TimeInterval = 0
private nonisolated(unsafe) var _gcHoldStart: TimeInterval?
private nonisolated(unsafe) var _gcVerified = false

/// Reusable AVCapture preview layer host.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}
