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
    @Published var courseUnavailable: CourseAvailabilityReport?
    /// Best tier the current course can be played in (rangefinder / scorecard-only / full GPS).
    @Published var courseTier: CourseModeTier = .fullGPS
    /// Non-blocking note shown when the course plays in a degraded tier; nil for full GPS.
    @Published var degradedTierNote: String?

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

    // MARK: - NFC Shot Tracking

    /// Records an NFC club tap at the user's current GPS position for the active hole.
    func recordNFCShot(club: UserClub) {
        guard var round = activeRound,
              let coord = location.currentLocation else { return }
        let holeNum = currentHole?.holeNumber ?? (currentHoleIndex + 1)
        let shot = NFCShot(
            clubId:      club.id,
            clubName:    club.name,
            holeNumber:  holeNum,
            latitude:    coord.latitude,
            longitude:   coord.longitude
        )
        round.nfcShots.append(shot)
        activeRound = round
    }

    /// Returns the NFC-inferred stroke count for a hole, capped at par + 10.
    func inferredStrokes(forHole holeNumber: Int) -> Int? {
        guard let round = activeRound else { return nil }
        let shots = round.nfcShots.filter { $0.holeNumber == holeNumber }
        guard !shots.isEmpty else { return nil }
        let par = round.holes.first(where: { $0.holeNumber == holeNumber })?.par ?? 4
        return min(shots.count, par + 10)
    }

    init(userId: UUID, backend: AppBackend) {
        self.userId  = userId
        self.backend = backend
        self.courseProvider = CourseProviderFactory.make(userId: userId)
        self.location = LocationService()
    }

    // MARK: - Round control

    /// Enriches the course with real OSM geometry first, then starts the round.
    /// Falls back to the unenriched course on any OSM error so a round can still be played.
    func startRoundEnriching(course: GolfCourse, teeBox: TeeBox) async {
        guard activeRound == nil else { return }
        // Start GPS acquisition immediately so the blue dot + distances are ready by the
        // time geometry finishes loading. Do NOT gate this behind the (slow) OSM enrich.
        location.requestPermission()
        location.startUpdating()
        isLoading = true
        courseUnavailable = nil
        errorMessage = nil
        // Merge GolfCourseAPI scorecard (accurate par/yardage/handicap) with OSM geometry.
        let enriched = await CourseDataAggregator.shared.enrich(course, backend: backend)
        // The user picked a generic tee from MapKit search; map it to the authoritative
        // tee box on the enriched course so per-hole yardages resolve correctly.
        let resolvedTee = CourseDataAggregator.shared.resolveTeeBox(teeBox, in: enriched)
        let readiness = CourseAvailability.evaluateReadiness(course: enriched, teeBox: resolvedTee)
        courseTier = readiness.tier

        // Log + queue backfill for anything short of full verified GPS so coverage keeps improving.
        if readiness.tier != .fullGPS, let report = readiness.report {
            CourseAvailability.recordUnavailable(report, teeBox: resolvedTee)
            await CourseDataAggregator.shared.queueBackfill(
                enriched,
                backend: backend,
                reason: report.reasonCode
            )
        }

        // Only truly empty courses block. Everything else plays in its best tier.
        guard readiness.tier.isPlayable else {
            selectedCourse = enriched
            selectedTeeBox = resolvedTee
            courseUnavailable = readiness.report
            errorMessage = readiness.report?.message
            isLoading = false
            location.stopUpdating()
            return
        }

        courseUnavailable = nil
        // Rangefinder tier: synthesize green polygons/front/back from green centers so the round
        // map renders distance-to-green everywhere it has a center.
        let playCourse = readiness.tier == .rangefinder
            ? CourseAvailability.makePlayReady(enriched)
            : enriched
        // Show a non-blocking note for degraded tiers; nil for full GPS.
        degradedTierNote = readiness.tier == .fullGPS ? nil : readiness.report?.message
        isLoading = false
        await startRound(course: playCourse, teeBox: resolvedTee)
    }

    /// Resumes a previously-saved round (`endedAt == nil`). Rehydrates the course from the OSM
    /// cache so geometry overlays come back; advances to the first unscored hole.
    func resumeRound(_ round: CourseRound) async {
        guard activeRound == nil else { return }
        let cached = OSMGolfService.shared.loadCached(courseId: round.courseId)
        let course = cached ?? GolfCourse(
            id: round.courseId,
            name: round.courseName,
            city: "",
            state: "",
            country: "US",
            holes: round.holes.map {
                GolfHole(id: "\(round.courseId)-hole-\($0.holeNumber)",
                         courseId: round.courseId,
                         number: $0.holeNumber,
                         par: $0.par)
            },
            teeBoxes: [TeeBox(id: "\(round.courseId)-tee",
                              name: round.teeBoxName,
                              color: "White",
                              totalYards: 0)]
        )
        let tee = course.teeBoxes.first(where: { $0.name == round.teeBoxName })
               ?? course.teeBoxes.first
               ?? TeeBox(id: "\(round.courseId)-tee",
                         name: round.teeBoxName,
                         color: "White",
                         totalYards: 0)

        activeRound      = round
        selectedCourse   = course
        selectedTeeBox   = tee
        currentHoleIndex = round.holes.firstIndex(where: { $0.score == nil })
                          ?? max(round.holes.count - 1, 0)
        location.requestPermission()
        location.startUpdating()
    }

    func startRound(course: GolfCourse, teeBox: TeeBox) async {
        guard activeRound == nil else { return }
        var courseHoles = course.holes.sorted { $0.number < $1.number }
        if courseHoles.isEmpty {
            courseHoles = (1...18).map { n in
                GolfHole(id: "\(course.id)-hole-\(n)", courseId: course.id,
                         number: n, par: Self.defaultPar(for: n))
            }
        }
        let holes = courseHoles.map { RoundHole(holeNumber: $0.number, par: $0.par) }
        let round = CourseRound(
            userId: userId,
            courseId: course.id,
            courseName: course.name,
            teeBoxName: teeBox.name,
            holes: holes
        )
        activeRound = round
        selectedCourse = course.holes.isEmpty
            ? GolfCourse(id: course.id, name: course.name, city: course.city,
                         state: course.state, country: course.country,
                         latitude: course.latitude, longitude: course.longitude,
                         holes: courseHoles, teeBoxes: course.teeBoxes,
                         source: course.source, cachedAt: course.cachedAt)
            : course
        selectedTeeBox = teeBox
        currentHoleIndex = 0
        location.requestPermission()
        location.startUpdating()
        await saveRoundOfflineSafe(round)
    }

    private static func defaultPar(for hole: Int) -> Int {
        // Typical par-72: four par-3s, four par-5s, ten par-4s
        switch hole {
        case 3, 7, 12, 16: return 3
        case 2, 6, 11, 15: return 5
        default: return 4
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
        await saveRoundOfflineSafe(round)
    }

    // MARK: - Tracked shots (GPS)

    /// All tracked shots for the current hole, in order.
    var currentHoleTrackedShots: [TrackedShot] {
        guard let round = activeRound,
              currentHoleIndex < round.holes.count else { return [] }
        return round.holes[currentHoleIndex].trackedShots
    }

    /// Append a tracked shot to the current hole and persist.
    @discardableResult
    func appendTrackedShot(start: Coordinate,
                            end: Coordinate,
                            club: ShotClub?,
                            lie: ShotLie,
                            result: ShotResult,
                            linkedSavedShotId: UUID? = nil) async -> TrackedShot? {
        guard var round = activeRound,
              currentHoleIndex < round.holes.count else { return nil }
        let holeNumber = round.holes[currentHoleIndex].holeNumber
        var shot = TrackedShot(
            roundId: round.id,
            holeNumber: holeNumber,
            shotIndex: round.holes[currentHoleIndex].trackedShots.count + 1,
            userId: userId,
            startCoordinate: start,
            endCoordinate: end,
            club: club,
            lie: lie,
            result: result,
            linkedSavedShotId: linkedSavedShotId
        )
        shot.recomputeDistance()
        round.holes[currentHoleIndex].trackedShots.append(shot)
        activeRound = round
        await saveRoundOfflineSafe(round)
        return shot
    }

    func updateTrackedShot(_ shot: TrackedShot) async {
        guard var round = activeRound,
              currentHoleIndex < round.holes.count else { return }
        guard let idx = round.holes[currentHoleIndex].trackedShots.firstIndex(where: { $0.id == shot.id }) else { return }
        var updated = shot
        updated.recomputeDistance()
        round.holes[currentHoleIndex].trackedShots[idx] = updated
        activeRound = round
        await saveRoundOfflineSafe(round)
    }

    func removeTrackedShot(id: UUID) async {
        guard var round = activeRound,
              currentHoleIndex < round.holes.count else { return }
        round.holes[currentHoleIndex].trackedShots.removeAll(where: { $0.id == id })
        // Reindex remaining shots so shotIndex stays contiguous (1-based).
        for i in round.holes[currentHoleIndex].trackedShots.indices {
            round.holes[currentHoleIndex].trackedShots[i].shotIndex = i + 1
        }
        activeRound = round
        await saveRoundOfflineSafe(round)
    }

    func saveManualHoleGeometry(holeNumber: Int, tee: Coordinate, green: Coordinate) {
        guard var course = selectedCourse else { return }
        let index = course.holes.firstIndex(where: { $0.number == holeNumber })
        let existing = index.map { course.holes[$0] }
        var hole = existing ?? GolfHole(
            id: "\(course.id)-hole-\(holeNumber)",
            courseId: course.id,
            number: holeNumber,
            par: currentHole?.par ?? Self.defaultPar(for: holeNumber)
        )

        let synth = GolfGeometry.synthesizeGreen(center: green, tee: tee)

        hole.teeCoordinate = tee
        hole.greenCenterCoordinate = green
        hole.greenFrontCoordinate = synth.front
        hole.greenBackCoordinate = synth.back
        hole.greenPolygon = synth.polygon
        hole.pathCoordinates = [tee, green]

        if let index {
            course.holes[index] = hole
        } else {
            course.holes.append(hole)
            course.holes.sort { $0.number < $1.number }
        }
        course.source = course.source == .golfCourseAPI ? .merged : .manual
        course.geometryMetadata = CourseGeometryMetadata(
            state: .accepted,
            confidence: 0.9,
            source: CourseSource.manual.rawValue,
            schemaVersion: 1,
            generatedBy: "debug_manual_setup",
            validationErrors: [],
            imagerySource: nil,
            updatedAt: Date()
        )
        course.cachedAt = Date()
        selectedCourse = course
        OSMGolfService.shared.cacheMergedCourse(course)
        Task { [backend, course] in
            try? await backend.saveCourseGeometry(course)
        }
    }

    /// Classify the lie of a coordinate from the hole's geometry. Best-effort.
    func classifyLie(at coord: Coordinate, hole: GolfHole?) -> ShotLie {
        guard let h = hole else { return .unknown }
        if polygonContains(h.greenPolygon, coord) { return .green }
        for w in h.waterPolygons where polygonContains(w, coord) { return .water }
        for b in h.bunkerPolygons where polygonContains(b, coord) { return .sand }
        if polygonContains(h.fairwayPolygon, coord) { return .fairway }
        return .rough
    }

    private func polygonContains(_ ring: PolygonRing?, _ p: Coordinate) -> Bool {
        guard let coords = ring?.coordinates, coords.count >= 3 else { return false }
        // Ray casting on lat/lon — accurate enough for the small spans involved here.
        var inside = false
        var j = coords.count - 1
        for i in 0..<coords.count {
            let xi = coords[i].longitude, yi = coords[i].latitude
            let xj = coords[j].longitude, yj = coords[j].latitude
            let intersect = ((yi > p.latitude) != (yj > p.latitude)) &&
                (p.longitude < (xj - xi) * (p.latitude - yi) / (yj - yi + .leastNonzeroMagnitude) + xi)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
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
        await saveRoundOfflineSafe(round)
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

    func discardRound() async {
        guard let round = activeRound else { return }
        try? await backend.deleteCourseRound(roundId: round.id, userId: userId)
        activeRound = nil
    }

    func finishRound() async {
        guard var round = activeRound else { return }
        let hasShots  = !round.shotIds.isEmpty
        let hasScores = round.holes.contains(where: { $0.score != nil })
        guard hasShots || hasScores else {
            // Nothing was recorded — silently discard so empty rounds don't litter history.
            try? await backend.deleteCourseRound(roundId: round.id, userId: userId)
            activeRound = nil
            return
        }
        round.endedAt = Date()
        round.scoreSummary = computeSummary(round)
        do {
            try await backend.saveRound(round)
        } catch {
            errorMessage = error.localizedDescription
        }
        // Auto-share the completed round to the social feed (opt-out in settings).
        await FeedAutoPoster.share(round: round, backend: backend)
        activeRound = nil
    }

    // MARK: - Distance helper

    func distanceToPin(hole: GolfHole) -> Int? {
        guard let mid = hole.greenCenterCoordinate else { return nil }
        return location.distanceInYards(to: CLLocationCoordinate2D(latitude: mid.latitude, longitude: mid.longitude))
            .map { Int($0.rounded()) }
    }

    // MARK: - Offline-safe save

    /// Persists the round via `backend.saveRound` and, on failure, enqueues a deferred sync
    /// so the local copy isn't orphaned. Used by every score-edit path.
    private func saveRoundOfflineSafe(_ round: CourseRound) async {
        do {
            try await backend.saveRound(round)
        } catch {
            SyncQueue.shared.enqueueRound(roundId: round.id, userId: userId)
            #if DEBUG
            print("[Sync] remote saveRound failed (\(error)); enqueued for retry")
            #endif
        }
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
