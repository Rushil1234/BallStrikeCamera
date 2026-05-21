import Foundation

// MARK: - Feed sharing preference (opt-out)

/// Global default for auto-sharing completed activities to the social feed.
/// Defaults to ON; users can disable it in profile settings, and skip individual
/// activities via the per-activity override passed to `FeedAutoPoster`.
enum FeedSharing {
    private static let key = "tc_feed_autoshare_enabled"

    static var autoShareEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Building feed posts from activities

/// Converts completed rounds / sessions into `FeedPost`s. Pure + testable.
enum FeedPostFactory {

    static func post(from round: CourseRound, authorName: String) -> FeedPost? {
        let s = round.scoreSummary
        guard s.totalScore > 0 else { return nil }   // don't post an unscored round
        let diff = s.totalScore - s.totalPar
        let toPar = diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)")
        return FeedPost(
            userId: round.userId,
            authorName: authorName,
            type: .round,
            title: round.courseName.isEmpty ? "Course Round" : round.courseName,
            subtitle: "18 holes · \(toPar) to par",
            metricHighlight: toPar,
            stats: [
                FeedStat(label: "Score", value: "\(s.totalScore)"),
                FeedStat(label: "Fairways", value: "\(s.fairwaysHit)/14"),
                FeedStat(label: "Putts", value: "\(s.totalPutts)")
            ],
            timestamp: round.endedAt ?? Date(),
            linkedRoundId: round.id
        )
    }

    static func post(from session: PracticeSession, authorName: String) -> FeedPost? {
        let s = session.summary
        guard s.shotCount > 0 else { return nil }
        return FeedPost(
            userId: session.userId,
            authorName: authorName,
            type: .session,
            title: session.selectedClubName.map { "\($0) Range Session" } ?? "Range Session",
            subtitle: "\(s.shotCount) shots",
            metricHighlight: "\(Int(s.avgCarry.rounded())) yd",
            stats: [
                FeedStat(label: "Shots", value: "\(s.shotCount)"),
                FeedStat(label: "Avg Carry", value: "\(Int(s.avgCarry.rounded())) yd"),
                FeedStat(label: "Best", value: "\(Int(s.bestCarry.rounded())) yd")
            ],
            timestamp: session.endedAt ?? Date(),
            linkedSessionId: session.id
        )
    }

    static func post(from sim: SimSession, authorName: String) -> FeedPost? {
        guard !sim.shotIds.isEmpty else { return nil }
        let provider = sim.provider == .notConnected ? "Simulator" : sim.provider.rawValue
        return FeedPost(
            userId: sim.userId,
            authorName: authorName,
            type: .session,
            title: "Sim Session",
            subtitle: provider,
            metricHighlight: "\(sim.shotIds.count)",
            stats: [
                FeedStat(label: "Shots", value: "\(sim.shotIds.count)"),
                FeedStat(label: "Source", value: provider)
            ],
            timestamp: sim.endedAt ?? Date(),
            linkedSessionId: sim.id
        )
    }
}

// MARK: - Auto-poster

/// Shares a completed activity to the feed when sharing is enabled. Best-effort:
/// failures are swallowed so they never block finishing a round/session.
enum FeedAutoPoster {

    static func share(round: CourseRound, backend: AppBackend, enabled: Bool = FeedSharing.autoShareEnabled) async {
        guard enabled else { return }
        let name = await authorName(for: round.userId, backend: backend)
        guard let post = FeedPostFactory.post(from: round, authorName: name) else { return }
        try? await backend.saveFeedPost(post)
    }

    static func share(session: PracticeSession, backend: AppBackend, enabled: Bool = FeedSharing.autoShareEnabled) async {
        guard enabled else { return }
        let name = await authorName(for: session.userId, backend: backend)
        guard let post = FeedPostFactory.post(from: session, authorName: name) else { return }
        try? await backend.saveFeedPost(post)
    }

    static func share(sim: SimSession, backend: AppBackend, enabled: Bool = FeedSharing.autoShareEnabled) async {
        guard enabled else { return }
        let name = await authorName(for: sim.userId, backend: backend)
        guard let post = FeedPostFactory.post(from: sim, authorName: name) else { return }
        try? await backend.saveFeedPost(post)
    }

    /// Resolves the poster's display name. RLS allows reading your own profile.
    private static func authorName(for userId: UUID, backend: AppBackend) async -> String {
        if let profile = try? await backend.loadUserProfile(userId: userId), !profile.displayName.isEmpty {
            return profile.displayName
        }
        return "Golfer"
    }
}
