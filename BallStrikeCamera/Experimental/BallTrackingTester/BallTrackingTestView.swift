#if DEBUG
import SwiftUI
import UIKit

// MARK: - Root

struct BallTrackingTestView: View {
    let onDismiss: () -> Void

    @State private var exports:      [URL]                      = []
    @State private var sequence:     BallTrackingTestSequence?  = nil
    @State private var result:       BallTrackingTestResult?    = nil
    @State private var isRunning:    Bool                       = false
    @State private var currentIndex: Int                        = 0
    @State private var loadError:    String?                    = nil
    @State private var displayMode:  FrameNormalizationMode     = .darkenedHighContrast
    @State private var settings:     BallTrackingTuningSettings = BallTrackingTuningSettings()

    private let loader     = TestFrameLoader()
    private let normalizer = FrameNormalizer()

    // Effective impact index: detected (after Run) or metadata fallback
    private var effectiveImpactIndex: Int {
        result?.detectedImpactFrameIndex ?? sequence?.impactFrameIndex ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let seq = sequence {
                mainContent(seq)
            } else {
                exportList
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { exports = loader.listAvailableExports() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            if sequence != nil {
                Button(action: { sequence = nil; result = nil }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            Text(sequence.map { "Tester · \($0.sourceName)" } ?? "Tracking Tester")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white).lineLimit(1).truncationMode(.middle)
            Spacer()
            if sequence != nil {
                displayModePicker
                Button(action: runTracker) {
                    Label(isRunning ? "Running…" : "Run", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(isRunning ? Color.gray.opacity(0.5) : Color.purple.opacity(0.75))
                        .clipShape(Capsule())
                }
                .disabled(isRunning)
            }
            Button("Done") { onDismiss() }
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.blue)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(white: 0.10))
    }

    private var displayModePicker: some View {
        HStack(spacing: 0) {
            ForEach(FrameNormalizationMode.allCases, id: \.self) { mode in
                Button(action: { displayMode = mode }) {
                    Text(mode.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(displayMode == mode ? .black : .white.opacity(0.65))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(displayMode == mode ? Color.white : Color.clear)
                }
            }
        }
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - Export list

    private var exportList: some View {
        Group {
            if exports.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.system(size: 36)).foregroundColor(.white.opacity(0.3))
                    Text("No shot exports found").font(.system(size: 14)).foregroundColor(.white.opacity(0.5))
                    Text("Export a shot from the Review screen first.")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(exports, id: \.self) { url in
                            Button(action: { loadExport(url) }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                                        if let count = frameCount(in: url) {
                                            Text("\(count) frames")
                                                .font(.system(size: 11)).foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12)).foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(Color(white: 0.10))
                            }
                        }
                    }
                }
                .padding(.top, 1)
            }
        }
    }

    // MARK: - Main content

    private func mainContent(_ seq: BallTrackingTestSequence) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                imagePane(seq).frame(maxWidth: .infinity)
                controlsSidebar.frame(width: 270)
            }
            .layoutPriority(1)
            impactInfoRow
            frameStrip(seq)
            navigationBar(seq)
        }
        .background(
            KeyboardNavigatorView(
                onLeft:  { if currentIndex > 0 { currentIndex -= 1 } },
                onRight: { if currentIndex < (sequence?.frames.count ?? 1) - 1 { currentIndex += 1 } }
            ).frame(width: 0, height: 0)
        )
    }

    // MARK: - Impact info row

    private var impactInfoRow: some View {
        Group {
            if let r = result {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.yellow)
                    Text("Impact detected: frame \(r.detectedImpactFrameIndex)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white)
                    if r.detectedImpactFrameIndex != r.fallbackImpactFrameIndex {
                        Text("(fallback: \(r.fallbackImpactFrameIndex))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    Text(r.impactDetectionReason)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary).lineLimit(1)
                    Spacer()
                    if let c = r.initialBallCenter {
                        Text(String(format: "initCenter=(%.3f,%.3f)", c.x, c.y))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color(white: 0.08))
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Image pane

    private func imagePane(_ seq: BallTrackingTestSequence) -> some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if currentIndex < seq.frames.count,
                   let img = displayedImage(seq.frames[currentIndex]) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    let obs = result?.observations.first {
                        $0.frameIndex == seq.frames[currentIndex].frameIndex
                    }
                    let showCandBounds = settings.showOriginalCandidateBounds
                    Canvas { ctx, size in
                        drawOverlay(ctx: ctx, containerSize: size, image: img,
                                    obs: obs, showCandidateBounds: showCandBounds)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)
                    infoOverlay(seq: seq, obs: obs)
                    if settings.showMaskPreview {
                        maskPreviewInset(obs)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, 8).padding(.trailing, 8)
                            .allowsHitTesting(false)
                    }
                } else {
                    Text("No image").foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func displayedImage(_ frame: BallTrackingTestFrame) -> UIImage? {
        displayMode == .original ? frame.image
            : normalizer.normalizedImage(from: frame.image, mode: displayMode)
    }

    // MARK: - Canvas overlay

    private func drawOverlay(ctx: GraphicsContext, containerSize: CGSize,
                              image: UIImage, obs: BallTrackingTestObservation?,
                              showCandidateBounds: Bool) {
        let dr = aspectFitRect(imageSize: image.size, in: containerSize)
        guard dr.width > 0, dr.height > 0 else { return }
        let dbg = obs?.frameDebug

        // Cyan dashed ROI
        if let roi = dbg?.searchROI {
            ctx.stroke(Path(normToView(roi, dr: dr)), with: .color(.cyan.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }

        // Rejected candidates — red dashed rects
        for cand in dbg?.candidates ?? [] where !cand.accepted {
            ctx.stroke(Path(normToView(cand.rect, dr: dr)), with: .color(.red.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }

        // Accepted-but-not-selected — yellow circles (candidate diameter)
        if let selected = dbg?.selectedCandidate {
            for cand in dbg?.candidates ?? [] where cand.accepted && cand.centerX != selected.centerX {
                strokeCircle(ctx: ctx, dr: dr, cx: cand.centerX, cy: cand.centerY,
                             d: cand.diameter, color: .yellow, lineWidth: 1.5)
            }
        }

        guard let cx = obs?.centerX, let cy = obs?.centerY else { return }

        // Optional faint gray dashed rect — selected candidate blob bbox
        if showCandidateBounds, let blobRect = dbg?.selectedCandidate?.rect {
            ctx.stroke(Path(normToView(blobRect, dr: dr)), with: .color(.white.opacity(0.3)),
                       style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }

        // Green circle — tight around the white pixels in the B&W mask.
        if let maskRect = obs?.maskBoundsRect,
           let refinedD = obs?.maskRefinedDiameter {
            strokeCircle(ctx: ctx, dr: dr, cx: maskRect.midX, cy: maskRect.midY,
                         d: refinedD, color: .green, lineWidth: 2)
        } else if let finalD = obs?.diameter {
            strokeCircle(ctx: ctx, dr: dr, cx: cx, cy: cy,
                         d: finalD, color: .green, lineWidth: 2)
        }

        // Green center dot follows the refined mask center when available.
        let dotCenter = obs?.maskBoundsRect.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: cx, y: cy)
        let dotPx = CGPoint(x: dr.minX + dotCenter.x * dr.width, y: dr.minY + dotCenter.y * dr.height)
        ctx.fill(Path(ellipseIn: CGRect(x: dotPx.x - 2.5, y: dotPx.y - 2.5, width: 5, height: 5)),
                 with: .color(.green))
    }

    private func strokeCircle(ctx: GraphicsContext, dr: CGRect,
                               cx: CGFloat, cy: CGFloat, d: CGFloat,
                               color: Color, lineWidth: CGFloat) {
        let radius = d * dr.width / 2
        let center = CGPoint(x: dr.minX + cx * dr.width, y: dr.minY + cy * dr.height)
        ctx.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2)),
                   with: .color(color), lineWidth: lineWidth)
    }

    private func normToView(_ rect: CGRect, dr: CGRect) -> CGRect {
        CGRect(x: dr.minX + rect.minX * dr.width, y: dr.minY + rect.minY * dr.height,
               width: rect.width * dr.width, height: rect.height * dr.height)
    }

    // MARK: - Info overlay

    private func infoOverlay(seq: BallTrackingTestSequence,
                              obs: BallTrackingTestObservation?) -> some View {
        let frame    = currentIndex < seq.frames.count ? seq.frames[currentIndex] : nil
        let detImpact = effectiveImpactIndex
        let isImpact  = frame?.frameIndex == detImpact
        let isPost    = (frame?.frameIndex ?? 0) > detImpact

        return VStack(alignment: .leading, spacing: 3) {
            // Line 1: frame + phase + time
            HStack(spacing: 8) {
                Text("Frame \(frame?.frameIndex ?? 0)").fontWeight(.semibold)
                Text(isImpact ? "IMPACT" : isPost ? "post" : "pre")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isImpact ? .red : isPost ? .orange : .secondary)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background((isImpact ? Color.red : isPost ? Color.orange : Color.secondary).opacity(0.2))
                    .clipShape(Capsule())
                if let t = frame?.relativeTime {
                    Text(String(format: "%+.1f ms", t * 1000)).foregroundColor(.secondary)
                }
            }
            // Line 2: center
            if let obs {
                if let cx = obs.centerX, let cy = obs.centerY {
                    Text(String(format: "x=%.4f  y=%.4f  conf=%.2f", cx, cy, obs.confidence))
                        .foregroundColor(.green)
                    // Line 3: diameter breakdown
                    let cD = obs.candidateDiameter.map   { String(format:"%.4f",$0) } ?? "—"
                    let rD = obs.maskRefinedDiameter.map { String(format:"%.4f",$0) } ?? "—"
                    let sD = obs.smoothedDiameter.map    { String(format:"%.4f",$0) } ?? "—"
                    Text("candidateD=\(cD)  refinedD=\(rD)  smoothedD=\(sD)  maskPx=\(obs.maskWhitePixelCount)")
                        .foregroundColor(.white.opacity(0.75))
                    Text("reason=\(obs.diameterDebugReason)")
                        .foregroundColor(.white.opacity(0.45))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        Text(obs.debugReason).foregroundColor(.orange).lineLimit(1)
                    }
                }
                // Line 4: ROI debug
                if let dbg = obs.frameDebug {
                    Text("roi: \(dbg.searchCenterSource)  scale=\(String(format:"%.2f",dbg.searchScale))  cands=\(dbg.candidates.count)  acc=\(dbg.candidates.filter{$0.accepted}.count)")
                        .foregroundColor(.white.opacity(0.45))
                }
            } else {
                Text(result == nil ? "Run tracker to see results" : "No observation")
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.white)
        .padding(8)
        .background(Color.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    // MARK: - Mask preview inset

    private func maskPreviewInset(_ obs: BallTrackingTestObservation?) -> some View {
        let sz: CGFloat = 160
        return VStack(spacing: 0) {
            // Header row with legend
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("old").font(.system(size: 8, design: .monospaced)).foregroundColor(.red.opacity(0.85))
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text("new").font(.system(size: 8, design: .monospaced)).foregroundColor(.green.opacity(0.85))
                Spacer()
                Text("Mask Preview")
                    .font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.black.opacity(0.85))

            ZStack {
                Color.black
                if let img = obs?.maskPreviewImage {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: sz, height: sz)

                    Canvas { ctx, size in
                        let half = size.width / 2
                        // Red circle — original candidate diameter
                        if let candD = obs?.maskCandidateDiamInCrop {
                            let r = candD * size.width / 2
                            let c = CGPoint(x: half, y: size.height / 2)
                            ctx.stroke(
                                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                       width: r * 2, height: r * 2)),
                                with: .color(.red.opacity(0.9)), lineWidth: 1.5)
                        }
                        // Green circle — mask-refined diameter
                        if let refD = obs?.maskRefinedDiamInCrop {
                            let r = refD * size.width / 2
                            let c = refinedMaskCenterInCrop(obs, size: size) ?? CGPoint(x: half, y: size.height / 2)
                            ctx.stroke(
                                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                       width: r * 2, height: r * 2)),
                                with: .color(.green.opacity(0.9)), lineWidth: 1.5)
                        }
                        // Center dot
                        let c = refinedMaskCenterInCrop(obs, size: size) ?? CGPoint(x: half, y: size.height / 2)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)),
                                 with: .color(.yellow))
                    }
                    .frame(width: sz, height: sz)
                    .allowsHitTesting(false)
                } else {
                    let msg: String = {
                        if obs == nil            { return "no obs" }
                        if obs?.centerX == nil   { return "no ball" }
                        return "no mask"
                    }()
                    Text(msg)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: sz, height: sz)
                }
            }
            .frame(width: sz, height: sz)
        }
        .background(Color.black.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Frame strip

    private func frameStrip(_ seq: BallTrackingTestSequence) -> some View {
        let detImpact = effectiveImpactIndex
        let fallback  = result?.fallbackImpactFrameIndex ?? seq.impactFrameIndex
        let hasDiff   = result != nil && detImpact != fallback

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(seq.frames.enumerated()), id: \.offset) { i, frame in
                        let fi        = frame.frameIndex
                        let isCurrent = i == currentIndex
                        let isDetImp  = fi == detImpact
                        let isFallImp = hasDiff && fi == fallback
                        let obs = result?.observations.first { $0.frameIndex == fi }

                        let blockColor: Color = isDetImp  ? .yellow
                            : isFallImp ? .yellow.opacity(0.35)
                            : obs?.centerX != nil ? .green
                            : result != nil ? .red
                            : Color(white: 0.25)

                        Button(action: { currentIndex = i }) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(blockColor.opacity(0.85))
                                .frame(width: 14, height: 28)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .stroke(Color.white, lineWidth: isCurrent ? 2 : 0)
                                )
                        }
                        .id(i)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 40)
            .background(Color(white: 0.08))
            .onChange(of: currentIndex) { idx in
                withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(idx, anchor: .center) }
            }
        }
    }

    // MARK: - Navigation bar

    private func navigationBar(_ seq: BallTrackingTestSequence) -> some View {
        let last = max(0, seq.frames.count - 1)
        return HStack(spacing: 12) {
            Button(action: { if currentIndex > 0 { currentIndex -= 1 } }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(currentIndex > 0 ? .white : .white.opacity(0.25))
            }.frame(width: 44, height: 44)
            Slider(value: Binding(
                get: { Double(currentIndex) },
                set: { currentIndex = Int($0.rounded()) }
            ), in: 0...Double(last), step: 1).tint(.white)
            Button(action: { if currentIndex < last { currentIndex += 1 } }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(currentIndex < last ? .white : .white.opacity(0.25))
            }.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(white: 0.10))
    }

    // MARK: - Controls sidebar

    private var controlsSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                trackerModePicker

                TunerSection(title: "Global") {
                    TunerSlider(label: "sampleStride", value: $settings.sampleStride,
                                range: 1...8, format: "%.0f", isInt: true)
                }

                TunerSection(title: "Pre-impact") {
                    TunerSlider(label: "brightness ≥", value: $settings.preBrightnessThreshold,
                                range: 40...240, format: "%.0f", isInt: true)
                    TunerSlider(label: "spread ≤",     value: $settings.preMaxChannelSpread,
                                range: 10...180, format: "%.0f", isInt: true)
                    TunerSlider(label: "minSamples",   value: $settings.preMinBrightSamples,
                                range: 1...100, format: "%.0f", isInt: true)
                    TunerSlider(label: "minW",    value: $settings.preMinNormWidth,  range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "maxW",    value: $settings.preMaxNormWidth,  range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "minH",    value: $settings.preMinNormHeight, range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "maxH",    value: $settings.preMaxNormHeight, range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "minAspect", value: $settings.preMinAspect, range: 0.05...8.0, format: "%.2f")
                    TunerSlider(label: "maxAspect", value: $settings.preMaxAspect, range: 0.05...8.0, format: "%.2f")
                }

                TunerSection(title: "Post-impact") {
                    TunerSlider(label: "brightness ≥", value: $settings.postBrightnessThreshold,
                                range: 40...240, format: "%.0f", isInt: true)
                    TunerSlider(label: "spread ≤",     value: $settings.postMaxChannelSpread,
                                range: 10...180, format: "%.0f", isInt: true)
                    TunerSlider(label: "minSamples",   value: $settings.postMinBrightSamples,
                                range: 1...100, format: "%.0f", isInt: true)
                    TunerSlider(label: "minW",    value: $settings.postMinNormWidth,  range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "maxW",    value: $settings.postMaxNormWidth,  range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "minH",    value: $settings.postMinNormHeight, range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "maxH",    value: $settings.postMaxNormHeight, range: 0.001...0.25, format: "%.3f")
                    TunerSlider(label: "minAspect", value: $settings.postMinAspect, range: 0.05...8.0, format: "%.2f")
                    TunerSlider(label: "maxAspect", value: $settings.postMaxAspect, range: 0.05...8.0, format: "%.2f")
                }

                TunerSection(title: "Search ROI") {
                    TunerSlider(label: "preScale",    value: $settings.preImpactSearchScale, range: 1...40, format: "%.2f")
                    TunerSlider(label: "impactScale", value: $settings.impactSearchScale,    range: 1...40, format: "%.2f")
                    TunerSlider(label: "postBase",    value: $settings.postImpactBaseScale,  range: 1...40, format: "%.2f")
                    TunerSlider(label: "postGrowth",  value: $settings.postImpactScaleGrowth,range: 0...5,  format: "%.2f")
                    TunerSlider(label: "postMax",     value: $settings.postImpactMaxScale,   range: 1...40, format: "%.1f")
                }

                TunerSection(title: "Impact Detection") {
                    TunerSlider(label: "moveThreshold",  value: $settings.impact.movementThresholdNorm,
                                range: 0.001...0.030, format: "%.3f")
                    TunerSlider(label: "confirmFrames",  value: $settings.impact.confirmFrames,
                                range: 1...5, format: "%.0f", isInt: true)
                    TunerSlider(label: "stableWindow",   value: $settings.impact.stableWindowCount,
                                range: 3...20, format: "%.0f", isInt: true)
                }

                TunerSection(title: "Diameter / Mask Refinement") {
                    TunerToggle(label: "enabled",          value: $settings.diameter.enabled)
                    TunerSlider(label: "maskWindowScale",  value: $settings.diameter.localMaskWindowScale,
                                range: 0.5...4.0, format: "%.2f")
                    TunerSlider(label: "minDiameter",      value: $settings.diameter.minDiameterNorm,
                                range: 0.001...0.10, format: "%.3f")
                    TunerSlider(label: "maxDiameter",      value: $settings.diameter.maxDiameterNorm,
                                range: 0.01...0.30, format: "%.3f")
                    TunerToggle(label: "combineMode=max",  value: $settings.diameter.combineModeIsMax)
                    TunerToggle(label: "smoothing",        value: $settings.diameter.smoothingEnabled)
                    TunerSlider(label: "medianWindow",     value: $settings.diameter.smoothingWindowSize,
                                range: 2...15, format: "%.0f", isInt: true)
                    TunerToggle(label: "show candidate rect", value: $settings.showOriginalCandidateBounds)
                    TunerToggle(label: "show mask preview",  value: $settings.showMaskPreview)
                }

                Button(action: { settings = BallTrackingTuningSettings() }) {
                    Text("Reset Defaults")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.orange)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 20)
        }
        .background(Color(white: 0.07))
    }

    private var trackerModePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TRACKER MODE")
                .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.top, 12)
            VStack(spacing: 1) {
                ForEach(FrameNormalizationMode.allCases, id: \.self) { mode in
                    Button(action: { settings.trackingMode = mode }) {
                        HStack {
                            Text(mode.displayName).font(.system(size: 12)).foregroundColor(.white)
                            Spacer()
                            if settings.trackingMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.purple)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(settings.trackingMode == mode ? Color.purple.opacity(0.15) : Color.clear)
                    }
                }
            }
            Divider().background(Color.white.opacity(0.1))
        }
    }

    // MARK: - Actions

    private func loadExport(_ url: URL) {
        do {
            let seq = try loader.loadSequence(from: url)
            sequence = seq; currentIndex = seq.impactFrameIndex; result = nil; loadError = nil
        } catch { loadError = error.localizedDescription }
    }

    private func runTracker() {
        guard let seq = sequence, !isRunning else { return }
        isRunning = true
        let cfg = settings.toConfiguration()
        Task.detached(priority: .userInitiated) {
            let tracker = ExperimentalBallTracker(configuration: cfg)
            let r = tracker.run(on: seq)
            await MainActor.run { self.result = r; self.isRunning = false }
        }
    }

    // MARK: - Geometry helpers

    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let scale = min(containerSize.width / imageSize.width,
                        containerSize.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (containerSize.width - w) / 2,
                      y: (containerSize.height - h) / 2, width: w, height: h)
    }

    private func frameCount(in url: URL) -> Int? {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return contents?.filter { $0.pathExtension == "png" }.count
    }

    private func refinedMaskCenterInCrop(_ obs: BallTrackingTestObservation?, size: CGSize) -> CGPoint? {
        guard let bounds = obs?.maskBoundsRect,
              let crop = obs?.maskCropNormRect,
              crop.width > 0,
              crop.height > 0 else {
            return nil
        }

        return CGPoint(
            x: ((bounds.midX - crop.minX) / crop.width) * size.width,
            y: ((bounds.midY - crop.minY) / crop.height) * size.height
        )
    }
}

// MARK: - Reusable controls

private struct TunerSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
            content()
            Divider().background(Color.white.opacity(0.1)).padding(.top, 6)
        }
    }
}

private struct TunerSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var isInt: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(isInt ? "\(Int(value.rounded()))" : String(format: format, value))
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                    .frame(width: 52, alignment: .trailing)
            }
            Slider(value: $value, in: range).tint(.purple)
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
    }
}

private struct TunerToggle: View {
    let label: String
    @Binding var value: Bool
    var body: some View {
        HStack {
            Text(label).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            Spacer()
            Toggle("", isOn: $value).toggleStyle(.switch).scaleEffect(0.75, anchor: .trailing).labelsHidden()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

// MARK: - Keyboard navigation

private struct KeyboardNavigatorView: UIViewRepresentable {
    let onLeft:  () -> Void
    let onRight: () -> Void
    func makeUIView(context: Context) -> _KeyNavView {
        let v = _KeyNavView(); v.onLeft = onLeft; v.onRight = onRight; return v
    }
    func updateUIView(_ uiView: _KeyNavView, context: Context) {
        uiView.onLeft = onLeft; uiView.onRight = onRight
    }
    class _KeyNavView: UIView {
        var onLeft:  (() -> Void)?
        var onRight: (() -> Void)?
        override var canBecomeFirstResponder: Bool { true }
        override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { becomeFirstResponder() } }
        override var keyCommands: [UIKeyCommand]? {[
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow,  modifierFlags: [], action: #selector(handleLeft)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(handleRight))
        ]}
        @objc private func handleLeft()  { onLeft?() }
        @objc private func handleRight() { onRight?() }
    }
}
#endif
