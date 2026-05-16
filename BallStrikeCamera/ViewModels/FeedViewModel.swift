import Foundation

@MainActor
final class FeedViewModel: ObservableObject {

    @Published var posts: [FeedPost] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let backend: AppBackend
    private let userId: UUID

    init(userId: UUID, backend: AppBackend) {
        self.userId  = userId
        self.backend = backend
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            posts = try await backend.loadFeed(userId: userId)
                .sorted { $0.timestamp > $1.timestamp }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func postShot(_ shot: SavedShot, authorName: String) async {
        let post = FeedPost(
            userId: userId,
            authorName: authorName,
            type: .shot,
            title: "\(shot.clubName ?? "Shot") · \(Int(shot.metrics.carryYards)) yd carry",
            subtitle: "Ball speed \(Int(shot.metrics.ballSpeedMph)) mph · Smash \(String(format: "%.2f", shot.metrics.smashFactor))",
            metricHighlight: "\(Int(shot.metrics.carryYards)) yd",
            linkedShotId: shot.id
        )
        do {
            try await backend.saveFeedPost(post)
            posts.insert(post, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func postSession(_ session: PracticeSession, authorName: String) async {
        let post = FeedPost(
            userId: userId,
            authorName: authorName,
            type: .session,
            title: "Range Session · \(session.summary.shotCount) shots",
            subtitle: "Avg carry \(Int(session.summary.avgCarry)) yd · Ball speed \(Int(session.summary.avgBallSpeed)) mph",
            metricHighlight: "\(Int(session.summary.bestCarry)) yd best",
            linkedSessionId: session.id
        )
        do {
            try await backend.saveFeedPost(post)
            posts.insert(post, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePost(id: UUID) async {
        do {
            try await backend.deleteFeedPost(postId: id, userId: userId)
            posts.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
