import Foundation

@MainActor
final class SimSessionViewModel: ObservableObject {

    @Published var activeSession: SimSession?
    @Published var selectedProvider: SimProvider = .ogs
    @Published var lastShotJSON: String?
    @Published var shots: [SavedShot] = []
    @Published var clubs: [UserClub] = []
    @Published var selectedClub: UserClub?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let backend: AppBackend
    private let simOutput = SimOutputService()
    private(set) var userId: UUID

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

    init(userId: UUID, backend: AppBackend) {
        self.userId  = userId
        self.backend = backend
    }

    // MARK: - Clubs

    func loadClubs() async {
        do {
            clubs = try await backend.loadClubs(userId: userId)
                .filter { $0.isActive }
                .sorted { $0.sortOrder < $1.sortOrder }
            if selectedClub == nil {
                selectedClub = clubs.first(where: { $0.name == "7 Iron" }) ?? clubs.first
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

    func addShot(_ shot: SavedShot) async {
        shots.append(shot)
        lastShotJSON = simOutput.jsonString(metrics: shot.metrics, shotNumber: shots.count)
        guard var session = activeSession else { return }
        session.shotIds.append(shot.id)
        session.outputLog.append(lastShotJSON ?? "")
        activeSession = session
        try? await backend.saveSimSession(session)
    }

    func endSession() async {
        guard var session = activeSession else { return }
        session.endedAt = Date()
        do {
            try await backend.saveSimSession(session)
        } catch {
            errorMessage = error.localizedDescription
        }
        await FeedAutoPoster.share(sim: session, backend: backend)
        activeSession = nil
    }

    func endSessionWithDetails(name: String, description: String?, usedOGS: Bool = false) async {
        guard var session = activeSession else { return }
        session.name = name
        session.sessionDescription = description
        session.usedOpenGolfSim = usedOGS
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
