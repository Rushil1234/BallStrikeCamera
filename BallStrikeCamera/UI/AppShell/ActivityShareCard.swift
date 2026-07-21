import SwiftUI
import UIKit

// MARK: - Activity share card (Strava-style)

/// A shareable TrueCarry card for a feed post — the full session at a glance, on
/// the fixed brand-dark capture palette so it renders identically in any chat.
/// Replaces the old plain-text share.
struct ActivityShareCardView: View {
    let post: FeedPost

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f
    }()

    private var kindLabel: String {
        switch post.type {
        case .round:   return "ROUND"
        case .session: return "SESSION"
        default:       return "TRUE CARRY"
        }
    }

    /// Full stat line derived from the activity metadata (falls back to the post's own stats).
    private var stats: [(String, String)] {
        guard let m = post.activityMetadata else {
            return post.stats.prefix(4).map { ($0.label, $0.value) }
        }
        switch m.kind {
        case .round:
            return [
                ("To Par", m.scoreToPar.map { $0 == 0 ? "E" : ($0 > 0 ? "+\($0)" : "\($0)") } ?? "--"),
                ("Score", m.totalScore.map { "\($0)" } ?? "--"),
                ("Fairways", m.fairwaysHit.map { "\($0)" } ?? "--"),
                ("Putts", m.putts.map { "\($0)" } ?? "--"),
            ]
        case .range:
            return [
                ("Shots", m.shotCount.map { "\($0)" } ?? "--"),
                ("Avg Carry", m.averageCarryYards.map { "\($0) yd" } ?? "--"),
                ("Best", m.bestCarryYards.map { "\($0) yd" } ?? "--"),
                ("Ball Speed", m.averageBallSpeedMph.map { "\($0) mph" } ?? "--"),
            ]
        case .sim:
            return [
                ("Shots", m.shotCount.map { "\($0)" } ?? "--"),
                ("Source", m.providerName ?? "Simulator"),
            ]
        case .manual:
            return post.stats.prefix(4).map { ($0.label, $0.value) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TCWordmark(size: 20, onDark: true)
                Spacer()
                Text(kindLabel)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundColor(TCTheme.captureGold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(TCTheme.captureGold.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(TCTheme.captureGold.opacity(0.4), lineWidth: 1))
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)

            VStack(spacing: 4) {
                Text(post.title)
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundColor(TCTheme.captureBone)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if !post.subtitle.isEmpty {
                    Text(post.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TCTheme.captureSilver)
                }
            }
            .padding(.top, 26)
            .padding(.horizontal, 24)

            Text(post.metricHighlight)
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundColor(TCTheme.captureBone)
                .padding(.top, 10)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Rectangle()
                .fill(TCTheme.captureBone.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 34)
                .padding(.top, 20)

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                    VStack(spacing: 4) {
                        Text(s.0.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(TCTheme.captureBone.opacity(0.5))
                            .lineLimit(1)
                        Text(s.1)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(TCTheme.captureBone)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            HStack(spacing: 6) {
                Text(post.authorName)
                Text("·")
                Text(Self.dateFormatter.string(from: post.timestamp))
                Text("·")
                Text("truecarrygolf.com")
            }
            .font(.system(size: 11))
            .foregroundColor(TCTheme.captureBone.opacity(0.45))
            .padding(.top, 22)
            .padding(.bottom, 26)
        }
        .frame(width: 360)
        .background(
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.137, green: 0.196, blue: 0.157), TCTheme.captureBg],
                    startPoint: .top, endPoint: .bottom
                )
                RadialGradient(
                    colors: [TCTheme.captureBone.opacity(0.08), .clear],
                    center: .init(x: 0.5, y: 0.4), startRadius: 10, endRadius: 260
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(TCTheme.captureGold.opacity(0.25), lineWidth: 1)
        )
    }
}

/// Renders the activity card to a UIImage (3× for crisp chat previews), then to a
/// temp PNG file URL suitable for the share sheet. Returns nil on failure.
@MainActor
func renderActivityShareCard(post: FeedPost) -> URL? {
    let card = ActivityShareCardView(post: post).padding(14)
    let renderer = ImageRenderer(content: card)
    renderer.scale = 3
    renderer.isOpaque = false
    guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("truecarry-\(post.id.uuidString).png")
    do { try data.write(to: url); return url } catch { return nil }
}
