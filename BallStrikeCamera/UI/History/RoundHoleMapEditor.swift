import SwiftUI
import MapKit
import CoreLocation

// MARK: - RoundHoleMapEditSheet
//
// Post-round shot editing ON the hole itself (History → Fix logged shots → tap a hole).
// Every logged shot is a numbered pin exactly where it was hit from: tap one to change its
// club, move it, or delete it — or drop a forgotten shot right where it happened, with the
// yardage read straight off the placement. Putts never show a yardage (distances run to the
// green CENTER and the pin moves daily); a putt's pin exists to finish off the shot before
// it — the 7-iron's end is where the putter came out.

struct RoundHoleMapEditSheet: View {
    @Binding var round: CourseRound
    let holeNumber: Int
    let clubs: [UserClub]
    /// Cached OSM geometry — nil degrades to shots-only framing, no line/green context.
    let hole: GolfHole?
    let teeBoxName: String
    /// Called after every mutation so the owner can re-verify / auto-snap the tee shot.
    var onMutate: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    private enum Mode: Equatable { case browse, placingNew, movingShot(UUID) }
    @State private var mode: Mode = .browse
    @State private var selectedShotId: UUID?
    @State private var pendingCoord: CLLocationCoordinate2D?
    @State private var pendingAfterIndex = 0
    @State private var pendingClubId: UUID?

    private var holeIdx: Int? { round.holes.firstIndex { $0.holeNumber == holeNumber } }
    private var roundHole: RoundHole? { holeIdx.map { round.holes[$0] } }
    private var shots: [TrackedShot] {
        (roundHole?.trackedShots ?? []).sorted { $0.shotIndex < $1.shotIndex }
    }
    private var greenCL: CLLocationCoordinate2D? { hole?.greenCenterCoordinate?.clCoordinate }
    private var teeCL: CLLocationCoordinate2D? {
        (hole?.teeCoordinateByTeeBox?[teeBoxName] ?? hole?.teeCoordinate)?.clCoordinate
    }
    private var centerline: [CLLocationCoordinate2D] {
        hole.flatMap { CourseRoundViewModel.holeCenterline(hole: $0, teeBoxName: teeBoxName) }?
            .map { $0.clCoordinate } ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ShotMapEditView(
                    shots: shots,
                    holeLine: centerline,
                    green: greenCL,
                    tee: teeCL,
                    selectedShotId: selectedShotId,
                    placementActive: mode != .browse,
                    pendingCoord: pendingCoord,
                    onSelect: { id in
                        if mode == .browse { selectedShotId = id }
                    },
                    onPlace: { coord in
                        switch mode {
                        case .placingNew:
                            pendingCoord = coord
                            pendingAfterIndex = inferredAfterIndex(for: coord)
                        case .movingShot(let id):
                            moveShot(id, to: coord)
                            mode = .browse
                        case .browse:
                            break
                        }
                    }
                )
                .ignoresSafeArea(edges: .bottom)

                panel
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
            }
            .navigationTitle("Hole \(holeNumber)\(roundHole?.score.map { " · \($0)" } ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(TCTheme.sage)
                }
            }
        }
    }

    // MARK: Bottom panel

    @ViewBuilder
    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch mode {
            case .placingNew:
                if let coord = pendingCoord {
                    addForm(coord)
                } else {
                    instruction("Tap the map right where you hit the shot from.")
                }
            case .movingShot:
                instruction("Tap where this shot was actually hit from.")
            case .browse:
                if let shot = shots.first(where: { $0.id == selectedShotId }) {
                    selectedPanel(shot)
                } else {
                    browsePanel
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TCTheme.panel.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(TCTheme.border, lineWidth: 1))
    }

    private var browsePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(shots.isEmpty
                 ? "No logged shots on this hole — add each one where it was hit from."
                 : "Tap a numbered pin to edit that shot, or add one you forgot.")
                .font(.system(size: 12))
                .foregroundColor(TCTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                pendingClubId = nil
                pendingCoord = nil
                mode = .placingNew
            } label: {
                Label("Add a missed shot", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(TCTheme.sage))
            }
            .buttonStyle(.plain)
        }
    }

    private func selectedPanel(_ shot: TrackedShot) -> some View {
        let isPutter = shot.club?.category == .putter
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(shot.shotIndex)")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundColor(TCTheme.gold)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(TCTheme.gold.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Menu {
                        ForEach(clubs) { c in
                            Button(c.name) { changeClub(shot.id, ShotClub(userClub: c)) }
                        }
                        Button("No club") { changeClub(shot.id, nil) }
                    } label: {
                        HStack(spacing: 5) {
                            Text(shot.club?.name ?? "Pick club")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(TCTheme.textPrimary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(TCTheme.sage)
                        }
                    }
                    Text(isPutter
                         ? "Putt — marks where the shot before it finished"
                         : "\(shot.lie.displayName)\(shot.distanceYards > 0 ? " · \(Int(shot.distanceYards)) yd" : "")")
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                Button { selectedShotId = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(TCTheme.border.opacity(0.5)))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                Button { mode = .movingShot(shot.id) } label: {
                    Label("Move", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(TCTheme.sage)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(TCTheme.sage.opacity(0.14)))
                }
                .buttonStyle(.plain)
                Button { deleteShot(shot.id) } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(TCTheme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(TCTheme.danger.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func addForm(_ coord: CLLocationCoordinate2D) -> some View {
        let pendingIsPutter = clubs.first { $0.id == pendingClubId }?.type == .putter
        return VStack(alignment: .leading, spacing: 10) {
            Text("ADD SHOT HERE")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(TCTheme.textMuted)
                .kerning(1.1)
            if pendingIsPutter {
                Text("Putt — no yardage shown (the pin moves daily). Its spot finishes off the shot before it.")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let g = greenCL {
                Text("≈ \(Int(coord.yards(to: g).rounded())) yds to the green — tap again to adjust.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.gold)
            }
            HStack(spacing: 10) {
                Menu {
                    ForEach(clubs) { c in
                        Button(c.name) { pendingClubId = c.id }
                    }
                    Button("No club") { pendingClubId = nil }
                } label: {
                    formChip(title: clubs.first { $0.id == pendingClubId }?.name ?? "Club")
                }
                Menu {
                    ForEach(0...shots.count, id: \.self) { after in
                        Button("Play as shot \(after + 1)") { pendingAfterIndex = after }
                    }
                } label: {
                    formChip(title: "Shot \(pendingAfterIndex + 1)")
                }
            }
            HStack {
                Button("Cancel") {
                    pendingCoord = nil
                    mode = .browse
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TCTheme.textMuted)
                Spacer()
                Button { addShot(at: coord) } label: {
                    Text("Add Shot")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(TCTheme.sage))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func instruction(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(TCTheme.gold)
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Cancel") {
                pendingCoord = nil
                mode = .browse
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(TCTheme.textMuted)
        }
    }

    private func formChip(title: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(TCTheme.sage)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(TCTheme.border.opacity(0.4)))
    }

    // MARK: Mutations (statics from CourseRoundViewModel keep History + in-round identical)

    /// Where the placed shot slots into the sequence: shots farther from the green than the
    /// placement happened earlier. Overridable in the form.
    private func inferredAfterIndex(for coord: CLLocationCoordinate2D) -> Int {
        guard let g = greenCL else { return shots.count }
        let d = coord.yards(to: g)
        return shots.filter { $0.startCoordinate.clCoordinate.yards(to: g) > d }.count
    }

    private func moveShot(_ id: UUID, to coord: CLLocationCoordinate2D) {
        guard let h = holeIdx,
              let s = round.holes[h].trackedShots.firstIndex(where: { $0.id == id }) else { return }
        let c = Coordinate(coord)
        round.holes[h].trackedShots[s].startCoordinate = c
        round.holes[h].trackedShots[s].recomputeDistance()
        // The shot before it landed where this one was hit from.
        let idx = round.holes[h].trackedShots[s].shotIndex
        if let prev = round.holes[h].trackedShots.firstIndex(where: { $0.shotIndex == idx - 1 }) {
            round.holes[h].trackedShots[prev].endCoordinate = c
            round.holes[h].trackedShots[prev].recomputeDistance()
        }
        onMutate()
    }

    private func deleteShot(_ id: UUID) {
        round = CourseRoundViewModel.removeTrackedShot(id, from: round) ?? round
        selectedShotId = nil
        onMutate()
    }

    private func changeClub(_ id: UUID, _ club: ShotClub?) {
        round = CourseRoundViewModel.updateTrackedShotClub(id, club: club, in: round) ?? round
        onMutate()
    }

    private func addShot(at coord: CLLocationCoordinate2D) {
        let club = clubs.first { $0.id == pendingClubId }.map { ShotClub(userClub: $0) }
        let end: Coordinate? = pendingAfterIndex >= shots.count ? greenCL.map { Coordinate($0) } : nil
        round = CourseRoundViewModel.insertTrackedShot(
            club: club, start: Coordinate(coord), end: end,
            afterIndex: pendingAfterIndex, holeNumber: holeNumber, in: round) ?? round
        pendingCoord = nil
        mode = .browse
        onMutate()
    }
}

// MARK: - Map view (UIKit)

private final class ShotPinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let shotId: UUID
    let number: Int
    let isPutter: Bool
    let isSelected: Bool
    init(shot: TrackedShot, selected: Bool) {
        coordinate = shot.startCoordinate.clCoordinate
        shotId = shot.id
        number = shot.shotIndex
        isPutter = shot.club?.category == .putter
        isSelected = selected
        super.init()
    }
}

private final class EditorFlagAnnotation: MKPointAnnotation {}
private final class EditorPendingAnnotation: MKPointAnnotation {}
private final class EditorHoleLinePolyline: MKPolyline {}
private final class EditorShotSegmentPolyline: MKPolyline {}

private struct ShotMapEditView: UIViewRepresentable {
    let shots: [TrackedShot]
    let holeLine: [CLLocationCoordinate2D]
    let green: CLLocationCoordinate2D?
    let tee: CLLocationCoordinate2D?
    let selectedShotId: UUID?
    let placementActive: Bool
    let pendingCoord: CLLocationCoordinate2D?
    let onSelect: (UUID?) -> Void
    let onPlace: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .satellite
        map.delegate = context.coordinator
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.mapTapped(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        fitCamera(map)
        rebuildContent(map)
        context.coordinator.lastSignature = signature
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        let sig = signature
        guard sig != context.coordinator.lastSignature else { return }
        context.coordinator.lastSignature = sig
        rebuildContent(map)
    }

    /// Cheap change detection — annotations only rebuild when shots/selection/pending move.
    private var signature: String {
        var s = shots.map {
            "\($0.id)|\($0.shotIndex)|\($0.startCoordinate.latitude)|\($0.startCoordinate.longitude)|\($0.endCoordinate.latitude)|\($0.club?.name ?? "-")"
        }.joined(separator: ";")
        s += "#sel=\(selectedShotId?.uuidString ?? "-")"
        s += "#pend=\(pendingCoord.map { "\($0.latitude),\($0.longitude)" } ?? "-")"
        return s
    }

    private func rebuildContent(_ map: MKMapView) {
        map.removeAnnotations(map.annotations)
        map.removeOverlays(map.overlays)
        if holeLine.count >= 2 {
            var pts = holeLine
            map.addOverlay(EditorHoleLinePolyline(coordinates: &pts, count: pts.count))
        }
        // Shot flight segments (start → end). Putts draw no segment — only their pin, which
        // is the previous shot's landing spot.
        for shot in shots where shot.club?.category != .putter {
            var pts = [shot.startCoordinate.clCoordinate, shot.endCoordinate.clCoordinate]
            if abs(pts[0].latitude - pts[1].latitude) > 1e-9
                || abs(pts[0].longitude - pts[1].longitude) > 1e-9 {
                map.addOverlay(EditorShotSegmentPolyline(coordinates: &pts, count: 2))
            }
        }
        for shot in shots {
            map.addAnnotation(ShotPinAnnotation(shot: shot, selected: shot.id == selectedShotId))
        }
        if let green {
            let f = EditorFlagAnnotation()
            f.coordinate = green
            map.addAnnotation(f)
        }
        if let pendingCoord {
            let p = EditorPendingAnnotation()
            p.coordinate = pendingCoord
            map.addAnnotation(p)
        }
    }

    private func fitCamera(_ map: MKMapView) {
        var coords: [CLLocationCoordinate2D] = shots.map { $0.startCoordinate.clCoordinate }
        coords += shots.map { $0.endCoordinate.clCoordinate }
        if let tee { coords.append(tee) }
        if let green { coords.append(green) }
        coords += holeLine
        guard let first = coords.first else { return }
        guard coords.count >= 2 else {
            map.camera = MKMapCamera(lookingAtCenter: first, fromDistance: 700, pitch: 0, heading: 0)
            return
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let diag = CLLocation(latitude: minLat, longitude: minLon)
            .distance(from: CLLocation(latitude: maxLat, longitude: maxLon))
        // Hole plays bottom → top (tee at the bottom of the screen), like course mode.
        let start = tee ?? first
        let end = green ?? coords[coords.count - 1]
        let heading = start.bearing(to: end)
        // Empirical MapKit FOV at pitch 0: visible vertical ≈ 0.537 × altitude. The wide
        // padding keeps the tee pin clear of the bottom edit panel and the title bar.
        map.camera = MKMapCamera(lookingAtCenter: center,
                                 fromDistance: max(diag, 120) / 0.537 * 1.65,
                                 pitch: 0, heading: heading)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: ShotMapEditView
        var lastSignature = ""
        init(_ parent: ShotMapEditView) { self.parent = parent }

        @objc func mapTapped(_ gr: UITapGestureRecognizer) {
            guard parent.placementActive, let map = gr.view as? MKMapView else { return }
            parent.onPlace(map.convert(gr.location(in: map), toCoordinateFrom: map))
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard !parent.placementActive else {
                mapView.deselectAnnotation(view.annotation, animated: false)
                return
            }
            if let pin = view.annotation as? ShotPinAnnotation {
                parent.onSelect(pin.shotId)
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            if view.annotation is ShotPinAnnotation, !parent.placementActive {
                parent.onSelect(nil)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let pin = annotation as? ShotPinAnnotation {
                let id = "editorShotPin"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: pin, reuseIdentifier: id)
                v.annotation = pin
                v.image = ShotPinArt.image(number: pin.number, isPutter: pin.isPutter,
                                           selected: pin.isSelected)
                v.centerOffset = .zero
                v.canShowCallout = false
                return v
            }
            if annotation is EditorFlagAnnotation {
                let id = "editorFlag"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.image = ShotPinArt.symbol("flag.fill", pointSize: 20,
                                            color: UIColor(red: 1, green: 0.84, blue: 0, alpha: 1))
                v.centerOffset = CGPoint(x: 6, y: -10)
                return v
            }
            if annotation is EditorPendingAnnotation {
                let id = "editorPending"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.image = ShotPinArt.symbol("mappin.circle.fill", pointSize: 30,
                                            color: UIColor(red: 1, green: 0.84, blue: 0, alpha: 1))
                v.centerOffset = CGPoint(x: 0, y: -6)
                return v
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let l = overlay as? EditorHoleLinePolyline {
                let r = MKPolylineRenderer(polyline: l)
                r.strokeColor = UIColor.white.withAlphaComponent(0.55)
                r.lineWidth = 2
                r.lineDashPattern = [6, 6]
                return r
            }
            if let l = overlay as? EditorShotSegmentPolyline {
                let r = MKPolylineRenderer(polyline: l)
                r.strokeColor = UIColor(red: 1, green: 0.84, blue: 0, alpha: 0.85)
                r.lineWidth = 2.5
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

/// Rendered pin art: numbered forest-green circle for swings, a light "P" disc for putts.
private enum ShotPinArt {
    /// SF symbol rasterized with the color baked in — MKAnnotationView renders template /
    /// palette-configured symbol images black, so tint must be burned into the bitmap.
    static func symbol(_ name: String, pointSize: CGFloat, color: UIColor) -> UIImage? {
        let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        guard let base = UIImage(systemName: name, withConfiguration: cfg) else { return nil }
        return UIGraphicsImageRenderer(size: base.size).image { _ in
            base.withTintColor(color).draw(at: .zero)
        }
    }

    static func image(number: Int, isPutter: Bool, selected: Bool) -> UIImage {
        let d: CGFloat = selected ? 40 : 30
        return UIGraphicsImageRenderer(size: CGSize(width: d, height: d)).image { _ in
            let rect = CGRect(x: 1.5, y: 1.5, width: d - 3, height: d - 3)
            let fill = isPutter
                ? UIColor(white: 0.94, alpha: 1)
                : UIColor(red: 0.10, green: 0.23, blue: 0.13, alpha: 1)
            fill.setFill()
            UIBezierPath(ovalIn: rect).fill()
            let ring = UIBezierPath(ovalIn: rect)
            ring.lineWidth = selected ? 3 : 1.5
            (selected ? UIColor(red: 1, green: 0.84, blue: 0, alpha: 1) : UIColor.white).setStroke()
            ring.stroke()
            let text = isPutter ? "P" : "\(number)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: selected ? 17 : 13, weight: .heavy),
                .foregroundColor: isPutter ? UIColor.black : UIColor.white,
            ]
            let sz = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: (d - sz.width) / 2, y: (d - sz.height) / 2),
                                    withAttributes: attrs)
        }
    }
}
