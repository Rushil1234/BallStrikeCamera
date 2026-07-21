import Foundation

@MainActor
final class RangeSessionViewModel: ObservableObject {

    @Published var activeSession: PracticeSession?
    @Published var shots: [SavedShot] = []
    @Published var selectedClub: UserClub?
    @Published var clubs: [UserClub] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let backend: AppBackend
    private let userId: UUID

    /// Auto-stop a session after this much inactivity (no new shot).
    private let idleTimeout: TimeInterval = 15 * 60
    private var idleTask: Task<Void, Never>?

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

    private var discardObserver: NSObjectProtocol?

    init(userId: UUID, backend: AppBackend) {
        self.userId  = userId
        self.backend = backend
        discardObserver = NotificationCenter.default.addObserver(
            forName: .tcShotDiscarded, object: nil, queue: .main) { [weak self] note in
            guard let id = note.userInfo?["id"] as? UUID else { return }
            Task { @MainActor in self?.dropShot(id) }
        }
    }

    deinit { if let o = discardObserver { NotificationCenter.default.removeObserver(o) } }

    /// Remove a discarded (bad) shot from the active session so counts stay correct.
    func dropShot(_ id: UUID) {
        shots.removeAll { $0.id == id }
        guard var s = activeSession, s.shotIds.contains(id) else { return }
        s.shotIds.removeAll { $0 == id }
        s.summary = summary
        activeSession = s
        Task { try? await backend.saveRangeSession(s) }
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
            selectedClubName: selectedClub?.name
        )
        // Set immediately so the UI is interactive regardless of network status.
        activeSession = session
        shots = []
        do {
            try await backend.saveRangeSession(session)
        } catch {
            errorMessage = error.localizedDescription
            // Keep activeSession — user can still hit shots; final save retries on end.
        }
    }

    /// Ensures a session is open so every saved shot belongs to one (autostart).
    func ensureSessionStarted() async {
        if activeSession == nil { await startSession() }
    }

    func addShot(_ shot: SavedShot) async {
        await ensureSessionStarted()           // every shot must live in a session
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
        scheduleIdleAutoStop()
    }

    /// (Re)arm the inactivity timer. If no new shot arrives within `idleTimeout`, the session
    /// auto-ends (saved if it has shots, discarded if empty).
    private func scheduleIdleAutoStop() {
        idleTask?.cancel()
        let timeout = idleTimeout
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.endSession()
        }
    }

    func endSession() async {
        idleTask?.cancel(); idleTask = nil
        guard var session = activeSession else { return }
        guard !session.shotIds.isEmpty else { await discardSession(); return }
        session.endedAt = Date()
        session.summary = summary
        do {
            try await backend.saveRangeSession(session)
        } catch {
            errorMessage = error.localizedDescription
        }
        activeSession = nil
    }

    func endSessionWithDetails(name: String, description: String?) async {
        guard var session = activeSession else { return }
        guard !session.shotIds.isEmpty else { await discardSession(); return }
        session.name = name
        session.sessionDescription = description
        session.endedAt = Date()
        session.summary = summary
        do {
            try await backend.saveRangeSession(session)
        } catch {
            errorMessage = error.localizedDescription
        }
        activeSession = nil
    }

    func discardSession() async {
        idleTask?.cancel(); idleTask = nil
        if let session = activeSession {
            try? await backend.deleteRangeSession(sessionId: session.id, userId: userId)
        }
        activeSession = nil
        shots = []
    }

    func computeDefaultName() async -> String {
        let existing = (try? await backend.loadRangeSessions(userId: userId)) ?? []
        return "Range Session \(existing.count + 1)"
    }
}
