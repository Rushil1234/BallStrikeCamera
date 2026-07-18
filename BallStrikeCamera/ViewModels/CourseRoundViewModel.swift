import Foundation
import CoreLocation
import Combine

@MainActor
final class CourseRoundViewModel: ObservableObject {

    @Published var activeRound: CourseRound? {
        didSet {
            // Keep the app-wide "round in progress" beacon current so the shell can show a
            // return banner when the player browses the rest of the app mid-round.
            if let r = activeRound, r.endedAt == nil {
                ActiveRoundBeacon.shared.round = r
            } else {
                ActiveRoundBeacon.shared.round = nil
            }
        }
    }
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

    /// The hole a logged shot belongs to is the hole the player is LOOKING AT when they hit
    /// log — course mode's current hole, full stop. GPS coordinates are recorded as data on
    /// the shot; they never decide (or second-guess) the hole. A player can be standing on
    /// hole 8's fairway playing hole 7 after a slice, and the shot is still hole 7's because
    /// that's the hole on screen.
    private var onScreenHole: Int { currentHole?.holeNumber ?? (currentHoleIndex + 1) }

    /// Records an NFC club tap at the user's current GPS position for the on-screen hole.
    /// Captures shot number within the hole and distance to the green center.
    func recordNFCShot(club: UserClub) {
        ClubPreference.remember(club)   // app club is the source of truth
        guard var round = activeRound,
              let coord = location.currentLocation else { return }
        let holeNum = onScreenHole
        let shotNum   = round.nfcShots.filter { $0.holeNumber == holeNum }.count + 1

        var distYards: Double?
        if let course   = selectedCourse,
           let golfHole = course.holes.first(where: { $0.number == holeNum }),
           let pinCoord = golfHole.greenCenterCoordinate?.clCoordinate {
            let shotLoc = CLLocation(latitude: coord.latitude,    longitude: coord.longitude)
            let pinLoc  = CLLocation(latitude: pinCoord.latitude, longitude: pinCoord.longitude)
            distYards = shotLoc.distance(from: pinLoc) * 1.09361  // metres → yards
        }

        let shot = NFCShot(
            clubId:             club.id,
            clubName:           club.name,
            holeNumber:         holeNum,
            shotNumber:         shotNum,
            latitude:           coord.latitude,
            longitude:          coord.longitude,
            distanceToPinYards: distYards
        )
        round.nfcShots.append(shot)
        activeRound = round
        print(String(format: "[CourseGPS] Hole %d · shot %d logged · %@ · (%.6f, %.6f)%@",
                     holeNum, shotNum, club.name, coord.latitude, coord.longitude,
                     distYards.map { String(format: " · %.0fyd to pin", $0) } ?? ""))
    }

    // MARK: - Smart Scoring

    struct SmartScoreResult {
        let score: Int
        let putts: Int?
        /// false when there are no NFC taps and score is just the par default.
        let isInferred: Bool
    }

    /// Infers score and putts for a hole from NFC tap data.
    ///
    /// Rules:
    ///   No taps           → par default, isInferred = false
    ///   Putter + other    → score = total taps, putts = putter count
    ///   Other taps only   → score = other count + 2 (assumed putts), putts = 2
    ///   Putter taps only  → score = par + (putter count − 2), putts = putter count
    func smartScore(forHole holeNumber: Int) -> SmartScoreResult {
        guard let round = activeRound else {
            return SmartScoreResult(score: 4, putts: nil, isInferred: false)
        }
        let par  = round.holes.first(where: { $0.holeNumber == holeNumber })?.par ?? 4
        let taps = round.nfcShots.filter { $0.holeNumber == holeNumber }

        guard !taps.isEmpty else {
            return SmartScoreResult(score: par, putts: nil, isInferred: false)
        }

        let putterTaps = taps.filter { $0.clubName.lowercased().contains("putter") }
        let otherTaps  = taps.filter { !$0.clubName.lowercased().contains("putter") }

        let score: Int
        let putts: Int?

        if !putterTaps.isEmpty && !otherTaps.isEmpty {
            // Full data: trust every tap
            score = taps.count
            putts = putterTaps.count
        } else if !otherTaps.isEmpty {
            // Non-putter taps only — assume 2 putts to finish
            score = otherTaps.count + 2
            putts = 2
        } else {
            // Putter taps only — infer approach count from par
            // e.g. par 4 + 3 putts → score 5; floor at putter count (can't score fewer than putts)
            let raw = par + (putterTaps.count - 2)
            score = max(putterTaps.count, raw)
            putts = putterTaps.count
        }

        return SmartScoreResult(score: min(score, par + 10), putts: putts, isInferred: true)
    }

    /// Shim kept for call sites that only need the score integer.
    /// Returns nil when there are no taps (so the UI can fall back to par itself).
    func inferredStrokes(forHole holeNumber: Int) -> Int? {
        let result = smartScore(forHole: holeNumber)
        return result.isInferred ? result.score : nil
    }

    private var discardObserver: NSObjectProtocol?
    private var locationForwarder: AnyCancellable?

    init(userId: UUID, backend: AppBackend) {
        self.userId  = userId
        self.backend = backend
        self.courseProvider = CourseProviderFactory.make(userId: userId)
        self.location = LocationService()
        discardObserver = NotificationCenter.default.addObserver(
            forName: .tcShotDiscarded, object: nil, queue: .main) { [weak self] note in
            guard let id = note.userInfo?["id"] as? UUID else { return }
            Task { @MainActor in self?.dropShot(id) }
        }
        // CRITICAL: LocationService is a NESTED ObservableObject — its @Published GPS updates
        // do NOT propagate to views observing this view model. Without this forwarding, the
        // course HUD (lines, yardages, F/C/B pill, camera) only refreshed when some *other*
        // vm property changed — users had to toggle the GPS button to force a redraw.
        locationForwarder = location.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    deinit { if let o = discardObserver { NotificationCenter.default.removeObserver(o) } }

    /// Remove a discarded (bad) shot from the active round so counts stay correct.
    func dropShot(_ id: UUID) {
        guard var r = activeRound, r.shotIds.contains(id) else { return }
        r.shotIds.removeAll { $0 == id }
        for i in r.holes.indices { r.holes[i].shotIds.removeAll { $0 == id } }
        activeRound = r
        Task { await saveRoundOfflineSafe(r) }
    }

    // MARK: - Round control

    /// Enriches the course with real OSM geometry first, then starts the round.
    /// Falls back to the unenriched course on any OSM error so a round can still be played.
    func startRoundEnriching(course: GolfCourse, teeBox: TeeBox, gender: Gender = .male) async {
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
        // Write every playable course we enrich into our own geometry DB so repeat plays
        // (by anyone) stop depending on GolfCourseAPI.
        if playCourse.holes.contains(where: { $0.handicap != nil || !$0.teeYardsByTeeBox.isEmpty }) {
            let snapshot = playCourse
            Task.detached(priority: .utility) { [backend] in
                try? await backend.saveCourseGeometry(snapshot)
            }
        }
        await startRound(course: playCourse, teeBox: resolvedTee, gender: gender)
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
        location.beginRoundBackgroundUpdates()
    }

    func startRound(course: GolfCourse, teeBox: TeeBox, gender: Gender = .male) async {
        guard activeRound == nil else { return }
        var courseHoles = course.holes.sorted { $0.number < $1.number }
        if courseHoles.isEmpty {
            courseHoles = (1...18).map { n in
                GolfHole(id: "\(course.id)-hole-\(n)", courseId: course.id,
                         number: n, par: Self.defaultPar(for: n))
            }
        }
        let holes = courseHoles.map { RoundHole(holeNumber: $0.number, par: $0.par) }
        var round = CourseRound(
            userId: userId,
            courseId: course.id,
            courseName: course.name,
            teeBoxName: teeBox.name,
            holes: holes
        )
        // Gender-aware: a tee's rating/slope can differ for men's/women's play on the SAME physical
        // markers (see TeeBox.resolvedRating/resolvedSlope) — pick the pair matching the golfer's
        // profile so the handicap differential (TrueCarryHistoryView.differential) is correct.
        round.courseRating = teeBox.resolvedRating(for: gender)
        round.slopeRating  = teeBox.resolvedSlope(for: gender)
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
        location.beginRoundBackgroundUpdates()
        await saveRoundOfflineSafe(round)
        await backend.logAnalyticsEvent("round_started", properties: [
            "course": round.courseName,
            "tee": round.teeBoxName,
            "holes": round.holes.count
        ], sessionId: nil)
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
        // Entering the score may verify the hole — normalize its tee shot onto the line.
        if let snapped = Self.autoSnapVerifiedTeeShots(in: round, course: selectedCourse,
                                                       teeBoxName: selectedTeeBox?.name) {
            round = snapped
        }
        activeRound = round
        await saveRoundOfflineSafe(round)
    }

    // MARK: - Tracked shots (GPS)

    /// Remove ONE tracked shot (the accidental duplicate tee tap): renumber the rest,
    /// fix the mirrored NFC log, take the stroke off the hole score, refresh totals.
    /// Static so History can run the same fix on already-submitted rounds.
    static func removeTrackedShot(_ shotId: UUID, from original: CourseRound) -> CourseRound? {
        var round = original
        guard let h = round.holes.firstIndex(where: { $0.trackedShots.contains { $0.id == shotId } }),
              let sIdx = round.holes[h].trackedShots.firstIndex(where: { $0.id == shotId })
        else { return nil }
        let removedNumber = round.holes[h].trackedShots[sIdx].shotIndex
        let holeNumber = round.holes[h].holeNumber

        round.holes[h].trackedShots.remove(at: sIdx)
        for i in round.holes[h].trackedShots.indices
        where round.holes[h].trackedShots[i].shotIndex > removedNumber {
            round.holes[h].trackedShots[i].shotIndex -= 1
        }
        // The NFC tap log carries the same hole/shot numbering — keep it in lockstep.
        if let n = round.nfcShots.firstIndex(where: {
            $0.holeNumber == holeNumber && $0.shotNumber == removedNumber }) {
            round.nfcShots.remove(at: n)
        }
        for i in round.nfcShots.indices
        where round.nfcShots[i].holeNumber == holeNumber
            && round.nfcShots[i].shotNumber > removedNumber {
            round.nfcShots[i].shotNumber -= 1
        }
        // One less stroke on the card.
        if let score = round.holes[h].score {
            round.holes[h].score = max(1, score - 1)
        }
        // Totals follow (same rules as computeSummary).
        let scored = round.holes.filter { $0.score != nil }
        round.scoreSummary = RoundScoreSummary(
            totalScore:  scored.compactMap { $0.score }.reduce(0, +),
            totalPar:    scored.map { $0.par }.reduce(0, +),
            fairwaysHit: scored.filter { $0.fairwayHit == true }.count,
            greensInReg: scored.filter { $0.greenInRegulation == true }.count,
            totalPutts:  scored.compactMap { $0.putts }.reduce(0, +)
        )
        return round
    }

    /// In-round delete + persist.
    func deleteTrackedShot(_ shotId: UUID) async {
        guard let round = activeRound,
              let updated = Self.removeTrackedShot(shotId, from: round) else { return }
        activeRound = updated
        await saveRoundOfflineSafe(updated)
    }

    /// Change the club on a logged shot ("logged driver, hit 3-wood"). Pure so the
    /// post-round fix sheet can run it on its own copy of the round.
    static func updateTrackedShotClub(_ shotId: UUID, club: ShotClub?,
                                      in round: CourseRound) -> CourseRound? {
        var round = round
        for h in round.holes.indices {
            if let s = round.holes[h].trackedShots.firstIndex(where: { $0.id == shotId }) {
                round.holes[h].trackedShots[s].club = club
                return round
            }
        }
        return nil
    }

    /// In-round club change + persist.
    func updateTrackedShotClub(_ shotId: UUID, club: ShotClub?) async {
        guard let round = activeRound,
              let updated = Self.updateTrackedShotClub(shotId, club: club, in: round) else { return }
        activeRound = updated
        await saveRoundOfflineSafe(updated)
    }

    /// Insert a forgotten shot after position `afterIndex` on a hole (0 = before the first
    /// logged shot). The neighbors re-chain — the shot before it must have landed where this
    /// one was hit from — numbering shifts up, the stroke is added, and totals refresh.
    /// Pure so the post-round fix sheet can run it on its own copy of the round.
    static func insertTrackedShot(club: ShotClub?, start: Coordinate, end: Coordinate?,
                                  afterIndex: Int, holeNumber: Int,
                                  in round: CourseRound) -> CourseRound? {
        var round = round
        guard let h = round.holes.firstIndex(where: { $0.holeNumber == holeNumber }) else { return nil }
        var shots = round.holes[h].trackedShots.sorted { $0.shotIndex < $1.shotIndex }
        let at = min(max(afterIndex, 0), shots.count)
        let nextStart = at < shots.count ? shots[at].startCoordinate : nil
        var shot = TrackedShot(
            roundId: round.id,
            holeNumber: holeNumber,
            shotIndex: at + 1,
            userId: round.userId,
            startCoordinate: start,
            endCoordinate: end ?? nextStart ?? start,
            club: club
        )
        shot.recomputeDistance()
        if at > 0 {
            shots[at - 1].endCoordinate = start
            shots[at - 1].recomputeDistance()
        }
        shots.insert(shot, at: at)
        for i in shots.indices { shots[i].shotIndex = i + 1 }
        round.holes[h].trackedShots = shots
        // The NFC tap log carries the same hole/shot numbering — keep it in lockstep.
        for i in round.nfcShots.indices
        where round.nfcShots[i].holeNumber == holeNumber && round.nfcShots[i].shotNumber > at {
            round.nfcShots[i].shotNumber += 1
        }
        // One more stroke on the card (only once the hole has a score at all).
        if let score = round.holes[h].score {
            round.holes[h].score = score + 1
        }
        let scored = round.holes.filter { $0.score != nil }
        round.scoreSummary = RoundScoreSummary(
            totalScore:  scored.compactMap { $0.score }.reduce(0, +),
            totalPar:    scored.map { $0.par }.reduce(0, +),
            fairwaysHit: scored.filter { $0.fairwayHit == true }.count,
            greensInReg: scored.filter { $0.greenInRegulation == true }.count,
            totalPutts:  scored.compactMap { $0.putts }.reduce(0, +)
        )
        return round
    }

    /// In-round insert + persist.
    func insertTrackedShot(club: ShotClub?, start: Coordinate, end: Coordinate?,
                           afterIndex: Int, holeNumber: Int) async {
        guard let round = activeRound,
              let updated = Self.insertTrackedShot(club: club, start: start, end: end,
                                                   afterIndex: afterIndex, holeNumber: holeNumber,
                                                   in: round) else { return }
        activeRound = updated
        await saveRoundOfflineSafe(updated)
    }

    // MARK: - Hole centerline (cart-logging position fix)

    private static func lineMeters(_ a: Coordinate, _ b: Coordinate) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private static func lineLerp(_ a: Coordinate, _ b: Coordinate, _ t: Double) -> Coordinate {
        Coordinate(latitude:  a.latitude  + (b.latitude  - a.latitude)  * t,
                   longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    /// Tee→green centerline for a hole: the OSM hole path when present, else straight
    /// tee→green. Always ordered tee first, green center last.
    func holeCenterline(holeNumber: Int) -> [Coordinate]? {
        guard let hole = selectedCourse?.holes.first(where: { $0.number == holeNumber }) else { return nil }
        return Self.holeCenterline(hole: hole, teeBoxName: selectedTeeBox?.name)
    }

    static func holeCenterline(hole: GolfHole, teeBoxName: String?) -> [Coordinate]? {
        guard let green = hole.greenCenterCoordinate else { return nil }
        var pts: [Coordinate]
        if let path = hole.pathCoordinates, path.count >= 2 {
            pts = path
            // OSM ways are undirected — make sure the line runs tee → green.
            if lineMeters(pts.first!, green) < lineMeters(pts.last!, green) { pts.reverse() }
        } else {
            let tee = teeBoxName.flatMap { hole.teeCoordinateByTeeBox?[$0] } ?? hole.teeCoordinate
            guard let tee else { return nil }
            pts = [tee]
        }
        if let last = pts.last, lineMeters(last, green) > 5 { pts.append(green) }
        return pts.count >= 2 ? pts : nil
    }

    /// The point on the centerline at the same distance to the green as `coord` — the shot
    /// only moves LATERALLY onto the line, its yardage to the pin stays what the GPS said.
    static func pointOnLine(_ line: [Coordinate], atGreenDistanceOf coord: Coordinate) -> Coordinate? {
        guard line.count >= 2, let green = line.last else { return nil }
        let d = lineMeters(coord, green)
        // Walk backward from the green until a vertex is at least `d` out — that segment
        // brackets the answer.
        var nearer: Coordinate = green
        var farther: Coordinate?
        for v in line.dropLast().reversed() {
            if lineMeters(v, green) >= d { farther = v; break }
            nearer = v
        }
        guard let far = farther else { return line.first }   // beyond the tee — clamp to tee
        var lo = 0.0, hi = 1.0                                // t=0 at far (≥ d), t=1 at nearer (< d)
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if lineMeters(lineLerp(far, nearer, mid), green) >= d { lo = mid } else { hi = mid }
        }
        return lineLerp(far, nearer, (lo + hi) / 2)
    }

    /// Tee-shot line normalization — Noah's rule: ONLY the first shot of a VERIFIED hole
    /// moves onto the hole's line (you log the tee shot standing by the cart or tee box, so
    /// its position is noisy; later shots start wherever the ball actually finished). Keeps
    /// distance-to-green. Runs automatically when a hole verifies — in-round at score entry,
    /// and in History after edits. Returns nil when nothing needed to move.
    static func autoSnapVerifiedTeeShots(in original: CourseRound,
                                         course: GolfCourse?,
                                         teeBoxName: String?) -> CourseRound? {
        guard let course else { return nil }
        var round = original
        var changed = false
        for h in round.holes.indices {
            let hole = round.holes[h]
            guard RoundShotVerifier.isVerified(hole),
                  let first = hole.trackedShots.min(by: { $0.shotIndex < $1.shotIndex }),
                  first.club?.category != .putter,
                  let gh = course.holes.first(where: { $0.number == hole.holeNumber }),
                  let line = holeCenterline(hole: gh, teeBoxName: teeBoxName),
                  let snapped = pointOnLine(line, atGreenDistanceOf: first.startCoordinate)
            else { continue }
            // Only correct a real offset; a tee shot already on the line stays put.
            guard lineMeters(first.startCoordinate, snapped) > 5,
                  let sIdx = round.holes[h].trackedShots.firstIndex(where: { $0.id == first.id })
            else { continue }
            round.holes[h].trackedShots[sIdx].startCoordinate = snapped
            round.holes[h].trackedShots[sIdx].recomputeDistance()
            changed = true
        }
        return changed ? round : nil
    }


    /// All tracked shots for the current hole, in order.
    var currentHoleTrackedShots: [TrackedShot] {
        guard let round = activeRound,
              currentHoleIndex < round.holes.count else { return [] }
        return round.holes[currentHoleIndex].trackedShots
    }

    /// Append a tracked shot to a hole and persist. `holeNumber` defaults to the current
    /// hole, but callers closing an EARLIER hole's shot (score entered after walking to the
    /// next tee) must pass the hole the shot belongs to — appending to whatever hole the
    /// player is standing on put approach shots (and their club pins) on the wrong hole.
    @discardableResult
    func appendTrackedShot(start: Coordinate,
                            end: Coordinate,
                            club: ShotClub?,
                            lie: ShotLie,
                            result: ShotResult,
                            linkedSavedShotId: UUID? = nil,
                            holeNumber: Int? = nil) async -> TrackedShot? {
        guard var round = activeRound,
              currentHoleIndex < round.holes.count else { return nil }
        let targetIndex: Int
        if let holeNumber, let idx = round.holes.firstIndex(where: { $0.holeNumber == holeNumber }) {
            targetIndex = idx
        } else {
            targetIndex = currentHoleIndex
        }
        var shot = TrackedShot(
            roundId: round.id,
            holeNumber: round.holes[targetIndex].holeNumber,
            shotIndex: round.holes[targetIndex].trackedShots.count + 1,
            userId: userId,
            startCoordinate: start,
            endCoordinate: end,
            club: club,
            lie: lie,
            result: result,
            linkedSavedShotId: linkedSavedShotId
        )
        shot.recomputeDistance()
        round.holes[targetIndex].trackedShots.append(shot)
        activeRound = round
        await saveRoundOfflineSafe(round)
        return shot
    }

    // MARK: - Manual shot tracker ("I'm hitting from HERE with CLUB")
    //
    // Works like NFC tags but with manual input: each log records the player's current GPS as
    // a shot origin. When the NEXT log (or the hole's score entry) arrives, the previous
    // origin → new position becomes a TrackedShot segment for that club. A "moved/drop" flag
    // on a log marks the segment ending there as .penalty so club-distance analytics
    // (which filter on isMeaningfulForCarry) never trust that distance.
    private var pendingManualOrigin: [Int: (coord: Coordinate, club: ShotClub?)] = [:]

    /// Logs a shot origin at the current GPS position. Returns false when no fix exists.
    @discardableResult
    func logManualShot(club: UserClub?, movedOrDropped: Bool) async -> Bool {
        guard let loc = location.currentLocation else { return false }
        let here = Coordinate(latitude: loc.latitude, longitude: loc.longitude)
        // The log goes to the hole on screen when the button was pressed — see onScreenHole.
        let holeNum = onScreenHole

        // Close the previous open origin into a completed segment.
        if let pending = pendingManualOrigin[holeNum] {
            await appendTrackedShot(
                start: pending.coord,
                end: here,
                club: pending.club,
                lie: .unknown,
                result: movedOrDropped ? .penalty : .inPlay,
                holeNumber: holeNum
            )
        }

        let shotClub = club.map { ShotClub(userClub: $0) }
        pendingManualOrigin[holeNum] = (here, shotClub)
        // Feed smart scoring exactly like an NFC tap would.
        if let club { recordNFCShot(club: club) }
        return true
    }

    /// Score entered for the hole → close any open manual origin at the green center so the
    /// final segment (approach/putt) still gets a distance.
    func closeManualShotForHole(_ holeNumber: Int) async {
        guard let pending = pendingManualOrigin[holeNumber] else { return }
        pendingManualOrigin[holeNumber] = nil
        let greenCoord = selectedCourse?.holes
            .first(where: { $0.number == holeNumber })?.greenCenterCoordinate
        guard let green = greenCoord else { return }
        await appendTrackedShot(
            start: pending.coord,
            end: green,
            club: pending.club,
            lie: .unknown,
            result: .inPlay,
            holeNumber: holeNumber
        )
    }

    /// True when a manual origin has already been logged near this position for the hole
    /// (used to suppress the stationary auto-prompt at spots already logged).
    func hasManualOrigin(nearCurrentPositionForHole holeNumber: Int, withinMeters: Double = 25) -> Bool {
        guard let pending = pendingManualOrigin[holeNumber],
              let loc = location.currentLocation else { return false }
        let a = CLLocation(latitude: pending.coord.latitude, longitude: pending.coord.longitude)
        let b = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
        return a.distance(from: b) < withinMeters
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

        let holeNum = currentHole?.holeNumber ?? (currentHoleIndex + 1)
        let unlinked = round.nfcShots.indices.filter {
            round.nfcShots[$0].holeNumber == holeNum &&
            round.nfcShots[$0].linkedShotId == nil
        }

        var bestIdx: Int? = nil

        // GPS proximity primary: if shot has coordinates, find the closest unlinked NFC
        // tap within 5 yards (~4.57 m) on the same hole.
        if let lat = shot.shotLatitude, let lon = shot.shotLongitude {
            bestIdx = unlinked
                .filter { i in
                    let nfc = round.nfcShots[i]
                    return haversineMeters(lat, lon, nfc.latitude, nfc.longitude) <= 4.572
                }
                .min(by: { i, j in
                    let di = haversineMeters(lat, lon, round.nfcShots[i].latitude, round.nfcShots[i].longitude)
                    let dj = haversineMeters(lat, lon, round.nfcShots[j].latitude, round.nfcShots[j].longitude)
                    return di < dj
                })
        }

        // Fallback: closest NFC tap within a 3-minute window.
        if bestIdx == nil {
            bestIdx = unlinked
                .filter { abs(round.nfcShots[$0].tappedAt.timeIntervalSince(shot.timestamp)) <= 180 }
                .min(by: { i, j in
                    abs(round.nfcShots[i].tappedAt.timeIntervalSince(shot.timestamp)) <
                    abs(round.nfcShots[j].tappedAt.timeIntervalSince(shot.timestamp))
                })
        }

        if let idx = bestIdx {
            round.nfcShots[idx].linkedShotId = shot.id
        }

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
        location.endRoundBackgroundUpdates()
    }

    /// `shareToFeed`: nil follows the user's auto-share setting; true/false is an explicit
    /// choice from the end-of-round Post Publicly / Save Privately buttons.
    func finishRound(shareToFeed: Bool? = nil) async {
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
        await backend.logAnalyticsEvent("round_completed", properties: [
            "course": round.courseName,
            "holes_scored": round.holes.filter { $0.score != nil }.count,
            "shots": round.shotIds.count
        ], sessionId: nil)
        // Share to the social feed (explicit choice, else the auto-share setting).
        await FeedAutoPoster.share(round: round, backend: backend,
                                   enabled: shareToFeed ?? FeedSharing.autoShareEnabled)
        activeRound = nil
        location.endRoundBackgroundUpdates()
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

    private func haversineMeters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let R = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        return R * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

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

// MARK: - ActiveRoundBeacon

/// App-wide "a round is in progress" signal. Course mode keeps it current while a round is
/// live; the app shell shows a tap-to-return banner whenever a round exists and course mode
/// itself is off screen. Survives the course view being dismissed (the round is persisted —
/// leaving the screen doesn't end it).
@MainActor
final class ActiveRoundBeacon: ObservableObject {
    static let shared = ActiveRoundBeacon()

    /// The live (unfinished) round, when one exists.
    @Published var round: CourseRound?
    /// True while CourseModeGPSHoleView is on screen — the shell hides the banner then.
    @Published var courseViewVisible = false

    private init() {}
}
