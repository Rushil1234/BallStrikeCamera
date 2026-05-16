import Foundation

@MainActor
final class SimSessionViewModel: ObservableObject {

    @Published var activeSession: SimSession?
    @Published var selectedProvider: SimProvider = .notConnected
    @Published var lastShotJSON: String?
    @Published var shots: [SavedShot] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let backend: AppBackend
    private let simOutput = SimOutputService()
    private let userId: UUID

    var sessionActive: Bool { activeSession != nil }

    init(userId: UUID, backend: AppBackend) {
        self.userId  = userId
        self.backend = backend
    }

    func startSession() async {
        guard activeSession == nil else { return }
        let session = SimSession(userId: userId, provider: selectedProvider)
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
        activeSession = nil
    }
}
