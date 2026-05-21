import SwiftUI

struct ShotTrackingReviewView: View {
    @EnvironmentObject private var session: AuthSessionStore

    let analysis: ShotAnalysisResult
    let context: ShotContext?
    let selectedClubId: UUID?
    let selectedClubName: String?
    let onShotSaved: ((SavedShot) -> Void)?
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @State private var displayMode:      FrameNormalizationMode = .darkenedHighContrast
    @State private var showComposite:    Bool = false
    @State private var isExporting:      Bool = false
    @State private var showShareSheet:   Bool = false
    @State private var exportedURL:      URL? = nil
    @State private var exportError:      String? = nil
    @State private var showMarkBadAlert: Bool = false
    @State private var isSavingShot:     Bool = false
    @State private var savedShot:        SavedShot? = nil
    @State private var saveError:        String? = nil
    #if DEBUG
    @State private var showTester: Bool = false
    #endif

    init(analysis: ShotAnalysisResult,
         context: ShotContext? = nil,
         selectedClubId: UUID? = nil,
         selectedClubName: String? = nil,
         onShotSaved: ((SavedShot) -> Void)? = nil,
         onDismiss: @escaping () -> Void) {
        self.analysis = analysis
        self.context = context
        self.selectedClubId = selectedClubId
        self.selectedClubName = selectedClubName
        self.onShotSaved = onShotSaved
        self.onDismiss = onDismiss
        // Start at the impact frame so the user immediately sees the interesting moment.
        let maxIndex = max(0, analysis.frames.count - 1)
        self._currentIndex = State(initialValue: min(max(0, analysis.detectedImpactFrameIndex), maxIndex))
    }

    private var currentFrame: AnalyzedShotFrame { analysis.frames[currentIndex] }
    private var lastIndex: Int { max(0, analysis.frames.count - 1) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            imageArea   // slider is overlaid inside
            actionBar   // Save / Bad — compact row above metrics
            metricsPanel
        }
        .background(Color.black.ignoresSafeArea())
        .tcAppearance()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .fullScreenCover(isPresented: $showComposite) {
            ShotCompositeView(analysis: analysis) { showComposite = false }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .alert("Marked as bad shot", isPresented: $showMarkBadAlert) {
            Button("OK") { }
        }
        .alert("Save failed", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        #if DEBUG
        .fullScreenCover(isPresented: $showTester) {
            BallTrackingTestView { showTester = false }
        }
        #endif
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("Shot Review")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .layoutPriority(1)

            Spacer(minLength: 4)

            // Mode picker
            HStack(spacing: 0) {
                ForEach(FrameNormalizationMode.allCases, id: \.self) { mode in
                    Button(action: { displayMode = mode }) {
                        Text(mode.displayName)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(displayMode == mode ? .black : .white.opacity(0.65))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(displayMode == mode ? Color.white : Color.clear)
                    }
                }
            }
            .background(Color.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Button("Done") { onDismiss() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 9)
        .background(Color(white: 0.10))
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button(action: { Task { await saveShot(markBad: false) } }) {
                Label(saveButtonTitle, systemImage: savedShot == nil ? "square.and.arrow.down" : "checkmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.white.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .disabled(saveButtonDisabled)

            Button(action: { Task { await saveShot(markBad: true) } }) {
                Label("Bad Shot", systemImage: "xmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Color.orange.opacity(0.18))
                    .foregroundColor(.orange.opacity(0.90))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .disabled(saveButtonDisabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(white: 0.065))
    }

    private var saveButtonTitle: String {
        if isSavingShot { return "Saving…" }
        if savedShot != nil { return "Saved" }
        return "Save Shot"
    }

    private var saveButtonDisabled: Bool {
        isSavingShot || savedShot != nil || analysis.metrics == nil || session.currentUser?.id == nil
    }

    @MainActor
    private func saveShot(markBad: Bool) async {
        guard !saveButtonDisabled,
              let uid = session.currentUser?.id,
              let metrics = analysis.metrics else { return }

        isSavingShot = true
        defer { isSavingShot = false }

        do {
            let service = ShotPersistenceService(userId: uid, backend: session.backend)
            let shot = try await service.saveShot(
                metrics: SavedShotMetrics(metrics),
                compositeImage: nil,
                clubId: selectedClubId,
                clubName: selectedClubName,
                mode: context?.shotMode ?? .range,
                saveOriginalFrames: false,
                roundId: context?.courseRoundId,
                holeNumber: context?.holeNumber,
                isBadShot: markBad,
                badShotReason: markBad ? "Marked from review" : nil
            )
            savedShot = shot
            onShotSaved?(shot)
            if markBad { showMarkBadAlert = true }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private var displayedImage: UIImage? {
        switch displayMode {
        case .original:            return currentFrame.originalFrame.image
        case .darkenedHighContrast: return currentFrame.darkenedHighContrastImage ?? currentFrame.originalFrame.image
        case .brightened:          return currentFrame.brightenedImage           ?? currentFrame.originalFrame.image
        }
    }

    private var imageArea: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let img = displayedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)

                    Canvas { ctx, size in
                        drawOverlays(ctx: ctx, containerSize: size, image: img)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)

                    // Top overlays: frame index + detection badge (left), impact badge (right)
                    VStack {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                frameIndexOverlay
                                detectionBadge
                            }
                            .padding(.leading, 12)
                            .padding(.top, 10)
                            Spacer()
                            if currentFrame.frameIndex == analysis.detectedImpactFrameIndex {
                                Text("IMPACT FRAME")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.yellow.opacity(0.90))
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    .padding(.trailing, 12)
                                    .padding(.top, 10)
                            }
                        }
                        Spacer()
                    }
                    .allowsHitTesting(false)

                    // Slider overlaid at bottom of image
                    VStack {
                        Spacer()
                        sliderOverlay
                            .padding(.horizontal, 12)
                            .padding(.bottom, 14)
                    }

                    // Action buttons — bottom-right of image, above frame slider
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Button(action: { showComposite = true }) {
                                    Label("Composite", systemImage: "square.stack.3d.up")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.indigo.opacity(0.7))
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }

                                Button(action: doExport) {
                                    Label(isExporting ? "…" : "Export", systemImage: "square.and.arrow.up")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(isExporting ? Color.gray.opacity(0.5) : Color.green.opacity(0.7))
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                                .disabled(isExporting)

                                #if DEBUG
                                Button(action: { showTester = true }) {
                                    Label("Tester", systemImage: "flask")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.purple.opacity(0.7))
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                                #endif
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.40))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(.trailing, 10)
                        }
                        .padding(.bottom, 72)  // sits above the slider overlay (~58pt)
                    }
                } else {
                    Text("No image")
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .layoutPriority(1)
    }

    private var frameIndexOverlay: some View {
        let frame = currentFrame
        let isImpact = frame.frameIndex == analysis.detectedImpactFrameIndex
        let isPost   = frame.frameIndex >  analysis.detectedImpactFrameIndex
        return HStack(spacing: 6) {
            Text("Frame \(currentIndex)/\(lastIndex)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text(String(format: "t=%+.3fs", frame.relativeTime))
                .font(.system(size: 10, design: .monospaced))
            if isImpact {
                Text("IMPACT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else if isPost {
                Text("post")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.orange)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var detectionBadge: some View {
        let detected = currentFrame.ballObservation?.centerX != nil
        return HStack(spacing: 5) {
            Image(systemName: detected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(detected ? "Detected" : "Not detected")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(detected ? .green : Color(white: 0.70))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var sliderOverlay: some View {
        HStack(spacing: 8) {
            Button(action: { if currentIndex > 0 { currentIndex -= 1 } }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(currentIndex > 0 ? .white : .white.opacity(0.25))
            }
            .frame(width: 36, height: 36)

            Slider(
                value: Binding(
                    get: { Double(currentIndex) },
                    set: { currentIndex = Int($0.rounded()) }
                ),
                in: 0...Double(max(1, lastIndex)),
                step: 1
            )
            .tint(.white)

            Button(action: { if currentIndex < lastIndex { currentIndex += 1 } }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(currentIndex < lastIndex ? .white : .white.opacity(0.25))
            }
            .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Overlay Drawing

    private func drawOverlays(ctx: GraphicsContext, containerSize: CGSize, image: UIImage) {
        let dr = aspectFitRect(imageSize: image.size, in: containerSize)

        // Locked ball rect — yellow solid border.
        if let locked = analysis.lockedBallRect {
            ctx.stroke(Path(mapRect(locked, to: dr)),
                       with: .color(Color.yellow.opacity(0.85)),
                       lineWidth: 2)
        }

        // Impact detector ROI — orange dashed.
        if let impactROI = analysis.lockedImpactROI {
            ctx.stroke(Path(mapRect(impactROI, to: dr)),
                       with: .color(Color.orange.opacity(0.75)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
        }

        // Tracker search ROI for this frame — cyan dashed.
        if let searchROI = currentFrame.debugInfo?.searchROI {
            ctx.stroke(Path(mapRect(searchROI, to: dr)),
                       with: .color(Color.cyan.opacity(0.75)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
        }

        // Ball detection result — green circle + center dot.
        if let obs = currentFrame.ballObservation,
           let cx  = obs.centerX, let cy = obs.centerY,
           let d = obs.finalDiameter ?? obs.diameter {
            let center = mapPoint(CGPoint(x: cx, y: cy), to: dr)
            let radius = d * dr.width / 2
            let ballRect = CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2)
            ctx.stroke(Path(ellipseIn: ballRect), with: .color(Color.green), lineWidth: 2)
            let dotRect = CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)
            ctx.fill(Path(ellipseIn: dotRect), with: .color(Color.green))
        }
    }

    @ViewBuilder
    private var metricsPanel: some View {
        if let metrics = analysis.metrics {
            VStack(spacing: 0) {
                // Row 1 — primary ball metrics
                HStack(spacing: 0) {
                    metricCell("Ball Speed", value: mph(metrics.ballLaunch.ballSpeedMph))
                    metricCell("HLA",        value: metrics.ballLaunch.hlaDisplay)
                    metricCell("VLA",        value: degrees(metrics.ballLaunch.vlaDegrees))
                    metricCell("Carry",      value: yards(metrics.distance.carryYards))
                    metricCell("Total",      value: yards(metrics.distance.totalYards))
                }
                Divider().background(Color.white.opacity(0.06))
                // Row 2 — secondary metrics
                HStack(spacing: 0) {
                    metricCell("Club Speed",   value: mph(metrics.club.clubSpeedMph))
                    metricCell("Smash Factor", value: plain(metrics.smashFactor, digits: 2))
                    metricCell("Backspin",     value: rpm(metrics.spin.estimatedBackspinRpm))
                    metricCell("Club Path",    value: metrics.clubPath.clubPathDisplay)
                    metricCell("Face",         value: metrics.faceAngle.faceAngleDisplay)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(white: 0.065))
        }
    }

    private func metricCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.50))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.60)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    // MARK: - Export

    private func doExport() {
        guard !isExporting else { return }
        isExporting = true
        Task.detached(priority: .userInitiated) {
            do {
                let result = try ShotExportService().export(from: analysis)
                await MainActor.run {
                    exportedURL    = result.zipURL
                    isExporting    = false
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }

    // MARK: - Geometry Helpers

    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let scale = min(containerSize.width / imageSize.width,
                        containerSize.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (containerSize.width - w) / 2,
                      y: (containerSize.height - h) / 2,
                      width: w, height: h)
    }

    private func mapRect(_ normalized: CGRect, to dr: CGRect) -> CGRect {
        CGRect(x: dr.minX + normalized.minX * dr.width,
               y: dr.minY + normalized.minY * dr.height,
               width: normalized.width * dr.width,
               height: normalized.height * dr.height)
    }

    private func mapPoint(_ normalized: CGPoint, to dr: CGRect) -> CGPoint {
        CGPoint(x: dr.minX + normalized.x * dr.width,
                y: dr.minY + normalized.y * dr.height)
    }

    private func mph(_ value: Double?) -> String {
        value.map { String(format: "%.1f mph", $0) } ?? "--"
    }

    private func rpm(_ value: Double?) -> String {
        value.map { String(format: "%.0f rpm", $0) } ?? "--"
    }

    private func degrees(_ value: Double?) -> String {
        value.map { String(format: "%.1f°", $0) } ?? "--"
    }

    private func yards(_ value: Double?) -> String {
        value.map { String(format: "%.0f yd", $0) } ?? "--"
    }

    private func plain(_ value: Double?, digits: Int) -> String {
        guard let value else { return "--" }
        return String(format: "%.\(digits)f", value)
    }
}

import UIKit

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
