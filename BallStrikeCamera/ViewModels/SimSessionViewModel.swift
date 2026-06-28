import Foundation

@MainActor
final class SimSessionViewModel: ObservableObject {

    @Published var activeSession: SimSession?
    @Published var selectedProvider: SimProvider = .ogs
    @Published var lastShotJSON: String?
    @Published var shots: [SavedShot] = []
    @Published var clubs: [UserClub] = []
    @Published var selectedClub: UserClub? { didSet { ClubPreference.remember(selectedClub) } }
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let backend: AppBackend
    private let simOutput = SimOutputService()
    private(set) var userId: UUID

    private let idleTimeout: TimeInterval = 15 * 60
    private var idleTask: Task<Void, Never>?

    var sessionActive: Bool { activeSession != nil }

    var summary: SessionSummary {
        guard !shots.isEmpty else { return SessionSummary() }
        let carries  = shots.map { $0.metrics.carryYards }
        let speeds   = shots.map { $0.metrics.ballSpeedMph }
        return SessionSummary(
            shotCount:    shots.count,
            avgCarry:     carries.reduce(0, +) / Double(carries.count),
            avgTotal:     0,
            avgBallSpeed: speeds.reduce(0, +)  / Double(speeds.count),
            bestCarry:    carries.max() ?? 0,
            hlaDispersion: 0
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
        activeSession = s
        Task { try? await backend.saveSimSession(s) }
    }

    // MARK: - Clubs

    func loadClubs() async {
        do {
            clubs = try await backend.loadClubs(userId: userId)
                .filter { $0.isActive }
                .sorted { $0.sortOrder < $1.sortOrder }
            if selectedClub == nil {
                selectedClub = ClubPreference.preferred(in: clubs)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Session lifecycle

    func startSession(provider: SimProvider = .ogs, usedOGS: Bool = false) async {
        guard activeSession == nil else { return }
        var session = SimSession(userId: userId, provider: provider)
        session.usedOpenGolfSim = usedOGS
        do {
            try await backend.saveSimSession(session)
            activeSession = session
            shots = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Ensures a session is open so every saved shot belongs to one (autostart).
    func ensureSessionStarted() async {
        if activeSession == nil { await startSession(provider: selectedProvider) }
    }

    func addShot(_ shot: SavedShot) async {
        await ensureSessionStarted()
        shots.append(shot)
        lastShotJSON = simOutput.jsonString(metrics: shot.metrics, shotNumber: shots.count)
        guard var session = activeSession else { return }
        session.shotIds.append(shot.id)
        session.outputLog.append(lastShotJSON ?? "")
        activeSession = session
        try? await backend.saveSimSession(session)
        scheduleIdleAutoStop()
    }

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
        do {
            try await backend.saveSimSession(session)
        } catch {
            errorMessage = error.localizedDescription
        }
        await FeedAutoPoster.share(sim: session, backend: backend)
        activeSession = nil
    }

    func endSessionWithDetails(name: String, description: String?, usedOGS: Bool = false,
                               provider: SimProvider? = nil) async {
        guard var session = activeSession else { return }
        guard !session.shotIds.isEmpty else { await discardSession(); return }
        session.name = name
        session.sessionDescription = description
        session.usedOpenGolfSim = usedOGS
        // Resolve the game at save time too (a Bluetooth bridge may only report
        // GSPro vs OGS after the session has already started).
        if let provider, provider != .notConnected {
            session.provider = provider
        }
        session.endedAt = Date()
        do {
            try await backend.saveSimSession(session)
        } catch {
            errorMessage = error.localizedDescription
        }
        await FeedAutoPoster.share(sim: session, backend: backend)
        activeSession = nil
    }

    func discardSession() async {
        idleTask?.cancel(); idleTask = nil
        if let session = activeSession {
            try? await backend.deleteSimSession(sessionId: session.id, userId: userId)
        }
        activeSession = nil
        shots = []
    }

    func computeDefaultName() async -> String {
        let existing = (try? await backend.loadSimSessions(userId: userId)) ?? []
        return "Sim Session \(existing.count + 1)"
    }

    // MARK: - Simulate shot

    /// Generates a simulated shot, sends to OGS if connected, saves to active session.
    func addSimulatedShot() async -> SavedShot {
        let testShot = OpenGolfSimShot.testShot
        // Rough carry estimate: ballSpeed × sin(2 × launchAngle) × 2.25
        let launchRad = testShot.verticalLaunchAngle * .pi / 180
        let estCarry  = testShot.ballSpeed * sin(2 * launchRad) * 2.25

        var metrics = SavedShotMetrics()
        metrics.carryYards     = estCarry
        metrics.totalYards     = estCarry * 1.07
        metrics.ballSpeedMph   = testShot.ballSpeed
        metrics.vlaDegrees     = testShot.verticalLaunchAngle
        metrics.hlaDegrees     = abs(testShot.horizontalLaunchAngle)
        metrics.hlaDirection   = testShot.horizontalLaunchAngle < 0 ? "left"
                               : testShot.horizontalLaunchAngle > 0 ? "right" : ""
        metrics.backspinRpm    = testShot.spinSpeed * 0.93
        metrics.sidespinRpm    = testShot.spinSpeed * 0.07
        metrics.spinAxisDegrees = testShot.spinAxis

        var shot = SavedShot(
            userId:    userId,
            source:    .simulated,
            mode:      .sim,
            clubId:    selectedClub?.id,
            clubName:  selectedClub?.name,
            metrics:   metrics,
            sessionId: activeSession?.id
        )

        try? await backend.saveShot(shot)
        await addShot(shot)
        return shot
    }
}
