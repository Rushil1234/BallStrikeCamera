#if DEBUG
import SwiftUI

struct BallTrackingTestView: View {
    let onDismiss: () -> Void

    @State private var exports:        [URL]                     = []
    @State private var sequence:       BallTrackingTestSequence? = nil
    @State private var result:         BallTrackingTestResult?   = nil
    @State private var isRunning:      Bool                      = false
    @State private var currentIndex:   Int                       = 0
    @State private var displayMode:    FrameNormalizationMode    = .darkenedHighContrast
    @State private var selectedExport: URL?                      = nil
    @State private var loadError:      String?                   = nil

    private let loader     = TestFrameLoader()
    private let normalizer = FrameNormalizer()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let seq = sequence {
                frameArea(seq)
                statsPanel(seq)
                navigationBar(seq)
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
                Button(action: {
                    sequence = nil; result = nil; selectedExport = nil
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            Text(sequence.map { "Tester · \($0.sourceName)" } ?? "Tracking Tester")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if sequence != nil {
                compactModePicker
                Button(action: runTracker) {
                    Label(isRunning ? "Running…" : "Run", systemImage: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(isRunning ? Color.gray.opacity(0.5) : Color.purple.opacity(0.75))
                        .clipShape(Capsule())
                }
                .disabled(isRunning)
            }

            Button("Done") { onDismiss() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.10))
    }

    private var compactModePicker: some View {
        HStack(spacing: 0) {
            ForEach(FrameNormalizationMode.allCases, id: \.self) { mode in
                Button(action: { displayMode = mode }) {
                    Text(mode.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(displayMode == mode ? .black : .white.opacity(0.65))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
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
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No shot exports found")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Export a shot from the Review screen first.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.35))
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
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.white)
                                        if let count = frameCount(in: url) {
                                            Text("\(count) frames")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(white: 0.10))
                            }
                        }
                    }
                }
                .padding(.top, 1)
            }
        }
    }

    // MARK: - Frame area

    private func frameArea(_ seq: BallTrackingTestSequence) -> some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if currentIndex < seq.frames.count,
                   let img = displayedImage(seq.frames[currentIndex]) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let r = result {
                        Canvas { ctx, size in
                            drawOverlay(ctx: ctx, containerSize: size, image: img,
                                        obs: r.observations.first { $0.frameIndex == seq.frames[currentIndex].frameIndex })
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                    }
                } else {
                    Text("No image").foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .layoutPriority(1)
    }

    private func displayedImage(_ frame: BallTrackingTestFrame) -> UIImage? {
        displayMode == .original ? frame.image
            : normalizer.normalizedImage(from: frame.image, mode: displayMode)
    }

    private func drawOverlay(ctx: GraphicsContext, containerSize: CGSize, image: UIImage,
                              obs: BallTrackingTestObservation?) {
        guard let obs, let cx = obs.centerX, let cy = obs.centerY, let d = obs.diameter else { return }
        let dr = aspectFitRect(imageSize: image.size, in: containerSize)
        let center = CGPoint(x: dr.minX + cx * dr.width, y: dr.minY + cy * dr.height)
        let radius = d * dr.width / 2
        let ballRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.stroke(Path(ellipseIn: ballRect), with: .color(.green), lineWidth: 2)
        let dot = CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)
        ctx.fill(Path(ellipseIn: dot), with: .color(.green))
    }

    // MARK: - Stats panel

    private func statsPanel(_ seq: BallTrackingTestSequence) -> some View {
        let frame = currentIndex < seq.frames.count ? seq.frames[currentIndex] : nil
        let obs   = result?.observations.first { $0.frameIndex == frame?.frameIndex }
        let isImpact = frame?.frameIndex == seq.impactFrameIndex
        let isPost   = (frame?.frameIndex ?? 0) > seq.impactFrameIndex

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Frame \(frame?.frameIndex ?? 0)")
                    .fontWeight(.semibold)
                Text(isImpact ? "IMPACT" : isPost ? "post" : "pre")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isImpact ? .red : isPost ? .orange : .secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background((isImpact ? Color.red : isPost ? Color.orange : Color.secondary).opacity(0.15))
                    .clipShape(Capsule())
                Spacer()
                if let r = result {
                    Text("\(r.trackedCount)/\(r.observations.count) tracked")
                        .foregroundColor(.green)
                    Text(String(format: "avg conf %.2f", r.averageConfidence))
                        .foregroundColor(.secondary)
                }
            }

            if let obs {
                HStack(spacing: 12) {
                    if let cx = obs.centerX, let cy = obs.centerY {
                        Text(String(format: "x=%.4f  y=%.4f", cx, cy))
                        if let d = obs.diameter { Text(String(format: "d=%.4f", d)) }
                        Text(String(format: "conf=%.2f", obs.confidence)).foregroundColor(.green)
                    } else {
                        Label("No detection", systemImage: "xmark.circle.fill").foregroundColor(.red)
                        Text(obs.debugReason).foregroundColor(.orange).lineLimit(1)
                    }
                    Spacer()
                }
            } else {
                Text(result == nil ? "Run tracker to see results" : "No observation")
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.08))
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
            ), in: 0...Double(last), step: 1)
            .tint(.white)

            Button(action: { if currentIndex < last { currentIndex += 1 } }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(currentIndex < last ? .white : .white.opacity(0.25))
            }.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(white: 0.10))
    }

    // MARK: - Actions

    private func loadExport(_ url: URL) {
        do {
            let seq = try loader.loadSequence(from: url)
            sequence = seq
            currentIndex = seq.impactFrameIndex
            result = nil
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func runTracker() {
        guard let seq = sequence, !isRunning else { return }
        isRunning = true
        Task.detached(priority: .userInitiated) {
            let tracker = ExperimentalBallTracker()
            let r = tracker.run(on: seq)
            await MainActor.run {
                self.result = r
                self.isRunning = false
            }
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
}
#endif
