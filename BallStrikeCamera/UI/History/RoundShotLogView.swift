import SwiftUI
import MapKit

// MARK: - RoundShotLogView

/// Paged satellite-map view of every recorded shot in a round — GPS-tracked shots, NFC taps,
/// and camera captures. One page per hole that has shots; swipe left/right to move between
/// holes. Each page frames the FULL hole (tee at the bottom, green at the top) exactly like
/// course mode did while playing it.
///
/// Shot-to-shot lines are drawn only for VERIFIED holes: the player entered score + putts and
/// logged exactly (score − putts) full swings, so shot k provably ended where shot k+1 was hit
/// and the last swing finished at the green.
struct RoundShotLogView: View {
    let round: CourseRound
    /// All SavedShots for this round — used for linked-shot playback and GPS pins.
    let linkedShots: [SavedShot]

    @State private var selectedLinkedShot: SavedShot?
    /// Which hole page is showing — opens on the shot's hole when launched from Insights.
    @State private var selectedHole: Int

    /// Cached OSM geometry for the course (tee/green/path per hole) — the same source course
    /// mode renders from, so history pages match what the player saw during the round.
    private let course: GolfCourse?

    init(round: CourseRound, linkedShots: [SavedShot], initialHole: Int? = nil) {
        self.round = round
        self.linkedShots = linkedShots
        self.course = OSMGolfService.shared.loadCached(courseId: round.courseId)
        let firstHole = round.holes.map { $0.holeNumber }.min() ?? 1
        _selectedHole = State(initialValue: initialHole ?? firstHole)
    }

    /// Every hole of the round gets a page — holes without shots still show the hole
    /// (tee, flag, score) so swiping through reads like replaying the whole round.
    private var holesToShow: [Int] {
        if !round.holes.isEmpty {
            return round.holes.map { $0.holeNumber }.sorted()
        }
        // No hole records at all (legacy rounds) — fall back to holes that have shots.
        let nfcHoles = round.nfcShots.map { $0.holeNumber }
        let cameraHoles = linkedShots.compactMap { shot -> Int? in
            guard shot.shotLatitude != nil, let h = shot.holeNumber else { return nil }
            return h
        }
        return Array(Set(nfcHoles + cameraHoles)).sorted()
    }

    var body: some View {
        if holesToShow.isEmpty {
            Text("No shots recorded — log shots from the course screen (or tap your club to the RFID hub) to see them mapped here.")
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textMuted)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            GeometryReader { geo in
                TabView(selection: $selectedHole) {
                    ForEach(holesToShow, id: \.self) { holeNum in
                        let roundHole = round.holes.first { $0.holeNumber == holeNum }
                        HoleShotPage(
                            holeNumber: holeNum,
                            roundHole: roundHole,
                            golfHole: course?.holes.first { $0.number == holeNum },
                            verifiedShots: roundHole.map {
                                RoundShotVerifier.verifiedShots(round: round, hole: $0, course: course)
                            } ?? [],
                            shots: round.nfcShots
                                .filter { $0.holeNumber == holeNum }
                                .sorted { $0.shotNumber < $1.shotNumber },
                            linkedShots: linkedShots,
                            cameraShots: linkedShots.filter {
                                $0.holeNumber == holeNum && $0.shotLatitude != nil
                            },
                            mapWidth: geo.size.width,
                            onPlayShot: { selectedLinkedShot = $0 }
                        )
                        .padding(.horizontal, 2)
                        .padding(.bottom, 28)
                        .tag(holeNum)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
            .frame(height: pageHeight)
            .sheet(item: $selectedLinkedShot) { shot in
                NavigationStack {
                    ShotDetailView(shot: shot)
                }
                .tcAppearance()
            }
        }
    }

    private var pageHeight: CGFloat {
        let maxRows = holesToShow.map { h in
            round.nfcShots.filter { $0.holeNumber == h }.count
                + (round.holes.first { $0.holeNumber == h }?.trackedShots.count ?? 0)
        }.max() ?? 1
        return 46 + 460 + CGFloat(min(maxRows, 6)) * 44 + 36
    }
}

// MARK: - HoleShotPage

private struct HoleShotPage: View {
    let holeNumber: Int
    let roundHole: RoundHole?
    let golfHole: GolfHole?
    let verifiedShots: [VerifiedRoundShot]
    let shots: [NFCShot]
    let linkedShots: [SavedShot]
    let cameraShots: [SavedShot]
    let mapWidth: CGFloat
    let onPlayShot: (SavedShot) -> Void

    /// Tall map so the whole hole reads like the course-mode screen, not a letterboxed
    /// strip — a full par-5 with its pins and club labels needs the vertical room.
    private let mapHeight: CGFloat = 460

    @State private var snapshot: UIImage?
    @State private var nfcPinPoints: [(id: UUID, point: CGPoint)] = []
    @State private var cameraPinPoints: [(id: UUID, point: CGPoint)] = []
    @State private var trackedPinPoints: [(id: UUID, point: CGPoint)] = []

    private var linkedShotIds: Set<UUID> {
        Set(shots.compactMap { $0.linkedShotId })
    }

    private var trackedSwings: [TrackedShot] {
        roundHole.map { RoundShotVerifier.fullSwings($0) } ?? []
    }

    /// Longest believable "yards to pin" on this hole. Anything beyond it is a misfiled or
    /// GPS-junk record (observed: "724 yd to pin" on a ~500-yd hole — score entry used to
    /// append the previous hole's closing segment to whatever hole the player had walked
    /// to). Misfiled shots are excluded outright: an impossible number is worse than a
    /// missing one. No hole geometry → no gate.
    private var maxPlausibleYards: Double? {
        guard let tee = golfHole?.teeCoordinate?.clCoordinate,
              let green = golfHole?.greenCenterCoordinate?.clCoordinate else { return nil }
        return RoundShotVerifier.yards(tee, green) * 1.3 + 40
    }

    private func isPlausible(_ swing: TrackedShot) -> Bool {
        let start = swing.startCoordinate.clCoordinate
        if let cap = maxPlausibleYards, let toPin = yardsToPin(from: swing), toPin > cap { return false }
        if let corridor = yardsToCorridor(start), corridor > 70 { return false }
        if let along = alongTeeYards(start), along < -40 { return false }
        return true
    }

    private func isPlausible(_ nfc: NFCShot) -> Bool {
        let tap = CLLocationCoordinate2D(latitude: nfc.latitude, longitude: nfc.longitude)
        if let cap = maxPlausibleYards,
           let green = golfHole?.greenCenterCoordinate?.clCoordinate,
           RoundShotVerifier.yards(tap, green) > cap { return false }
        if let corridor = yardsToCorridor(tap), corridor > 70 { return false }
        if let along = alongTeeYards(tap), along < -40 { return false }
        return true
    }

    /// Along-hole yards of a coordinate measured from the tee toward the green (negative =
    /// behind the tee box). A shot filed to this hole but hit from well behind its own tee
    /// is the previous hole's closing shot that score entry appended late — it can sit close
    /// enough to this hole's corridor (tees abut the last green) to pass the corridor test,
    /// but no real shot on this hole starts 40+ yards behind the tee.
    private func alongTeeYards(_ coord: CLLocationCoordinate2D) -> Double? {
        guard let tee = golfHole?.teeCoordinate?.clCoordinate,
              let green = golfHole?.greenCenterCoordinate?.clCoordinate,
              RoundShotVerifier.yards(tee, green) > 5 else { return nil }
        let kLat = 111_320.0
        let cosLat = cos(tee.latitude * .pi / 180)
        let th = bearing(from: tee, to: green) * .pi / 180
        let e = (coord.longitude - tee.longitude) * kLat * cosLat
        let n = (coord.latitude - tee.latitude) * kLat
        return (e * sin(th) + n * cos(th)) * 1.09361
    }

    /// Yards from a coordinate to this hole's tee→waypoints→green corridor line. A shot hit
    /// while PLAYING this hole starts on or near that corridor (a recovery from the next
    /// fairway over is still within ~70yd); a record filed here from a different hole sits
    /// hundreds of yards off it. This is what keeps another hole's misfiled shots — which can
    /// pass the raw to-pin cap — off this hole's page.
    private func yardsToCorridor(_ coord: CLLocationCoordinate2D) -> Double? {
        guard let tee = golfHole?.teeCoordinate?.clCoordinate,
              let green = golfHole?.greenCenterCoordinate?.clCoordinate else { return nil }
        var line = [tee]
        line += (golfHole?.pathCoordinates ?? []).map { $0.clCoordinate }
        line.append(green)
        let kLat = 111_320.0
        let cosLat = cos(tee.latitude * .pi / 180)
        func en(_ c: CLLocationCoordinate2D) -> (e: Double, n: Double) {
            ((c.longitude - tee.longitude) * kLat * cosLat, (c.latitude - tee.latitude) * kLat)
        }
        let p = en(coord)
        var best = Double.greatestFiniteMagnitude
        for i in 0..<(line.count - 1) {
            let a = en(line[i]), b = en(line[i + 1])
            let abe = b.e - a.e, abn = b.n - a.n
            let len2 = abe * abe + abn * abn
            let t = len2 > 0 ? max(0, min(1, ((p.e - a.e) * abe + (p.n - a.n) * abn) / len2)) : 0
            let de = p.e - (a.e + abe * t), dn = p.n - (a.n + abn * t)
            best = min(best, (de * de + dn * dn).squareRoot())
        }
        return best * 1.09361
    }

    /// One display sequence for the hole: tracked swings and (non-duplicate) NFC taps merged
    /// chronologically and numbered 1…N. The SAME numbers drive the map pins and the shot
    /// list — the two channels used to number themselves independently (`shotIndex` vs
    /// `shotNumber`), so a hole with one swing and one tap showed two different pins both
    /// labeled "1". Entries whose GPS fails the plausibility gates keep their list row
    /// (the shot WAS taken) but render no pin and no impossible yardage.
    private struct HoleShotEntry: Identifiable {
        enum Kind { case swing(TrackedShot), nfc(NFCShot) }
        let number: Int
        let kind: Kind
        /// GPS passed the plausibility gates → the shot renders a pin on the map.
        let onMap: Bool
        var id: UUID {
            switch kind {
            case .swing(let s): return s.id
            case .nfc(let n):   return n.id
            }
        }
    }

    private var entries: [HoleShotEntry] {
        var raw: [(when: Date, order: Int, kind: HoleShotEntry.Kind, onMap: Bool)] = []
        for s in trackedSwings {
            raw.append((s.timestamp, s.shotIndex, .swing(s), isPlausible(s)))
        }
        for n in shots where !trackedSwings.contains(where: { isDuplicate(n, of: $0) }) {
            raw.append((n.tappedAt, n.shotNumber, .nfc(n), isPlausible(n)))
        }
        let ordered = raw.sorted {
            $0.when != $1.when ? $0.when < $1.when : $0.order < $1.order
        }
        return ordered.enumerated().map {
            HoleShotEntry(number: $0.offset + 1, kind: $0.element.kind, onMap: $0.element.onMap)
        }
    }

    /// The manual shot logger feeds BOTH channels — every logged swing becomes a TrackedShot
    /// segment AND an NFCShot tap — so rendering both listed the same driver twice (once with
    /// its measured distance, once with its at-address "yards to pin"). An NFC tap that
    /// matches a tracked swing (same club, tapped within ~20m of the swing's origin) is the
    /// same physical shot and renders once, as the tracked swing.
    private func isDuplicate(_ nfc: NFCShot, of swing: TrackedShot) -> Bool {
        guard let clubName = swing.club?.name, clubName == nfc.clubName else { return false }
        let tap = CLLocationCoordinate2D(latitude: nfc.latitude, longitude: nfc.longitude)
        return RoundShotVerifier.yards(swing.startCoordinate.clCoordinate, tap) < 22
    }

    /// Playable camera capture for a tracked swing: its own link, or the link carried by the
    /// duplicate NFC tap this page suppressed.
    private func linkedSavedShot(for swing: TrackedShot) -> SavedShot? {
        if let id = swing.linkedSavedShotId,
           let s = linkedShots.first(where: { $0.id == id }) { return s }
        if let nfc = shots.first(where: { isDuplicate($0, of: swing) }),
           let lid = nfc.linkedShotId {
            return linkedShots.first { $0.id == lid }
        }
        return nil
    }

    /// Whether there is anything to render a map from (hole geometry or any shot GPS).
    private var hasMapContent: Bool {
        golfHole?.teeCoordinate != nil || golfHole?.greenCenterCoordinate != nil
            || !trackedSwings.isEmpty || !shots.isEmpty || !cameraShots.isEmpty
    }

    private var isVerified: Bool {
        roundHole.map { RoundShotVerifier.isVerified($0) } ?? false
    }

    /// Distance from where a shot was hit to the hole (green center) — the honest number we
    /// can always show, even when the hole's shot list doesn't reconcile with its score.
    private func yardsToPin(from shot: TrackedShot) -> Double? {
        guard let green = golfHole?.greenCenterCoordinate?.clCoordinate else { return nil }
        return RoundShotVerifier.yards(shot.startCoordinate.clCoordinate, green)
    }

    var body: some View {
        VStack(spacing: 0) {
            holeHeader

            // Satellite map with overlaid shot pins
            ZStack(alignment: .topLeading) {
                if let img = snapshot {
                    Image(uiImage: img)
                        .resizable()
                        .frame(width: mapWidth, height: mapHeight)

                    // Numbered shot pins at where each shot was hit from — tracked swings and
                    // NFC taps share one chronological sequence. Verified holes label the
                    // shot's actual distance; unverified holes label how far from the hole
                    // the player was standing when they hit it. Entries whose GPS failed the
                    // plausibility gates have a list row but no pin.
                    ForEach(entries.filter { $0.onMap }) { entry in
                        switch entry.kind {
                        case .swing(let shot):
                            if let pt = trackedPinPoints.first(where: { $0.id == shot.id })?.point {
                                TrackedShotPin(shot: shot,
                                               number: entry.number,
                                               verifiedDistance: verifiedShots.first { $0.id == shot.id }?.distanceYards,
                                               yardsToPin: yardsToPin(from: shot))
                                    .position(x: pt.x, y: pt.y)
                            }
                        case .nfc(let shot):
                            if let pt = nfcPinPoints.first(where: { $0.id == shot.id })?.point {
                                let linked = linkedShots.first(where: { $0.id == shot.linkedShotId })
                                ShotPin(shot: shot, number: entry.number, hasVideo: linked != nil) {
                                    if let s = linked { onPlayShot(s) }
                                }
                                .position(x: pt.x, y: pt.y - 22)
                            }
                        }
                    }

                    // Camera shot GPS pins (unlinked only — linked ones show via NFC pin)
                    ForEach(cameraShots.filter { !linkedShotIds.contains($0.id) }) { shot in
                        if let pt = cameraPinPoints.first(where: { $0.id == shot.id })?.point {
                            CameraShotPin(shot: shot) {
                                onPlayShot(shot)
                            }
                            .position(x: pt.x, y: pt.y - 18)
                        }
                    }
                } else if !hasMapContent {
                    ZStack {
                        Rectangle().fill(Color(white: 0.12))
                        Text("No map data for this hole")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .frame(width: mapWidth, height: mapHeight)
                } else {
                    ZStack {
                        Rectangle().fill(Color(white: 0.12))
                        ProgressView().tint(.white)
                    }
                    .frame(width: mapWidth, height: mapHeight)
                }
            }
            .frame(width: mapWidth, height: mapHeight)
            .clipped()
            .onAppear { if snapshot == nil, hasMapContent { renderSnapshot() } }

            shotList
        }
        .background(TCTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Sub-views

    /// Every shot filed to this hole counts — including ones the map can't place. The round
    /// header advertises "14 shots · 14 holes"; a hole page saying "0 shots" because its GPS
    /// fixes were junk read as lost data.
    private var totalShotCount: Int {
        entries.count + cameraShots.filter { !linkedShotIds.contains($0.id) }.count
    }

    private var holeHeader: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("HOLE \(holeNumber)")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(TCTheme.textMuted)
                    if let par = roundHole?.par {
                        Text("PAR \(par)")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.5)
                            .foregroundColor(TCTheme.textUltraMuted)
                    }
                }
                Text("\(totalShotCount) shot\(totalShotCount == 1 ? "" : "s")")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
            }
            Spacer()
            if isVerified {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("VERIFIED")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                }
                .foregroundColor(TCTheme.sage)
                .padding(.trailing, 10)
            }
            if let score = roundHole?.score {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SCORE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(TCTheme.textMuted)
                    Text("\(score)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                }
            } else if let closest = shots.compactMap({ $0.distanceToPinYards }).min() {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("CLOSEST")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(TCTheme.textMuted)
                    Text("\(Int(closest.rounded())) yd")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                }
            } else {
                // Every hole shows its score slot, even unscored ones — the pager reads as
                // the whole round, not just the holes that happen to have shots.
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SCORE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(TCTheme.textMuted)
                    Text("—")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var shotList: some View {
        let items = entries
        return VStack(spacing: 0) {
            ForEach(items) { entry in
                entryRow(entry)
                if entry.number < items.count {
                    Rectangle()
                        .fill(TCTheme.border)
                        .frame(height: 1)
                        .padding(.leading, 54)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func entryRow(_ entry: HoleShotEntry) -> some View {
        switch entry.kind {
        case .swing(let shot): swingRow(shot, number: entry.number, onMap: entry.onMap)
        case .nfc(let shot):   nfcRow(shot, number: entry.number, onMap: entry.onMap)
        }
    }

    private func swingRow(_ shot: TrackedShot, number: Int, onMap: Bool) -> some View {
        HStack(spacing: 10) {
            numberBadge(number, clubName: shot.club?.name ?? "")
            VStack(alignment: .leading, spacing: 1) {
                Text(shot.club?.name ?? "Shot \(number)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                // Shot distance + lateral miss only when the hole verifies; otherwise the
                // only trustworthy number is how far from the hole they stood — and when the
                // GPS fix fails the plausibility gates, no number beats an impossible one.
                if let v = verifiedShots.first(where: { $0.id == shot.id }) {
                    Text("\(Int(v.distanceYards.rounded())) yd · \(Self.lateralLabel(v.lateralYards))")
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                } else if !onMap {
                    Text("logged · GPS fix off this hole")
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textUltraMuted)
                } else if let toPin = yardsToPin(from: shot) {
                    Text("\(Int(toPin.rounded())) yd to pin")
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                }
            }
            Spacer()
            if let linkedShot = linkedSavedShot(for: shot) {
                playButton(linkedShot)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func nfcRow(_ shot: NFCShot, number: Int, onMap: Bool) -> some View {
        HStack(spacing: 10) {
            numberBadge(number, clubName: shot.clubName)
            VStack(alignment: .leading, spacing: 1) {
                Text(shot.clubName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                if !onMap {
                    Text("logged · GPS fix off this hole")
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textUltraMuted)
                } else if let dist = shot.distanceToPinYards {
                    Text("\(Int(dist.rounded())) yd to pin")
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                }
            }
            Spacer()
            if let linkedShot = linkedShots.first(where: { $0.id == shot.linkedShotId }) {
                playButton(linkedShot)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func numberBadge(_ number: Int, clubName: String) -> some View {
        ZStack {
            Circle()
                .fill(clubColor(clubName).opacity(0.18))
                .frame(width: 30, height: 30)
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(clubColor(clubName))
        }
    }

    private func playButton(_ shot: SavedShot) -> some View {
        Button {
            onPlayShot(shot)
        } label: {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 26))
                .foregroundColor(TCTheme.gold)
        }
        .buttonStyle(.plain)
    }

    private static func lateralLabel(_ lateral: Double) -> String {
        let y = Int(abs(lateral).rounded())
        if y < 5 { return "on line" }
        return lateral < 0 ? "\(y)y left" : "\(y)y right"
    }

    // MARK: Snapshot

    /// Visible vertical ground meters per meter of camera altitude for MKMapSnapshotter at
    /// pitch 0. The relationship is an undocumented field-of-view constant, so it's MEASURED
    /// from the first snapshot (via `snap.point(for:)` on two coordinates a known distance
    /// apart) instead of assumed. The old code guessed it — `altitude = 1.55 × span` — and
    /// guessed short: every hole rendered ~17% too zoomed-in, clipping the tee, the green,
    /// and any pin near an edge on every page.
    private static var calibratedVisibleFactor: Double?

    private func renderSnapshot(attempt: Int = 0) {
        let opts = MKMapSnapshotter.Options()
        opts.size    = CGSize(width: mapWidth, height: mapHeight)
        opts.scale   = UIScreen.main.scale
        opts.mapType = .hybrid

        // Frame the FULL hole exactly like course mode: tee at the bottom, green at the top,
        // and the whole hole path + every mapped shot inside the frame (a dogleg or an
        // offline shot must not fall off the edge). Fall back to fitting the shot cluster
        // when the course cache has no geometry for this hole.
        let fit = holeFit()
        let usedFactor = Self.calibratedVisibleFactor ?? 0.54   // ≈ MapKit's historical 30° FOV
        var usedAltitude = 0.0
        if let fit {
            usedAltitude = max(fit.visibleMeters / usedFactor, 180)
            opts.camera = MKMapCamera(lookingAtCenter: fit.center, fromDistance: usedAltitude,
                                      pitch: 0, heading: fit.heading)
        } else {
            opts.region = computeRegion()
        }

        MKMapSnapshotter(options: opts).start { snap, _ in
            guard let snap else { return }
            DispatchQueue.main.async {
                // Calibrate the FOV factor off this snapshot; if the guess misframed the
                // hole by more than ~8%, re-render once with the measured value. Later
                // pages hit the cached factor and render right on the first pass.
                if let fit, attempt == 0,
                   let measured = Self.measureVisibleFactor(snap: snap, center: fit.center,
                                                            altitude: usedAltitude,
                                                            heightPoints: Double(mapHeight)) {
                    Self.calibratedVisibleFactor = measured
                    if abs(measured / usedFactor - 1) > 0.08 {
                        renderSnapshot(attempt: 1)
                        return
                    }
                }
                self.snapshot = drawShotLines(on: snap)
                self.trackedPinPoints = trackedSwings.map { s in
                    (id: s.id, point: snap.point(for: s.startCoordinate.clCoordinate))
                }
                self.nfcPinPoints = shots.map { s in
                    let coord = CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude)
                    return (id: s.id, point: snap.point(for: coord))
                }
                self.cameraPinPoints = cameraShots.compactMap { s in
                    guard let lat = s.shotLatitude, let lon = s.shotLongitude else { return nil }
                    let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    return (id: s.id, point: snap.point(for: coord))
                }
            }
        }
    }

    /// Projects the snapshot center and a point 200 m due north of it, and derives visible
    /// vertical meters per altitude meter from the pixel distance between them. Projection
    /// scale at pitch 0 is isotropic, so the probe direction doesn't matter.
    private static func measureVisibleFactor(snap: MKMapSnapshotter.Snapshot,
                                             center: CLLocationCoordinate2D,
                                             altitude: Double,
                                             heightPoints: Double) -> Double? {
        guard altitude > 0 else { return nil }
        let probeMeters = 200.0
        let probe = CLLocationCoordinate2D(latitude: center.latitude + probeMeters / 111_320.0,
                                           longitude: center.longitude)
        let p1 = snap.point(for: center)
        let p2 = snap.point(for: probe)
        let px = Double(hypot(p2.x - p1.x, p2.y - p1.y))
        guard px > 1 else { return nil }
        return (probeMeters / px) * heightPoints / altitude
    }

    /// Draws the hole exactly the way course mode renders it — white hole-path line over a
    /// dark casing, small waypoint dots at each path marker, tee ring, flag on the green —
    /// plus the verified shot-to-shot polyline in course mode's gold. Shot lines only appear
    /// on verified holes — an unverified hole shows pins with no connecting lines, because
    /// we can't know where each shot actually finished.
    private func drawShotLines(on snap: MKMapSnapshotter.Snapshot) -> UIImage {
        let green = golfHole?.greenCenterCoordinate?.clCoordinate
        let tee = golfHole?.teeCoordinate?.clCoordinate
        guard !verifiedShots.isEmpty || green != nil || tee != nil else { return snap.image }

        let renderer = UIGraphicsImageRenderer(size: snap.image.size)
        return renderer.image { ctx in
            snap.image.draw(at: .zero)
            let c = ctx.cgContext

            // Hole path (tee → fairway waypoints → green): the same white-over-casing line
            // course mode draws, with SMALL waypoint dots at the intermediate markers.
            let waypoints = (golfHole?.pathCoordinates ?? []).map { $0.clCoordinate }
            if let tee, let green {
                let route = [tee] + waypoints + [green]
                let pts = route.map { snap.point(for: $0) }
                for (width, color) in [(4.0, UIColor.black.withAlphaComponent(0.32)),
                                       (2.0, UIColor.white.withAlphaComponent(0.92))] {
                    c.setLineWidth(width)
                    c.setStrokeColor(color.cgColor)
                    c.setLineCap(.round)
                    c.setLineJoin(.round)
                    c.beginPath()
                    c.move(to: pts[0])
                    for p in pts.dropFirst() { c.addLine(to: p) }
                    c.strokePath()
                }
                for w in waypoints {
                    let p = snap.point(for: w)
                    let r: CGFloat = 2.5
                    c.setFillColor(UIColor.white.cgColor)
                    c.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    c.setLineWidth(1)
                    c.setStrokeColor(UIColor.black.withAlphaComponent(0.4).cgColor)
                    c.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                }
            }

            if !verifiedShots.isEmpty {
                let ordered = verifiedShots.sorted { $0.shotIndex < $1.shotIndex }
                var pts = ordered.map { snap.point(for: $0.start) }
                if let lastEnd = ordered.last.map({ snap.point(for: $0.end) }) {
                    pts.append(lastEnd)
                }
                if pts.count >= 2 {
                    // Casing then line — gold, the color course mode gives logged shots.
                    for (width, color) in [(5.0, UIColor.black.withAlphaComponent(0.35)),
                                           (3.0, UIColor(red: 1.0, green: 0.82, blue: 0.0, alpha: 0.95))] {
                        c.setLineWidth(width)
                        c.setStrokeColor(color.cgColor)
                        c.setLineCap(.round)
                        c.setLineJoin(.round)
                        c.beginPath()
                        c.move(to: pts[0])
                        for p in pts.dropFirst() { c.addLine(to: p) }
                        c.strokePath()
                    }
                }
            }

            // Tee marker — white ring with a dot, same idiom as the live hole view.
            if let tee {
                let p = snap.point(for: tee)
                let r: CGFloat = 6
                c.setLineWidth(2.5)
                c.setStrokeColor(UIColor.white.cgColor)
                c.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                c.setFillColor(UIColor.white.cgColor)
                c.fillEllipse(in: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
            }

            // Flag on the green center: yellow ring plus a small pole + pennant.
            if let green {
                let p = snap.point(for: green)
                let r: CGFloat = 7
                c.setLineWidth(2.5)
                c.setStrokeColor(UIColor.systemYellow.cgColor)
                c.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                c.setFillColor(UIColor.systemYellow.cgColor)
                c.fillEllipse(in: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
                // Pole
                c.setLineWidth(2)
                c.move(to: CGPoint(x: p.x, y: p.y - 2))
                c.addLine(to: CGPoint(x: p.x, y: p.y - 16))
                c.strokePath()
                // Pennant
                c.beginPath()
                c.move(to: CGPoint(x: p.x, y: p.y - 16))
                c.addLine(to: CGPoint(x: p.x + 8, y: p.y - 13))
                c.addLine(to: CGPoint(x: p.x, y: p.y - 10))
                c.closePath()
                c.fillPath()
            }
        }
    }

    private struct HoleFit {
        let center: CLLocationCoordinate2D
        let heading: Double
        /// Ground meters the snapshot must show vertically for the whole hole and every
        /// mapped pin (plus their label overlays) to fit inside the frame.
        let visibleMeters: Double
    }

    /// Course-mode-style hole framing: heading tee→green (hole plays "up"), and the visible
    /// span solved EXACTLY from what has to fit — tee, path, green, every on-map shot pin —
    /// with screen-point padding reserved for the overlays that hang past their anchor
    /// (label capsules below pins, the flag pole above the green).
    private func holeFit() -> HoleFit? {
        guard let tee = golfHole?.teeCoordinate?.clCoordinate,
              let green = golfHole?.greenCenterCoordinate?.clCoordinate,
              RoundShotVerifier.yards(tee, green) > 5 else { return nil }
        let heading = bearing(from: tee, to: green)

        var pts: [CLLocationCoordinate2D] = [tee, green]
        pts += (golfHole?.pathCoordinates ?? []).map { $0.clCoordinate }
        for entry in entries where entry.onMap {
            switch entry.kind {
            case .swing(let s): pts.append(s.startCoordinate.clCoordinate)
            case .nfc(let n):   pts.append(CLLocationCoordinate2D(latitude: n.latitude, longitude: n.longitude))
            }
        }

        // Local ENU meters around the tee, rotated into the hole's heading frame so the
        // bounds are measured the way the snapshot is oriented (hole playing "up").
        let kLat = 111_320.0
        let cosLat = cos(tee.latitude * .pi / 180)
        let th = heading * .pi / 180
        var alongMin = Double.greatestFiniteMagnitude, alongMax = -Double.greatestFiniteMagnitude
        var crossMin = Double.greatestFiniteMagnitude, crossMax = -Double.greatestFiniteMagnitude
        for p in pts {
            let e = (p.longitude - tee.longitude) * kLat * cosLat
            let n = (p.latitude - tee.latitude) * kLat
            let along = e * sin(th) + n * cos(th)
            let cross = e * cos(th) - n * sin(th)
            alongMin = min(alongMin, along); alongMax = max(alongMax, along)
            crossMin = min(crossMin, cross); crossMax = max(crossMax, cross)
        }

        // Screen points reserved at each edge: NFC pins rise ~46pt above their anchor and
        // the flag pole tops the green (top), tracked-pin labels hang ~22pt below their
        // anchor (bottom), and label capsules extend sideways from pins near the rails.
        let padTop = 50.0, padBottom = 36.0, padSide = 40.0
        let h = Double(mapHeight), w = Double(mapWidth)
        let vAlong = (alongMax - alongMin) / max((h - padTop - padBottom) / h, 0.2)
        let vCross = (crossMax - crossMin) * h / max(w - 2 * padSide, 40)
        let visible = max(vAlong, vCross, 240)
        let metersPerPoint = visible / h

        // Center of the padded content: bounds midpoint, biased along the hole so the
        // asymmetric top/bottom padding is honored, mapped back to a coordinate.
        let alongMid = (alongMin + alongMax) / 2 + (padTop - padBottom) / 2 * metersPerPoint
        let crossMid = (crossMin + crossMax) / 2
        let ce = alongMid * sin(th) + crossMid * cos(th)
        let cn = alongMid * cos(th) - crossMid * sin(th)
        let center = CLLocationCoordinate2D(latitude: tee.latitude + cn / kLat,
                                            longitude: tee.longitude + ce / (kLat * cosLat))
        return HoleFit(center: center, heading: heading, visibleMeters: visible)
    }

    private func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }

    private func computeRegion() -> MKCoordinateRegion {
        var lats = shots.map { $0.latitude }
        var lons = shots.map { $0.longitude }
        for s in trackedSwings {
            lats.append(s.startCoordinate.latitude)
            lons.append(s.startCoordinate.longitude)
        }
        for s in cameraShots {
            if let lat = s.shotLatitude, let lon = s.shotLongitude {
                lats.append(lat); lons.append(lon)
            }
        }
        guard !lats.isEmpty else {
            return MKCoordinateRegion(center: .init(latitude: 0, longitude: 0),
                                     span: .init(latitudeDelta: 0.005, longitudeDelta: 0.005))
        }
        let center = CLLocationCoordinate2D(
            latitude:  (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let spanLat = max((lats.max()! - lats.min()!) * 2.5, 0.002)
        let spanLon = max((lons.max()! - lons.min()!) * 2.5, 0.002)
        return MKCoordinateRegion(center: center,
                                  span: .init(latitudeDelta: spanLat, longitudeDelta: spanLon))
    }
}

// MARK: - TrackedShotPin

private struct TrackedShotPin: View {
    let shot: TrackedShot
    /// Display number from the hole's unified (tracked + NFC) chronological sequence — NOT
    /// `shot.shotIndex`, which numbers only its own channel and collides with NFC numbers.
    let number: Int
    let verifiedDistance: Double?
    let yardsToPin: Double?

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(clubColor(shot.club?.name ?? ""))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 2)
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            if let label = pinLabel {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.62))
                    .clipShape(Capsule())
            }
        }
    }

    private var pinLabel: String? {
        let abbr = shot.club.map { abbreviateClub($0.name) }
        // Verified: the shot's real distance. Unverified: distance to the pin from here.
        if let d = verifiedDistance {
            return "\(abbr.map { "\($0) · " } ?? "")\(Int(d.rounded()))y"
        }
        if let toPin = yardsToPin {
            return "\(abbr.map { "\($0) · " } ?? "")\(Int(toPin.rounded()))y to pin"
        }
        return abbr
    }
}

// MARK: - ShotPin overlay

private struct ShotPin: View {
    let shot: NFCShot
    /// Display number from the hole's unified (tracked + NFC) chronological sequence — NOT
    /// `shot.shotNumber`, which numbers only its own channel and collides with swing numbers.
    let number: Int
    let hasVideo: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(clubColor(shot.clubName))
                        .frame(width: 28, height: 28)
                        .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 2)
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                if hasVideo {
                    Image(systemName: "video.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(3)
                        .background(Circle().fill(Color.black.opacity(0.7)))
                        .offset(x: 6, y: -6)
                }
            }
            Text(shotLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.62))
                .clipShape(Capsule())
        }
        .onTapGesture { if hasVideo { onTap() } }
        .contentShape(Rectangle())
    }

    private var shotLabel: String {
        let abbr = abbreviateClub(shot.clubName)
        if let dist = shot.distanceToPinYards {
            return "\(abbr) · \(Int(dist.rounded()))y"
        }
        return abbr
    }
}

// MARK: - CameraShotPin

private struct CameraShotPin: View {
    let shot: SavedShot
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.88))
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                Image(systemName: "camera.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.black.opacity(0.75))
            }
            Text(shot.clubName.flatMap { abbreviateClub($0) } ?? "—")
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
        }
        .onTapGesture { onTap() }
    }
}

// MARK: - Helpers

private func clubColor(_ name: String) -> Color {
    let l = name.lowercased()
    if l.contains("driver")  { return ClubType.driver.color }
    if l.contains("wood")    { return ClubType.fairwayWood.color }
    if l.contains("hybrid")  { return ClubType.hybrid.color }
    if l.contains("putter")  { return ClubType.putter.color }
    // "58°"-style loft names (the default bag's 50°/54°/58°) are wedges too — without the
    // degree check they fell through to the anonymous gray.
    if l.contains("wedge") || l.contains("°") || l == "pw" || l == "gw" || l == "sw" || l == "lw" {
        return ClubType.wedge.color
    }
    if l.contains("iron")    { return ClubType.iron.color }
    return Color(white: 0.55)
}

private func abbreviateClub(_ name: String) -> String {
    let map: [String: String] = [
        "Driver": "Dr",  "3 Wood": "3W",  "5 Wood": "5W",  "7 Wood": "7W",
        "3 Iron": "3i",  "4 Iron": "4i",  "5 Iron": "5i",  "6 Iron": "6i",
        "7 Iron": "7i",  "8 Iron": "8i",  "9 Iron": "9i",
        "Pitching Wedge": "PW", "Gap Wedge": "GW",
        "Sand Wedge": "SW",     "Lob Wedge": "LW",
        "Putter": "Pt"
    ]
    return map[name] ?? (name.count <= 3 ? name : String(name.prefix(2)))
}
