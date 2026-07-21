import SwiftUI
import UIKit

// MARK: - Profile share card (Strava/Beli-style)

/// The inputs a shareable profile card needs — small + explicit so both a public
/// profile and your own profile can render the same card.
struct ProfileShareData {
    var userId: UUID
    var name: String
    var homeCourse: String?
    var handicap: String?     // e.g. "8.4"; nil when not established
    var rounds: Int
    var sessions: Int
    var bestCarry: Int        // yards; 0 = unknown

    var initials: String {
        let chars = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return chars.isEmpty ? "?" : String(chars).uppercased()
    }
}

/// A shareable TrueCarry profile card on the fixed brand-dark capture palette, so
/// it renders identically in any chat. Same visual language as the activity card.
struct ProfileShareCardView: View {
    let data: ProfileShareData

    private var stats: [(String, String, String)] {
        var s: [(String, String, String)] = []
        if let h = data.handicap { s.append(("Handicap", h, "")) }
        s.append(("Rounds", "\(data.rounds)", ""))
        s.append(("Sessions", "\(data.sessions)", ""))
        if data.bestCarry > 0 { s.append(("Best Carry", "\(data.bestCarry)", "yd")) }
        return s
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TCWordmark(size: 20, onDark: true)
                Spacer()
                Text("GOLFER")
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

            // Avatar
            ZStack {
                Circle().fill(TCTheme.captureGold.opacity(0.14))
                Circle().strokeBorder(TCTheme.captureGold.opacity(0.5), lineWidth: 1.5)
                Text(data.initials)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(TCTheme.captureGold)
            }
            .frame(width: 96, height: 96)
            .padding(.top, 26)

            Text(data.name)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundColor(TCTheme.captureBone)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.top, 14)
                .padding(.horizontal, 24)

            if let hc = data.homeCourse, !hc.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "flag.fill").font(.system(size: 11))
                    Text(hc.components(separatedBy: " ~ ").first ?? hc)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(TCTheme.captureSilver)
                .padding(.top, 6)
            }

            Rectangle()
                .fill(TCTheme.captureBone.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 34)
                .padding(.top, 22)

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                    VStack(spacing: 4) {
                        Text(s.0.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(TCTheme.captureBone.opacity(0.5))
                            .lineLimit(1)
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text(s.1)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(TCTheme.captureBone)
                                .lineLimit(1).minimumScaleFactor(0.6)
                            if !s.2.isEmpty {
                                Text(s.2)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(TCTheme.captureBone.opacity(0.55))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            HStack(spacing: 6) {
                Text("Verified carries")
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
                    center: .init(x: 0.5, y: 0.35), startRadius: 10, endRadius: 260
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

/// Renders the profile card to a temp PNG file URL for the share sheet (3× scale).
@MainActor
func renderProfileShareCard(data: ProfileShareData) -> URL? {
    let card = ProfileShareCardView(data: data).padding(14)
    let renderer = ImageRenderer(content: card)
    renderer.scale = 2   // 720pt-wide PNG — crisp in chat, ~2.25× faster than 3×
    renderer.isOpaque = false
    guard let image = renderer.uiImage, let pngData = image.pngData() else { return nil }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("truecarry-profile-\(data.userId.uuidString).png")
    do { try pngData.write(to: url); return url } catch { return nil }
}
