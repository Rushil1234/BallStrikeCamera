import SwiftUI

struct ShotTrackingReviewView: View {
    let analysis: ShotAnalysisResult
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @State private var displayMode: FrameNormalizationMode = .darkenedHighContrast
    @State private var showComposite: Bool = false

    init(analysis: ShotAnalysisResult, onDismiss: @escaping () -> Void) {
        self.analysis = analysis
        self.onDismiss = onDismiss
        // Start at the impact frame so the user immediately sees the interesting moment.
        self._currentIndex = State(initialValue: analysis.impactFrameIndex)
    }

    private var currentFrame: AnalyzedShotFrame { analysis.frames[currentIndex] }
    private var lastIndex: Int { max(0, analysis.frames.count - 1) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            imageArea
            infoPanel
            navigationBar
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .fullScreenCover(isPresented: $showComposite) {
            ShotCompositeView(analysis: analysis) {
                showComposite = false
            }
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Shot Review")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            // Mode picker: Original | Darkened | Brightened
            HStack(spacing: 0) {
                ForEach(FrameNormalizationMode.allCases, id: \.self) { mode in
                    Button(action: { displayMode = mode }) {
                        Text(mode.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(displayMode == mode ? .black : .white.opacity(0.65))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(displayMode == mode ? Color.white : Color.clear)
                    }
                }
            }
            .background(Color.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Button(action: { showComposite = true }) {
                Text("Composite")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.indigo.opacity(0.7))
                    .clipShape(Capsule())
            }

            Button("Done") {
                onDismiss()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.10))
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

                    Canvas { ctx, size in
                        drawOverlays(ctx: ctx, containerSize: size, image: img)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)

                    if currentFrame.frameIndex == analysis.impactFrameIndex {
                        VStack {
                            Text("IMPACT FRAME")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.85))
                                .clipShape(Capsule())
                            Spacer()
                        }
                        .padding(.top, 10)
                        .allowsHitTesting(false)
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
           let cx  = obs.centerX, let cy = obs.centerY, let d = obs.diameter {
            let center = mapPoint(CGPoint(x: cx, y: cy), to: dr)
            let radius = d * dr.width / 2
            let ballRect = CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2)
            ctx.stroke(Path(ellipseIn: ballRect), with: .color(Color.green), lineWidth: 2)
            let dotRect = CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)
            ctx.fill(Path(ellipseIn: dotRect), with: .color(Color.green))
        }
    }

    // MARK: - Info Panel

    private var infoPanel: some View {
        let frame    = currentFrame
        let obs      = frame.ballObservation
        let debug    = frame.debugInfo
        let isImpact = frame.frameIndex == analysis.impactFrameIndex
        let isPost   = frame.frameIndex > analysis.impactFrameIndex

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 12) {
                Text("Frame \(currentIndex) / \(lastIndex)")
                    .fontWeight(.semibold)

                Text(isImpact ? "IMPACT" : isPost ? "post" : "pre")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isImpact ? .red : isPost ? .orange : .secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background((isImpact ? Color.red : isPost ? Color.orange : Color.secondary).opacity(0.15))
                    .clipShape(Capsule())

                Text(displayMode.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Text(String(format: "t = %+.4f s", frame.relativeTime))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                if let cx = obs?.centerX, let cy = obs?.centerY {
                    Text(String(format: "x=%.4f  y=%.4f", cx, cy))
                } else {
                    Text("x=nil  y=nil")
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let d = obs?.diameter { Text(String(format: "d=%.4f", d)) }
                if let obs, obs.centerX != nil {
                    Text(String(format: "conf=%.2f", obs.confidence))
                        .foregroundColor(.green)
                }
            }

            HStack(spacing: 10) {
                if obs?.centerX != nil {
                    Label("Detected", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 11, weight: .semibold))
                } else {
                    Label("No ball detected", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 11, weight: .semibold))
                }

                Spacer()

                if let debug {
                    Text("bright px: \(debug.candidateCount)")
                        .foregroundColor(.secondary)
                    if let reason = debug.rejectionReason {
                        Text(reason)
                            .foregroundColor(.orange)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.08))
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack(spacing: 12) {
            Button(action: { if currentIndex > 0 { currentIndex -= 1 } }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(currentIndex > 0 ? .white : .white.opacity(0.25))
            }
            .frame(width: 44, height: 44)

            Slider(
                value: Binding(
                    get: { Double(currentIndex) },
                    set: { currentIndex = Int($0.rounded()) }
                ),
                in: 0...Double(lastIndex),
                step: 1
            )
            .tint(.white)

            Button(action: { if currentIndex < lastIndex { currentIndex += 1 } }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(currentIndex < lastIndex ? .white : .white.opacity(0.25))
            }
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(white: 0.10))
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
}
