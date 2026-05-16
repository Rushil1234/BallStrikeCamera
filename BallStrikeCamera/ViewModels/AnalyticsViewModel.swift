import Foundation

@MainActor
final class AnalyticsViewModel: ObservableObject {

    @Published var allShots: [SavedShot] = []
    @Published var filteredShots: [SavedShot] = []
    @Published var clubFilter: String = "All"
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
            allShots = try await backend.loadShots(userId: userId)
            applyFilter()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setFilter(_ club: String) {
        clubFilter = club
        applyFilter()
    }

    // MARK: - Computed stats

    var availableClubs: [String] {
        let names = Set(allShots.compactMap { $0.clubName })
        return ["All"] + names.sorted()
    }

    var avgCarry: Double {
        average(filteredShots.map { $0.metrics.carryYards })
    }
    var avgBallSpeed: Double {
        average(filteredShots.map { $0.metrics.ballSpeedMph })
    }
    var avgSmashFactor: Double {
        average(filteredShots.map { $0.metrics.smashFactor })
    }
    var avgLaunchAngle: Double {
        average(filteredShots.map { $0.metrics.vlaDegrees })
    }
    var avgSpin: Double {
        average(filteredShots.map { $0.metrics.backspinRpm })
    }
    var dispersion: Double {
        let hlas = filteredShots.map { abs($0.metrics.hlaDegrees) }
        return average(hlas)
    }
    var bestCarry: Double {
        filteredShots.map { $0.metrics.carryYards }.max() ?? 0
    }

    struct ClubStat: Identifiable {
        var id: String { clubName }
        let clubName: String
        let avgCarry: Double
        let avgBallSpeed: Double
        let avgSmash: Double
        let shotCount: Int
    }

    var clubStats: [ClubStat] {
        let named = allShots.filter { $0.clubName != nil }
        let grouped = Dictionary(grouping: named) { $0.clubName! }
        return grouped.map { name, shots in
            ClubStat(
                clubName: name,
                avgCarry:     average(shots.map { $0.metrics.carryYards }),
                avgBallSpeed: average(shots.map { $0.metrics.ballSpeedMph }),
                avgSmash:     average(shots.map { $0.metrics.smashFactor }),
                shotCount:    shots.count
            )
        }
        .sorted { $0.avgCarry > $1.avgCarry }
    }

    // MARK: - Private

    private func applyFilter() {
        if clubFilter == "All" {
            filteredShots = allShots
        } else {
            filteredShots = allShots.filter { $0.clubName == clubFilter }
        }
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
