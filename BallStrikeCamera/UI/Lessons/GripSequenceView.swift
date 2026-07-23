import SwiftUI

/// "Take the grip" — a swipeable photo sequence of real hands forming the grip on the club.
/// The user pages through at their OWN pace (no auto-advance): swipe left for the next frame,
/// right for the previous. Swiping forward past the last frame wraps to the first with a
/// forward slide (it never appears to scroll back through every frame), and a "n/N" counter
/// sits in the top-right.
struct GripSequenceView: View {

    /// Loaded once. Bundled as a folder reference ("GripFrames"); count is discovered so
    /// adding/removing frames needs no code change.
    private static let frames: [UIImage] = (1...40).compactMap { i in
        let name = String(format: "grip_%02d", i)
        let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "GripFrames")
            ?? Bundle.main.url(forResource: name, withExtension: "jpg")
        return url.flatMap { UIImage(contentsOfFile: $0.path) }
    }

    @State private var idx = 0
    /// Direction of the last change, so the slide animation always matches the swipe
    /// (forward even when wrapping 11 → 1).
    @State private var forward = true

    var body: some View {
        Group {
            if Self.frames.isEmpty {
                Rectangle().fill(Color.black.opacity(0.15))
            } else {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: Self.frames[idx])
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(idx)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading),
                            removal:   .move(edge: forward ? .leading : .trailing)))
                    counter
                }
                .clipped()
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 18)
                        .onEnded { value in
                            if value.translation.width <= -18 { advance(1) }
                            else if value.translation.width >= 18 { advance(-1) }
                        }
                )
            }
        }
    }

    private var counter: some View {
        Text("\(idx + 1)/\(Self.frames.count)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.5)))
            .padding(8)
    }

    private func advance(_ dir: Int) {
        let n = Self.frames.count
        guard n > 1 else { return }
        forward = dir > 0
        withAnimation(.easeInOut(duration: 0.32)) {
            idx = (idx + dir + n) % n
        }
    }
}
