import SwiftUI

struct ShotCompositeView: View {
    let analysis: ShotAnalysisResult
    let onDismiss: () -> Void

    // Default: 11-frame composite, original image mode.
    @State private var compositeStyle: CompositeStyle       = .elevenFrame
    @State private var displayMode:    FrameNormalizationMode = .original
    @State private var compositeImage: UIImage?             = nil

    private let renderer = ShotCompositeRenderer()

    private var frameRange: ClosedRange<Int> {
        compositeStyle.frameRange(impact: analysis.impactFrameIndex,
                                  totalFrames: analysis.frames.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            imageArea
            infoPanel
        }
        .background(Color.black.ignoresSafeArea())
        .tcAppearance()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { renderComposite() }
        .onChange(of: compositeStyle) { _ in renderComposite() }
        .onChange(of: displayMode)    { _ in renderComposite() }
    }

    private func renderComposite() {
        let config = ShotCompositeRenderer.Configuration(style: compositeStyle)
        compositeImage = renderer.render(analysis: analysis, mode: displayMode, configuration: config)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Composite")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            // Style picker: 21F | 11F | Post
            compactPicker(
                options: CompositeStyle.allCases,
                selected: $compositeStyle,
                label: { $0.shortName }
            )

            // Image mode picker: Original | Darkened | Brightened
            compactPicker(
                options: FrameNormalizationMode.allCases,
                selected: $displayMode,
                label: { $0.displayName }
            )

            Button("Done") {
                print("ShotCompositeView dismissed")
                onDismiss()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.blue)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.10))
    }

    // Generic segmented-style pill picker.
    private func compactPicker<T: Hashable>(
        options: [T],
        selected: Binding<T>,
        label: @escaping (T) -> String
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button(action: { selected.wrappedValue = option }) {
                    Text(label(option))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(selected.wrappedValue == option ? .black : .white.opacity(0.65))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(selected.wrappedValue == option ? Color.white : Color.clear)
                }
            }
        }
        .background(Color.white.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    // MARK: - Image area (pure blended composite — no overlays)

    private var imageArea: some View {
        Group {
            if let img = compositeImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
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

    // MARK: - Info panel (all text lives here, outside the image)

    private var infoPanel: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(compositeStyle.rawValue) composite")
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
