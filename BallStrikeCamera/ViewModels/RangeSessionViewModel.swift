import Foundation

@MainActor
final class RangeSessionViewModel: ObservableObject {

    @Published var activeSession: PracticeSession?
    @Published var shots: [SavedShot] = []
    @Published var selectedClub: UserClub?
    @Published var clubs: [UserClub] = []
    @Published var saveOriginalFrames = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let backend: AppBackend
    private let userId: UUID

    var sessionActive: Bool { activeSession != nil }

    var summary: SessionSummary {
        guard !shots.isEmpty else { return SessionSummary() }
        let carries    = shots.map { $0.metrics.carryYards }
        let totals     = shots.map { $0.metrics.totalYards }
        let speeds     = shots.map { $0.metrics.ballSpeedMph }
        let hlas       = shots.map { abs($0.metrics.hlaDegrees) }
        return SessionSummary(
            shotCount:    shots.count,
            avgCarry:     carries.reduce(0, +) / Double(carries.count),
            avgTotal:     totals.reduce(0, +)  / Double(totals.count),
            avgBallSpeed: speeds.reduce(0, +)  / Double(speeds.count),
            bestCarry:    carries.max() ?? 0,
            hlaDispersion: hlas.reduce(0, +)   / Double(hlas.count)
        )
    }

    init(userId: UUID, backend: AppBackend) {
        self.userId  = userId
        self.backend = backend
    }

    func loadClubs() async {
        do {
            clubs = try await backend.loadClubs(userId: userId)
                .filter { $0.isActive }
                .sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startSession() async {
        guard activeSession == nil else { return }
        let session = PracticeSession(
            userId: userId,
            selectedClubId: selectedClub?.id,
            selectedClubName: selectedClub?.name,
            saveOriginalFrames: saveOriginalFrames
        )
        do {
            try await backend.saveRangeSession(session)
            activeSession = session
            shots = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addShot(_ shot: SavedShot) async {
        shots.append(shot)
        guard var session = activeSession else { return }
        if session.selectedClubId == nil {
            session.selectedClubId = shot.clubId
            session.selectedClubName = shot.clubName
        }
        session.shotIds.append(shot.id)
        session.summary = summary
        activeSession = session
        try? await backend.saveRangeSession(session)
    }

    func endSession() async {
        guard var session = activeSession else { return }
        session.endedAt = Date()
        session.summary = summary
        do {
            try await backend.saveRangeSession(session)
        } catch {
            errorMessage = error.localizedDescription
        }
        // Auto-share the completed session to the social feed (opt-out in settings).
        await FeedAutoPoster.share(session: session, backend: backend)
        activeSession = nil
    }

    func discardSession() async {
        if let session = activeSession {
            try? await backend.deleteRangeSession(sessionId: session.id, userId: userId)
        }
        activeSession = nil
        shots = []
    }
}
