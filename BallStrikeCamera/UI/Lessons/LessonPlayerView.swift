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
                Button { onClose() } label: {
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
        if step.kind == .swingCapture && !stepSatisfied { return "Record your swings first" }
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
            // Commissioned USDZ wins when present; otherwise the procedural scene renders —
            // fully in-code, so the 3D step works with zero external assets.
            if let scene = (sceneURL.flatMap { try? SCNScene(url: $0) })
                        ?? step.asset3D.flatMap({ LessonSceneFactory.scene(for: $0) }) {
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
        case "grip_interlock":   return gripScene(strong: false)
        case "grip_strong":      return gripScene(strong: true)
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

    /// Stylized hands on a club grip. Strong grip rotates the lead hand ~20° clockwise
    /// (the "3 knuckles" look the slice track teaches).
    private static func gripScene(strong: Bool) -> SCNScene {
        let scene = baseScene()
        let root = SCNNode()
        // Shaft angled like a club held at address in front of you.
        let tilt = Float.pi / 9
        root.addChildNode(node(SCNCylinder(radius: 0.012, height: 0.9), .lightGray,
                               pos: SCNVector3(0, -0.18, 0), euler: SCNVector3(0, 0, tilt)))
        // Grip section
        root.addChildNode(node(SCNCapsule(capRadius: 0.02, height: 0.28), UIColor(white: 0.15, alpha: 1),
                               pos: SCNVector3(-0.105, 0.11, 0), euler: SCNVector3(0, 0, tilt)))
        // Lead hand (sage) above trail hand (gold), stacked on the grip.
        let leadTwist: Float = strong ? -0.35 : 0
        let lead = node(SCNCapsule(capRadius: 0.045, height: 0.11), UIColor(red: 0.45, green: 0.65, blue: 0.35, alpha: 1),
                        pos: SCNVector3(-0.135, 0.15, 0.01), euler: SCNVector3(0.4 + leadTwist, 0.3, tilt))
        let trail = node(SCNCapsule(capRadius: 0.045, height: 0.11), UIColor(red: 0.78, green: 0.62, blue: 0.25, alpha: 1),
                         pos: SCNVector3(-0.075, 0.065, 0.015), euler: SCNVector3(0.4 + leadTwist * 0.6, -0.3, tilt))
        root.addChildNode(lead); root.addChildNode(trail)
        // Knuckle markers on the lead hand: 2 neutral, 3 strong.
        for i in 0..<(strong ? 3 : 2) {
            root.addChildNode(node(SCNSphere(radius: 0.012), .white,
                                   pos: SCNVector3(-0.165 + Float(i) * 0.025, 0.185, 0.045)))
        }
        // Interlock hint: pinky bridge between the hands.
        root.addChildNode(node(SCNCapsule(capRadius: 0.012, height: 0.05), UIColor(red: 0.45, green: 0.65, blue: 0.35, alpha: 1),
                               pos: SCNVector3(-0.104, 0.105, 0.035), euler: SCNVector3(0, 0, 1.2)))
        scene.rootNode.addChildNode(root)
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

// MARK: - check3D step (front camera + on-device hand tracking, self-confirm fallback)

private struct GripCheckStepView: View {
    let step: LessonStep
    @Binding var passed: Bool
    @StateObject private var checker = GripCheckController()
    @State private var checked: Set<String> = []
    @State private var stackedSince: Date?
    @State private var animPhase = false

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
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Opaque demo animation: hands converge onto the grip until the camera
                // sees the user's own hands stacked — then it clears out of the way.
                if !passed && !checker.handsStacked {
                    GripConvergeAnimation(animPhase: animPhase)
                        .allowsHitTesting(false)
                }
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
                        Image(systemName: checker.handsStacked ? "checkmark.seal.fill" : "hand.raised.fill")
                            .foregroundColor(checker.handsStacked ? TCTheme.sage : .white)
                        Text(passed ? "Nailed it — continue when ready." : checker.statusText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
                }
            }
            .onAppear {
                checker.start()
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    animPhase = true
                }
            }
            .onDisappear { checker.stop() }
            // Auto-complete: hands stacked and HELD for 1.5s = verified (haptic celebration).
            .onChange(of: checker.handsStacked) { stacked in
                if stacked {
                    stackedSince = Date()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if checker.handsStacked, let since = stackedSince,
                           Date().timeIntervalSince(since) >= 1.4, !passed {
                            passed = true
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }
                } else {
                    stackedSince = nil
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
}

/// The opaque "hands come together over the club" demo loop drawn over the camera.
private struct GripConvergeAnimation: View {
    let animPhase: Bool

    var body: some View {
        ZStack {
            // Club shaft, angled like it's held at address.
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.85))
                .frame(width: 7, height: 190)
                .rotationEffect(.degrees(22))
            // Lead hand slides down; trail hand slides up — they meet on the grip.
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 44))
                .foregroundColor(TCTheme.sage.opacity(0.95))
                .rotationEffect(.degrees(35))
                .offset(x: animPhase ? -14 : -66, y: animPhase ? -34 : -96)
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 44))
                .scaleEffect(x: -1, y: 1)
                .foregroundColor(TCTheme.gold.opacity(0.95))
                .rotationEffect(.degrees(-28))
                .offset(x: animPhase ? 10 : 62, y: animPhase ? 6 : 74)
            Text("Bring your hands together like this")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .offset(y: 118)
        }
    }
}

/// Minimal front-camera hand-pose checker: detects two hands close together ("stacked" —
/// the shape of every proper grip). Confidence-gated; the checklist is the human fallback.
@MainActor
final class GripCheckController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var handsDetected = 0
    @Published var handsStacked = false

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "gripcheck")

    var statusText: String {
        if handsStacked { return "Hands stacked — that's a grip!" }
        if handsDetected >= 2 { return "Two hands — bring them together on the club" }
        if handsDetected == 1 { return "One hand visible — show both on the grip" }
        return "Hold your grip up in front of the camera"
    }

    func start() {
        queue.async { [self] in
            guard session.inputs.isEmpty,
                  let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
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
            out.connection(with: .video)?.videoOrientation = .portrait
            session.commitConfiguration()
            session.startRunning()
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
        if now - _lastGripCheck < 0.25 { return }
        _lastGripCheck = now
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        try? VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up).perform([request])
        let hands = request.results ?? []
        var stacked = false
        if hands.count >= 2,
           let w1 = try? hands[0].recognizedPoint(.wrist), w1.confidence > 0.3,
           let w2 = try? hands[1].recognizedPoint(.wrist), w2.confidence > 0.3 {
            let d = hypot(w1.location.x - w2.location.x, w1.location.y - w2.location.y)
            stacked = d < 0.16   // wrists within ~16% of frame = hands on one grip
        }
        let count = hands.count
        Task { @MainActor in
            self.handsDetected = count
            self.handsStacked = stacked
        }
    }
}

private nonisolated(unsafe) var _lastGripCheck: TimeInterval = 0

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
