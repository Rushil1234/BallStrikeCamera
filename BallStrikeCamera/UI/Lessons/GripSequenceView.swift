import SwiftUI

/// "Take the grip" — a cross-fading photo sequence of real hands forming the grip on the
/// club. Ten frames (grip_01…grip_10) shot on a fixed camera against turf; cross-dissolving
/// through them reads as one continuous motion. Plays forward, lingers on the finished grip,
/// fades back to the open hand, and loops. Replaces the old procedural 3D grip scene.
struct GripSequenceView: View {

    /// Loaded once. Bundled as a folder reference ("GripFrames"), so the subdirectory is kept.
    private static let frames: [UIImage] = (1...10).compactMap { i in
        let name = String(format: "grip_%02d", i)
        let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "GripFrames")
            ?? Bundle.main.url(forResource: name, withExtension: "jpg")
        return url.flatMap { UIImage(contentsOfFile: $0.path) }
    }

    @State private var idx = 0

    var body: some View {
        ZStack {
            if Self.frames.isEmpty {
                Rectangle().fill(Color.black.opacity(0.15))
            } else {
                ForEach(Self.frames.indices, id: \.self) { i in
                    Image(uiImage: Self.frames[i])
                        .resizable()
                        .scaledToFit()
                        .opacity(i == idx ? 1 : 0)
                }
            }
        }
        .task { await play() }
    }

    private func play() async {
        let n = Self.frames.count
        guard n > 1 else { return }
        while !Task.isCancelled {
            for i in 0..<n {
                withAnimation(.easeInOut(duration: 0.32)) { idx = i }
                let hold = (i == n - 1) ? 1.5 : 0.5      // linger on the finished grip
                try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
                if Task.isCancelled { return }
            }
            withAnimation(.easeInOut(duration: 0.55)) { idx = 0 }   // fade back to the open hand
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
    }
}
