import Foundation
import CoreLocation

@MainActor
final class CourseRoundViewModel: ObservableObject {

    @Published var activeRound: CourseRound?
    @Published var selectedCourse: GolfCourse?
    @Published var selectedTeeBox: TeeBox?
    @Published var currentHoleIndex: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let backend: AppBackend
    private let userId: UUID
    let courseProvider: CourseProvider
    let location: LocationService

    var currentHole: RoundHole? {
        guard let round = activeRound,
              currentHoleIndex < round.holes.count else { return nil }
        return round.holes[currentHoleIndex]
    }

    var roundActive: Bool { activeRound != nil }

    init(userId: UUID, backend: AppBackend) {
        self.userId  = userId
        self.backend = backend
        self.courseProvider = CourseProviderFactory.make(userId: userId)
        self.location = LocationService()
    }

    // MARK: - Round control

    func startRound(course: GolfCourse, teeBox: TeeBox) async {
        guard activeRound == nil else { return }
        let holes = course.holes.sorted { $0.number < $1.number }.map { hole -> RoundHole in
            RoundHole(holeNumber: hole.number, par: hole.par)
        }
        let round = CourseRound(
            userId: userId,
            courseId: course.id,
            courseName: course.name,
            teeBoxName: teeBox.name,
            holes: holes
        )
        do {
            try await backend.saveRound(round)
            activeRound = round
            selectedCourse = course
            selectedTeeBox = teeBox
            currentHoleIndex = 0
            location.requestPermission()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setScore(holeIndex: Int, score: Int, putts: Int? = nil,
                  fairwayHit: Bool? = nil, gir: Bool? = nil) async {
        guard var round = activeRound,
              holeIndex < round.holes.count else { return }
        round.holes[holeIndex].score = score
        round.holes[holeIndex].putts = putts
        round.holes[holeIndex].fairwayHit = fairwayHit
        round.holes[holeIndex].greenInRegulation = gir
        round.scoreSummary = computeSummary(round)
        activeRound = round
        try? await backend.saveRound(round)
    }

    func addShot(_ shot: SavedShot) async {
        guard var round = activeRound else { return }
        if !round.shotIds.contains(shot.id) {
            round.shotIds.append(shot.id)
        }
        if currentHoleIndex < round.holes.count,
           !round.holes[currentHoleIndex].shotIds.contains(shot.id) {
            round.holes[currentHoleIndex].shotIds.append(shot.id)
        }
        activeRound = round
        try? await backend.saveRound(round)
    }

    func advanceHole() {
        guard let round = activeRound else { return }
        if currentHoleIndex < round.holes.count - 1 {
            currentHoleIndex += 1
        }
    }

    func goToHole(_ index: Int) {
        guard let round = activeRound, index >= 0, index < round.holes.count else { return }
        currentHoleIndex = index
    }

    func finishRound() async {
        guard var round = activeRound else { return }
        round.endedAt = Date()
        round.scoreSummary = computeSummary(round)
        do {
            try await backend.saveRound(round)
        } catch {
            errorMessage = error.localizedDescription
        }
        activeRound = nil
    }

    // MARK: - Distance helper

    func distanceToPin(hole: GolfHole) -> Int? {
        guard let mid = hole.greenCenterCoordinate else { return nil }
        return location.distanceInYards(to: CLLocationCoordinate2D(latitude: mid.latitude, longitude: mid.longitude))
            .map { Int($0.rounded()) }
    }

    // MARK: - Private

    private func computeSummary(_ round: CourseRound) -> RoundScoreSummary {
        let scored = round.holes.filter { $0.score != nil }
        return RoundScoreSummary(
            totalScore:   scored.compactMap { $0.score }.reduce(0, +),
            totalPar:     scored.map { $0.par }.reduce(0, +),
            fairwaysHit:  scored.filter { $0.fairwayHit == true }.count,
            greensInReg:  scored.filter { $0.greenInRegulation == true }.count,
            totalPutts:   scored.compactMap { $0.putts }.reduce(0, +)
        )
    }
}
