import SwiftUI

struct ShotCompositeView: View {
    let analysis: ShotAnalysisResult
    let onDismiss: () -> Void

    @State private var compositeImage: UIImage? = nil

    private let renderer = ShotCompositeRenderer()

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
    }

    private func renderComposite() {
        compositeImage = renderer.render(analysis: analysis)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Composite")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

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

    // MARK: - Info panel

    private var infoPanel: some View {
        HStack(spacing: 16) {
            Text("Full-shot composite")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.08))
    }
}
