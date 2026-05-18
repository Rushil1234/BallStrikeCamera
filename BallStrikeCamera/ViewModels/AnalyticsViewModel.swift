import Foundation

@MainActor
final class AnalyticsViewModel: ObservableObject {

    @Published var allShots: [SavedShot] = []
    @Published var filteredShots: [SavedShot] = []
    @Published var clubs: [UserClub] = []
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
            async let shots = backend.loadShots(userId: userId)
            async let bag = backend.loadClubs(userId: userId)
            allShots = try await shots
            clubs = try await bag
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
        var names = Set(clubs.map(\.name))
        allShots.compactMap { $0.clubName }.forEach { names.insert($0) }
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
        let grouped = Dictionary(grouping: availableClubs.dropFirst().flatMap { club in
            shotsFor(club).map { (club, $0) }
        }) { $0.0 }
        return grouped.map { name, values in
            let shots = values.map(\.1)
            return ClubStat(
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
            filteredShots = shotsFor(clubFilter)
        }
    }

    private func shotsFor(_ club: String) -> [SavedShot] {
        let clubIds = Set(clubs.filter { $0.name == club }.map(\.id))
        return allShots.filter { shot in
            if shot.clubName == club { return true }
            guard let clubId = shot.clubId else { return false }
            return clubIds.contains(clubId)
        }
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
