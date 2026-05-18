import SwiftUI

// MARK: - Models

private struct FeedPostMock: Identifiable {
    let id = UUID()
    let playerName: String
    let playerInitial: String
    let timeAgo: String
    let activityTitle: String
    let summary: String
    let accentMetric: String?
    let accentLabel: String?
    let accentColor: Color
    let stats: [(label: String, value: String)]
}

// MARK: - View

struct FeedView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var feedMessage: String?

    private let posts: [FeedPostMock] = [
        FeedPostMock(
            playerName: "Noah T.",
            playerInitial: "N",
            timeAgo: "Just now",
            activityTitle: "Range Session · 23 shots",
            summary: "Worked on compressing the 7 iron. Smash factor trending up to 1.44 from 1.40 last week.",
            accentMetric: "162 yd",
            accentLabel: "avg carry",
            accentColor: BSTheme.electricCyan,
            stats: [("116 mph", "ball spd"), ("1.44", "smash"), ("18.2°", "launch")]
        ),
        FeedPostMock(
            playerName: "Landon H.",
            playerInitial: "L",
            timeAgo: "30 min ago",
            activityTitle: "Driver · Personal Best",
            summary: "Finally broke the 280 yd barrier. Swing path cleaned up a ton after lesson yesterday.",
            accentMetric: "284 yd",
            accentLabel: "carry",
            accentColor: BSTheme.fairwayGreen,
            stats: [("152 mph", "ball spd"), ("13.1°", "launch"), ("2,840 rpm", "spin")]
        ),
        FeedPostMock(
            playerName: "Kevin M.",
            playerInitial: "K",
            timeAgo: "1h ago",
            activityTitle: "Range Session · 18 shots",
            summary: "Flushing the irons today. Club path is sitting at 0.6° out — closest to straight I've ever been.",
            accentMetric: "152 yd",
            accentLabel: "7 iron avg",
            accentColor: BSTheme.gold,
            stats: [("108 mph", "ball spd"), ("0.6°", "club path"), ("1.42", "smash")]
        ),
        FeedPostMock(
            playerName: "Marcus R.",
            playerInitial: "M",
            timeAgo: "3h ago",
            activityTitle: "Course Round · 18 Holes",
            summary: "Played Pebble Beach (mock). Irons were dialed in but driver was wild off the tee — 8 yd right avg.",
            accentMetric: "78",
            accentLabel: "net score",
            accentColor: BSTheme.simPurple,
            stats: [("11 / 14", "fairways"), ("9 / 18", "GIR"), ("32", "putts")]
        ),
        FeedPostMock(
            playerName: "Noah T.",
            playerInitial: "N",
            timeAgo: "Yesterday",
            activityTitle: "Driver Carry +12 yd",
            summary: "Distance gain this month: Driver carry improved from 229 yd to 241 yd average. Attributed to better hip rotation.",
            accentMetric: "+12 yd",
            accentLabel: "this month",
            accentColor: BSTheme.fairwayGreen,
            stats: [("241 yd", "current avg"), ("229 yd", "last month")]
        ),
    ]

    var body: some View {
        ZStack {
            BallStrikeBackgroundView()
            ScrollView(showsIndicators: false) {
                VStack(spacing: BSTheme.cardGap) {
                    headerRow
                    ForEach(posts) { post in
                        FeedPostCard(
                            playerName: post.playerName,
                            timeAgo: post.timeAgo,
                            activityTitle: post.activityTitle,
                            summary: post.summary,
                            accentMetric: post.accentMetric,
                            accentLabel: post.accentLabel,
                            accentColor: post.accentColor,
                            stats: post.stats
                        )
                        .overlay(alignment: .topLeading) {
                            // Avatar override with proper initial
                            avatarCircle(initial: post.playerInitial, color: post.accentColor)
                                .padding(BSTheme.hPad)
                        }
                    }
                    caughtUpNote
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, BSTheme.hPad)
                .padding(.top, 4)
            }
        }
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .alert("Feed", isPresented: Binding(
            get: { feedMessage != nil },
            set: { if !$0 { feedMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(feedMessage ?? "")
        }
    }

    private var headerRow: some View {
        HStack {
            Text("Friends & Activity")
                .font(.system(size: 14))
                .foregroundColor(BSTheme.textMuted)
            Spacer()
            Button { feedMessage = "Friend discovery will use the feed backend once social profiles are added." } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.badge.plus")
                    Text("Find Friends")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSTheme.electricCyan)
            }
            .buttonStyle(.plain)
        }
    }

    private func avatarCircle(initial: String, color: Color) -> some View {
        Circle()
            .fill(color.opacity(0.20))
            .frame(width: 40, height: 40)
            .overlay(
                Text(initial)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(color)
            )
    }

    private var caughtUpNote: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(BSTheme.fairwayGreen.opacity(0.60))
            Text("You're all caught up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BSTheme.textMuted)
            Text("Invite friends to see their shots and sessions here.")
                .font(.system(size: 12))
                .foregroundColor(BSTheme.textMuted.opacity(0.60))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
