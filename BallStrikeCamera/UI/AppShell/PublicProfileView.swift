import SwiftUI

/// A read-only look at another golfer's profile — opened by tapping their name or
/// avatar on a feed post (Strava/Beli-style). Shows a quick stat line and their
/// recent shared activities. Sourced from the posts already loaded in the feed,
/// so it needs no extra backend access.
struct PublicProfileView: View {
    let userId: UUID
    let displayName: String
    let homeCourse: String?
    let posts: [FeedPost]

    @Environment(\.dismiss) private var dismiss

    private var rounds: Int { posts.filter { $0.type == .round }.count }
    private var sessions: Int { posts.filter { $0.type == .session }.count }
    private var bestCarry: Int {
        posts.compactMap { $0.activityMetadata?.bestCarryYards }.max() ?? 0
    }

    var body: some View {
        ZStack {
            TrueCarryBackground(pattern: .plain)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    statStrip
                    activities
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 8)
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .frame(width: 32, height: 32)
                        .background(TCTheme.panel)
                        .clipShape(Circle())
                }
            }
            AvatarCircle(name: displayName, size: 88)
            Text(displayName)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            if let hc = homeCourse, !hc.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "flag.fill").font(.system(size: 11))
                    Text(hc.components(separatedBy: " ~ ").first ?? hc)
                        .font(.system(size: 13))
                }
                .foregroundColor(TCTheme.textMuted)
            }
        }
    }

    private var statStrip: some View {
        HStack(spacing: 0) {
            stat("\(rounds)", "Rounds")
            divider
            stat("\(sessions)", "Sessions")
            divider
            stat(bestCarry > 0 ? "\(bestCarry)" : "--", "Best Carry", unit: bestCarry > 0 ? "yd" : "")
        }
        .padding(.vertical, 16)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
    }

    private func stat(_ value: String, _ label: String, unit: String = "") -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(TCTheme.textPrimary)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 11, weight: .semibold)).foregroundColor(TCTheme.textMuted)
                }
            }
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(TCTheme.border).frame(width: 1, height: 30)
    }

    @ViewBuilder private var activities: some View {
        HStack {
            Text("Recent activity")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            Spacer()
        }
        if posts.isEmpty {
            Text("No shared activities yet.")
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
        } else {
            ForEach(posts) { post in
                HStack(spacing: 12) {
                    Image(systemName: post.type == .round ? "flag.fill" : "scope")
                        .font(.system(size: 14))
                        .foregroundColor(TCTheme.gold)
                        .frame(width: 34, height: 34)
                        .background(TCTheme.gold.opacity(0.12))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(TCTheme.textPrimary)
                            .lineLimit(1)
                        Text(post.subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textMuted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(post.metricHighlight)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(TCTheme.gold)
                }
                .padding(12)
                .background(TCTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
            }
        }
    }
}
