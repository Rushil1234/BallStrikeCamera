import SwiftUI

/// "Take the grip" — a swipeable photo sequence of real hands forming the grip on the club.
/// Fixed-camera frames (grip_01…grip_NN) shown in a paged carousel: the user can swipe
/// through them manually, and it also auto-advances every few seconds on its own. Page dots
/// show progress. Loops back to the first frame.
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
    // Auto-advance every 2.5s; a manual swipe just moves `idx` and the timer carries on.
    private let auto = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if Self.frames.isEmpty {
                Rectangle().fill(Color.black.opacity(0.15))
            } else {
                TabView(selection: $idx) {
                    ForEach(Self.frames.indices, id: \.self) { i in
                        Image(uiImage: Self.frames[i])
                            .resizable()
                            .scaledToFit()
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            }
        }
        .onReceive(auto) { _ in
            guard Self.frames.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                idx = (idx + 1) % Self.frames.count
            }
        }
    }
}
