import SwiftUI

/// Scrubbing slow-motion replay of a shot's captured frame burst.
/// Frames are written locally at capture time by ShotPersistenceService;
/// callers should fall back to the composite image when `framesExist` is false.
struct ReplayPlayerView: View {
    let framesDir: URL

    @State private var frames: [UIImage] = []
    @State private var index: Double = 0
    @State private var playing = false
    @State private var loaded = false

    static func frameURLs(in dir: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.lastPathComponent.hasPrefix("frame_") && $0.pathExtension == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func framesExist(in dir: URL) -> Bool {
        !frameURLs(in: dir).isEmpty
    }

    private var currentFrame: UIImage? {
        guard !frames.isEmpty else { return nil }
        return frames[min(frames.count - 1, max(0, Int(index)))]
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = currentFrame {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                    } else if loaded {
                        Text("No replay frames")
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textMuted)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)

                if !frames.isEmpty {
                    Text("SLOW-MO")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.1)
                        .foregroundColor(TCTheme.gold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(8)
                }
            }
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { playing.toggle() }

            if frames.count > 1 {
                HStack(spacing: 12) {
                    Button { playing.toggle() } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(TCTheme.gold)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)

                    Slider(value: $index, in: 0...Double(frames.count - 1), step: 1) { editing in
                        if editing { playing = false }
                    }
                    .tint(TCTheme.gold)

                    Text("\(Int(index) + 1)/\(frames.count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundColor(TCTheme.textMuted)
                        .frame(minWidth: 44, alignment: .trailing)
                }
            }
        }
        .task { await loadFrames() }
        .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { _ in
            guard playing, frames.count > 1 else { return }
            index = (index + 1).truncatingRemainder(dividingBy: Double(frames.count))
        }
    }

    private func loadFrames() async {
        guard !loaded else { return }
        let urls = Self.frameURLs(in: framesDir)
        let decoded: [UIImage] = await Task.detached(priority: .userInitiated) {
            urls.compactMap { UIImage(contentsOfFile: $0.path) }
        }.value
        frames = decoded
        loaded = true
        playing = decoded.count > 1
    }
}
