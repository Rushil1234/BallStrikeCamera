import SwiftUI

struct ShotCompositeView: View {
    let analysis: ShotAnalysisResult
    let onDismiss: () -> Void

    @State private var displayMode: FrameNormalizationMode = .darkenedHighContrast
    @State private var compositeImage: UIImage? = nil

    private let renderer = ShotCompositeRenderer()
    private let config   = ShotCompositeRenderer.Configuration()

    private var frameRange: ClosedRange<Int> {
        let impact = analysis.impactFrameIndex
        let first  = max(0, impact - config.preCount)
        let last   = min(analysis.frames.count - 1, impact + config.postCount)
        return first...last
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            imageArea
            infoPanel
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            print("Default review mode: DarkenedHighContrast")
            renderComposite()
        }
        .onChange(of: displayMode) { _ in
            renderComposite()
        }
    }

    private func renderComposite() {
        compositeImage = renderer.render(analysis: analysis, mode: displayMode, configuration: config)
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Composite")
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

            Button("Done") {
                print("ShotCompositeView dismissed")
                onDismiss()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.blue)
            .padding(.leading, 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.10))
    }

    // Pure blended image — no overlays drawn on it.
    private var imageArea: some View {
        Group {
            if let img = compositeImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Rendering composite…")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black)
        .frame(maxWidth: .infinity)
        .layoutPriority(1)
    }

    // All text lives here, outside the image.
    private var infoPanel: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("21-frame composite")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text("Frames \(frameRange.lowerBound)–\(frameRange.upperBound)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("Mode: \(displayMode.displayName)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.08))
    }
}
