import SwiftUI
import MapKit

// MARK: - Distance Bubble Annotation

private class DistanceBubbleAnnotation: NSObject, MKAnnotation {
    enum Style {
        case primary
        case secondary
        case compact
    }

    let coordinate: CLLocationCoordinate2D
    let yardage: Int
    let label: String?
    let style: Style

    init(coordinate: CLLocationCoordinate2D, yardage: Int, label: String? = nil, style: Style = .compact) {
        self.coordinate = coordinate
        self.yardage    = yardage
        self.label      = label
        self.style      = style
    }
}

private class DistanceBubbleAnnotationView: MKAnnotationView {
    private let bubbleLabel = UILabel()
    private let container   = UIView()
    private var bubbleStyle: DistanceBubbleAnnotation.Style = .compact

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 68, height: 30)
        centerOffset = CGPoint(x: 0, y: -15)
        backgroundColor = .clear
        setupBubble()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupBubble() {
        container.backgroundColor = UIColor(white: 0.05, alpha: 0.82)
        container.frame = bounds
        addSubview(container)

        bubbleLabel.textColor     = .white
        bubbleLabel.textAlignment = .center
        bubbleLabel.frame         = container.bounds
        container.addSubview(bubbleLabel)
    }

    override var annotation: MKAnnotation? {
        didSet {
            guard let a = annotation as? DistanceBubbleAnnotation else { return }
            bubbleStyle = a.style
            bubbleLabel.text = a.label.map { "\($0) \(a.yardage)" } ?? "\(a.yardage)"
            applyStyle(for: a.style)
            sizeToFit()
        }
    }

    private func applyStyle(for style: DistanceBubbleAnnotation.Style) {
        switch style {
        case .primary:
            bubbleLabel.font = UIFont.systemFont(ofSize: 18, weight: .heavy)
            container.layer.cornerRadius = 22
            container.layer.borderWidth  = 2.5
        case .secondary:
            bubbleLabel.font = UIFont.systemFont(ofSize: 16, weight: .heavy)
            container.layer.cornerRadius = 18
            container.layer.borderWidth  = 2.0
        case .compact:
            bubbleLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
            container.layer.cornerRadius = 12
            container.layer.borderWidth  = 1.0
        }
        container.layer.borderColor = UIColor(white: 1.0, alpha: style == .compact ? 0.18 : 0.92).cgColor
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let a = annotation as? DistanceBubbleAnnotation else { return CGSize(width: 68, height: 30) }
        let text = a.label.map { "\($0) \(a.yardage)" } ?? "\(a.yardage)"
        let font: UIFont
        let minWidth: CGFloat
        let height: CGFloat
        switch a.style {
        case .primary:
            font = UIFont.systemFont(ofSize: 18, weight: .heavy)
            minWidth = 62
            height = 44
        case .secondary:
            font = UIFont.systemFont(ofSize: 16, weight: .heavy)
            minWidth = 56
            height = 36
        case .compact:
            font = UIFont.systemFont(ofSize: 12, weight: .bold)
            minWidth = 56
            height = 30
        }
        let attrs = [NSAttributedString.Key.font: font]
        let width = (text as NSString).size(withAttributes: attrs).width + 24
        return CGSize(width: max(width, minWidth), height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        container.frame    = bounds
        bubbleLabel.frame  = container.bounds
        centerOffset       = CGPoint(x: 0, y: -bounds.height / 2 - 2)
    }
}

// MARK: - Flag / Pin Annotation

private class GreenPinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
    var title: String? { "Pin" }
}

// MARK: - Identifiable coordinate box (for sheet(item:))

private struct CoordinateBox: Identifiable {
    let id = UUID()
    let coord: CLLocationCoordinate2D
}

// MARK: - Tagged Polygon (carries a kind so the renderer can style it)

private final class TaggedPolygon: MKPolygon {
    var kind: String = "fairway"

    static func make(kind: String, coordinates: [CLLocationCoordinate2D]) -> TaggedPolygon {
        var pts = coordinates
        let p = TaggedPolygon(coordinates: &pts, count: pts.count)
        p.kind = kind
        return p
    }
}

// MARK: - Shot rendering primitives

/// Polyline subclass so the renderer can distinguish shot paths from the user→green line.
private final class ShotPolyline: MKPolyline {}

// MARK: - HUD flight animation primitives

/// One-shot request to animate a ball flying from `start` to `end` on the map.
/// Identity (`id`) drives the animation trigger; same id = no re-fire.
private struct FlightRequest: Equatable {
    let id: UUID
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    static func == (a: FlightRequest, b: FlightRequest) -> Bool { a.id == b.id }
}

/// Transient growing trail behind the flying ball.
private final class FlightTrailPolyline: MKPolyline {}

/// Transient flying-ball annotation (white dot) animated by the coordinator.
private final class FlightBallAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

private final class FlightBallAnnotationView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 16, height: 16)
        backgroundColor = .clear
        let dot = UIView(frame: bounds)
        dot.backgroundColor = .white
        dot.layer.cornerRadius = 8
        dot.layer.borderColor = UIColor.black.withAlphaComponent(0.4).cgColor
        dot.layer.borderWidth = 1
        dot.layer.shadowColor = UIColor.white.cgColor
        dot.layer.shadowRadius = 4
        dot.layer.shadowOpacity = 0.9
        dot.layer.shadowOffset = .zero
        addSubview(dot)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class ShotEndAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let shotIndex: Int
    let shotId: UUID
    let clubLabel: String
    let distanceYds: Int

    init(coordinate: CLLocationCoordinate2D, shotIndex: Int, shotId: UUID,
         clubLabel: String, distanceYds: Int) {
        self.coordinate = coordinate
        self.shotIndex  = shotIndex
        self.shotId     = shotId
        self.clubLabel  = clubLabel
        self.distanceYds = distanceYds
    }
    var title: String? { "Shot \(shotIndex)" }
    var subtitle: String? { "\(distanceYds) yd · \(clubLabel)" }
}

private final class ShotEndAnnotationView: MKAnnotationView {
    private let circle = UIView()
    private let label  = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 26, height: 26)
        centerOffset = CGPoint(x: 0, y: 0)
        backgroundColor = .clear
        circle.frame = bounds
        circle.backgroundColor = UIColor(red: 1.0, green: 0.82, blue: 0.0, alpha: 0.95)
        circle.layer.cornerRadius = 13
        circle.layer.borderColor = UIColor.black.withAlphaComponent(0.6).cgColor
        circle.layer.borderWidth = 1.5
        addSubview(circle)
        label.frame = bounds
        label.textAlignment = .center
        label.textColor = .black
        label.font = UIFont.systemFont(ofSize: 12, weight: .black)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var annotation: MKAnnotation? {
        didSet {
            guard let a = annotation as? ShotEndAnnotation else { return }
            label.text = "\(a.shotIndex)"
        }
    }
}

// MARK: - Satellite Map Background

private struct SatelliteMapBackground: UIViewRepresentable {
    var greenCoord:  CLLocationCoordinate2D?
    var teeCoord:    CLLocationCoordinate2D?
    var userCoord:   CLLocationCoordinate2D?
    var courseCoord: CLLocationCoordinate2D?
    var frontCoord:  CLLocationCoordinate2D?
    var backCoord:   CLLocationCoordinate2D?
    var frontDist:   Int?
    var centerDist:  Int?
    var backDist:    Int?

    // Hole geometry overlays (optional; only drawn when present)
    var greenPolygon:    [CLLocationCoordinate2D]?
    var fairwayPolygon:  [CLLocationCoordinate2D]?
    var bunkerPolygons:  [[CLLocationCoordinate2D]] = []
    var waterPolygons:   [[CLLocationCoordinate2D]] = []

    // Tracked shot polylines + markers (current hole only)
    var trackedShots:    [TrackedShot] = []

    // When non-nil, taps on the map are forwarded to this closure.
    var onMapTap:        ((CLLocationCoordinate2D) -> Void)? = nil
    var focusId:         String = ""
    var recenterToken:   Int = 0

    // HUD flight animation (transient). When a new request id arrives, the coordinator
    // animates a ball start->end and calls onFlightCompleted with the landing coordinate.
    var flightRequest:   FlightRequest? = nil
    var onFlightCompleted: ((CLLocationCoordinate2D) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Camera geometry helpers

    private func coordsEqual(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < 1e-6 && abs(a.longitude - b.longitude) < 1e-6
    }

    static func midpoint(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2,
                               longitude: (a.longitude + b.longitude) / 2)
    }

    /// Linear interpolation between two coordinates (t in 0...1).
    static func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, t: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                               longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    /// Initial bearing in degrees (0 = north) from `a` to `b`.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType             = .hybrid
        map.isScrollEnabled     = true
        map.isZoomEnabled       = true
        map.isRotateEnabled     = false
        map.isPitchEnabled      = false
        map.showsUserLocation   = true
        map.showsCompass        = false
        map.delegate            = context.coordinator
        context.coordinator.parent = self
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                          action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        // Preserve any in-flight transient ball/trail across SwiftUI re-renders.
        map.removeOverlays(map.overlays.filter { !($0 is FlightTrailPolyline) })
        map.removeAnnotations(map.annotations.filter {
            !($0 is MKUserLocation) && !($0 is FlightBallAnnotation)
        })

        // Kick off a flight if a new request arrived.
        if let req = flightRequest, context.coordinator.lastFlightId != req.id {
            context.coordinator.lastFlightId = req.id
            context.coordinator.runFlight(on: map, from: req.start, to: req.end) { [weak coordinator = context.coordinator] landing in
                coordinator?.parent?.onFlightCompleted?(landing)
            }
        }

        let shouldRecenter = context.coordinator.shouldRecenter(for: focusId,
                                                                recenterToken: recenterToken)

        // Region / camera
        // Preferred: 18Birdies-style "down the hole" view — frame the whole hole from the
        // tee (bottom) to the green (top), rotated so you look straight down the fairway.
        let lineStart = teeCoord ?? userCoord            // bottom of the hole
        if let green = greenCoord, let start = lineStart, !coordsEqual(start, green) {
            if shouldRecenter {
                let mid = Self.midpoint(start, green)
                let holeMeters = MKMapPoint(start).distance(to: MKMapPoint(green))
                let heading = Self.bearing(from: start, to: green)   // green points "up"
                // Bias the center slightly toward the green so the forward hole fills more
                // of the (taller) portrait view, with the tee near the bottom edge.
                let biasedCenter = Self.interpolate(start, green, t: 0.55)
                let camDistance = max(holeMeters * 1.55 + 120, 280)
                let cam = MKMapCamera(lookingAtCenter: biasedCenter,
                                      fromDistance: camDistance,
                                      pitch: 0,
                                      heading: heading)
                _ = mid
                context.coordinator.setProgrammaticRegionChange(true)
                map.setCamera(cam, animated: context.coordinator.hasInitializedRegion)
                context.coordinator.completeRecenter(focusId: focusId, recenterToken: recenterToken)
            }
            // The hole reference line: tee → pin.
            var pts = [start, green]
            map.addOverlay(MKPolyline(coordinates: &pts, count: 2))
        } else if let green = greenCoord {
            if shouldRecenter {
                context.coordinator.setProgrammaticRegionChange(true)
                map.setRegion(
                    MKCoordinateRegion(center: green,
                                       latitudinalMeters: 350,
                                       longitudinalMeters: 350),
                    animated: context.coordinator.hasInitializedRegion
                )
                context.coordinator.completeRecenter(focusId: focusId, recenterToken: recenterToken)
            }
        } else {
            // Always center on the course/hole — never follow the user's GPS alone
            let center = courseCoord ?? CLLocationCoordinate2D(latitude: 37.785834, longitude: -122.406417)
            if shouldRecenter {
                context.coordinator.setProgrammaticRegionChange(true)
                map.setRegion(
                    MKCoordinateRegion(center: center,
                                       latitudinalMeters: 400,
                                       longitudinalMeters: 400),
                    animated: context.coordinator.hasInitializedRegion
                )
                context.coordinator.completeRecenter(focusId: focusId, recenterToken: recenterToken)
            }
        }

        // Polygon overlays — drawn under everything else. Filter water/bunkers against the
        // visible map region so off-screen polygons don't burn CPU on render.
        let region = map.region
        func intersectsVisible(_ ring: [CLLocationCoordinate2D]) -> Bool {
            guard !ring.isEmpty else { return false }
            let half = region.span
            let cLat = region.center.latitude,  cLon = region.center.longitude
            let minLat = cLat - half.latitudeDelta,  maxLat = cLat + half.latitudeDelta
            let minLon = cLon - half.longitudeDelta, maxLon = cLon + half.longitudeDelta
            var rMinLat = ring[0].latitude,  rMaxLat = ring[0].latitude
            var rMinLon = ring[0].longitude, rMaxLon = ring[0].longitude
            for c in ring {
                rMinLat = Swift.min(rMinLat, c.latitude);  rMaxLat = Swift.max(rMaxLat, c.latitude)
                rMinLon = Swift.min(rMinLon, c.longitude); rMaxLon = Swift.max(rMaxLon, c.longitude)
            }
            // AABB intersection test
            return !(rMaxLat < minLat || rMinLat > maxLat ||
                     rMaxLon < minLon || rMinLon > maxLon)
        }
        // Order matters: water/fairway first (background), then bunkers, then green (on top).
        for ring in waterPolygons where ring.count >= 3 && intersectsVisible(ring) {
            map.addOverlay(TaggedPolygon.make(kind: "water", coordinates: ring), level: .aboveRoads)
        }
        if let fw = fairwayPolygon, fw.count >= 3 {
            map.addOverlay(TaggedPolygon.make(kind: "fairway", coordinates: fw), level: .aboveRoads)
        }
        for ring in bunkerPolygons where ring.count >= 3 && intersectsVisible(ring) {
            map.addOverlay(TaggedPolygon.make(kind: "bunker", coordinates: ring), level: .aboveRoads)
        }
        if let g = greenPolygon, g.count >= 3 {
            map.addOverlay(TaggedPolygon.make(kind: "green", coordinates: g), level: .aboveRoads)
        }

        // Yellow flag at green center
        if let green = greenCoord {
            map.addAnnotation(GreenPinAnnotation(coordinate: green))
        }

        // Distance bubble annotations
        if let coord = frontCoord, let dist = frontDist {
            map.addAnnotation(DistanceBubbleAnnotation(coordinate: coord, yardage: dist, label: "F"))
        }
        if let coord = greenCoord, let dist = centerDist {
            let offsetCoord = CLLocationCoordinate2D(
                latitude:  coord.latitude  + 0.00005,
                longitude: coord.longitude - 0.00010
            )
            map.addAnnotation(DistanceBubbleAnnotation(coordinate: offsetCoord, yardage: dist, label: "C"))
        }
        if let coord = backCoord, let dist = backDist {
            map.addAnnotation(DistanceBubbleAnnotation(coordinate: coord, yardage: dist, label: "B"))
        }

        // Tracked shot polylines + markers
        for shot in trackedShots {
            var pts = [shot.startCoordinate.clCoordinate, shot.endCoordinate.clCoordinate]
            let line = ShotPolyline(coordinates: &pts, count: 2)
            map.addOverlay(line, level: .aboveLabels)
            map.addAnnotation(ShotEndAnnotation(
                coordinate: shot.endCoordinate.clCoordinate,
                shotIndex: shot.shotIndex,
                shotId: shot.id,
                clubLabel: shot.club?.category.displayName.prefix(1).uppercased() ?? "·",
                distanceYds: Int(shot.distanceYards.rounded())
            ))
        }

        context.coordinator.parent = self
    }

    // MARK: Coordinator

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {

        var parent: SatelliteMapBackground?
        var hasInitializedRegion = false
        private var lastFocusId = ""
        private var lastRecenterToken = -1
        private var isProgrammaticRegionChange = false

        // Flight animation state
        var lastFlightId: UUID?
        private var flightTimer: Timer?
        private weak var flightBall: FlightBallAnnotation?
        private weak var flightTrail: FlightTrailPolyline?

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let onTap = parent?.onMapTap, let map = gr.view as? MKMapView else { return }
            let pt = gr.location(in: map)
            let coord = map.convert(pt, toCoordinateFrom: map)
            onTap(coord)
        }

        // MARK: Flight animation

        /// Animate a ball from `start` to `end` over ~2.0s with an ease-out and a growing
        /// trail, framing both endpoints. Runs entirely in UIKit (no SwiftUI churn).
        func runFlight(on map: MKMapView,
                       from start: CLLocationCoordinate2D,
                       to end: CLLocationCoordinate2D,
                       completion: @escaping (CLLocationCoordinate2D) -> Void) {
            flightTimer?.invalidate()
            if let b = flightBall { map.removeAnnotation(b) }
            if let t = flightTrail { map.removeOverlay(t) }

            // Frame the flight keeping the "down the hole" orientation (ball flies upward).
            let mid = SatelliteMapBackground.midpoint(start, end)
            let biased = SatelliteMapBackground.interpolate(start, end, t: 0.55)
            let flightMeters = MKMapPoint(start).distance(to: MKMapPoint(end))
            let heading = SatelliteMapBackground.bearing(from: start, to: end)
            _ = mid
            setProgrammaticRegionChange(true)
            map.setCamera(MKMapCamera(lookingAtCenter: biased,
                                      fromDistance: max(flightMeters * 1.7 + 120, 280),
                                      pitch: 0,
                                      heading: heading),
                          animated: true)

            let ball = FlightBallAnnotation(coordinate: start)
            map.addAnnotation(ball)
            flightBall = ball

            let duration: CFTimeInterval = 2.0
            let startTime = CACurrentMediaTime()
            // Slight lateral curve so it reads as a shot, not a ruler line.
            let curveMagnitude = 0.00018

            flightTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak map] timer in
                guard let self, let map else { timer.invalidate(); return }
                let raw = min(1.0, (CACurrentMediaTime() - startTime) / duration)
                let t = 1 - pow(1 - raw, 2)            // ease-out
                let lat = start.latitude  + (end.latitude  - start.latitude)  * t
                let lon = start.longitude + (end.longitude - start.longitude) * t
                // perpendicular curve, peaks at t=0.5
                let bump = sin(t * .pi) * curveMagnitude
                let dx = end.longitude - start.longitude
                let dy = end.latitude - start.latitude
                let len = max(sqrt(dx*dx + dy*dy), 1e-9)
                let px = -dy / len, py = dx / len
                let cur = CLLocationCoordinate2D(latitude: lat + py * bump,
                                                 longitude: lon + px * bump)
                ball.coordinate = cur

                // Rebuild growing trail.
                if let old = self.flightTrail { map.removeOverlay(old) }
                var pts = [start, cur]
                let trail = FlightTrailPolyline(coordinates: &pts, count: 2)
                map.addOverlay(trail, level: .aboveLabels)
                self.flightTrail = trail

                if raw >= 1.0 {
                    timer.invalidate()
                    self.flightTimer = nil
                    // Brief settle, then clean up transient visuals and report landing.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak map] in
                        if let b = self.flightBall { map?.removeAnnotation(b) }
                        if let tr = self.flightTrail { map?.removeOverlay(tr) }
                        self.flightBall = nil
                        self.flightTrail = nil
                        completion(end)
                    }
                }
            }
        }

        func shouldRecenter(for focusId: String, recenterToken: Int) -> Bool {
            !hasInitializedRegion || focusId != lastFocusId || recenterToken != lastRecenterToken
        }

        func completeRecenter(focusId: String, recenterToken: Int) {
            hasInitializedRegion = true
            lastFocusId = focusId
            lastRecenterToken = recenterToken
        }

        func setProgrammaticRegionChange(_ value: Bool) {
            isProgrammaticRegionChange = value
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if isProgrammaticRegionChange {
                isProgrammaticRegionChange = false
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? TaggedPolygon {
                let r = MKPolygonRenderer(polygon: polygon)
                switch polygon.kind {
                case "green":
                    r.fillColor   = UIColor(red: 0.42, green: 0.82, blue: 0.42, alpha: 0.65)
                    r.strokeColor = UIColor(red: 0.18, green: 0.60, blue: 0.28, alpha: 0.95)
                    r.lineWidth   = 1.2
                case "fairway":
                    r.fillColor   = UIColor(red: 0.36, green: 0.66, blue: 0.34, alpha: 0.45)
                    r.strokeColor = UIColor(red: 0.20, green: 0.48, blue: 0.22, alpha: 0.60)
                    r.lineWidth   = 0.8
                case "bunker":
                    r.fillColor   = UIColor(red: 0.95, green: 0.86, blue: 0.62, alpha: 0.85)
                    r.strokeColor = UIColor(red: 0.80, green: 0.68, blue: 0.42, alpha: 1.0)
                    r.lineWidth   = 1.0
                case "water":
                    r.fillColor   = UIColor(red: 0.20, green: 0.50, blue: 0.85, alpha: 0.65)
                    r.strokeColor = UIColor(red: 0.10, green: 0.35, blue: 0.70, alpha: 0.90)
                    r.lineWidth   = 1.0
                default:
                    r.fillColor   = UIColor.systemGreen.withAlphaComponent(0.4)
                }
                return r
            }
            if overlay is FlightTrailPolyline, let line = overlay as? MKPolyline {
                let r         = MKPolylineRenderer(polyline: line)
                r.strokeColor = UIColor.white.withAlphaComponent(0.95)
                r.lineWidth   = 3.0
                return r
            }
            if overlay is ShotPolyline, let line = overlay as? MKPolyline {
                let r         = MKPolylineRenderer(polyline: line)
                r.strokeColor = UIColor(red: 1.0, green: 0.82, blue: 0.0, alpha: 0.95)
                r.lineWidth   = 3.5
                return r
            }
            if let line = overlay as? MKPolyline {
                let r             = MKPolylineRenderer(polyline: line)
                r.strokeColor     = UIColor(white: 1.0, alpha: 0.92)
                r.lineWidth       = 3.0
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }

            if annotation is FlightBallAnnotation {
                let id = "flightBall"
                let v  = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                            as? FlightBallAnnotationView
                            ?? FlightBallAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.displayPriority = .required
                return v
            }

            if let pin = annotation as? GreenPinAnnotation {
                let id  = "greenPin"
                let v   = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                            as? MKMarkerAnnotationView
                            ?? MKMarkerAnnotationView(annotation: pin, reuseIdentifier: id)
                v.annotation     = pin
                v.markerTintColor = UIColor(red: 1.0, green: 0.82, blue: 0.0, alpha: 1.0)
                v.glyphImage      = UIImage(systemName: "flag.fill")
                v.glyphTintColor  = .black
                v.displayPriority = .required
                return v
            }

            if let shot = annotation as? ShotEndAnnotation {
                let id = "shotEnd"
                let v  = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                            as? ShotEndAnnotationView
                            ?? ShotEndAnnotationView(annotation: shot, reuseIdentifier: id)
                v.annotation      = shot
                v.canShowCallout  = true
                v.displayPriority = .required
                return v
            }

            if let bubble = annotation as? DistanceBubbleAnnotation {
                let id  = "distBubble"
                let v   = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                            as? DistanceBubbleAnnotationView
                            ?? DistanceBubbleAnnotationView(annotation: bubble, reuseIdentifier: id)
                v.annotation      = bubble
                v.displayPriority = .required
                v.setNeedsLayout()
                v.layoutIfNeeded()
                return v
            }

            return nil
        }
    }
}

// MARK: - Main View

struct CourseModeGPSHoleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AuthSessionStore
    @EnvironmentObject var camera: CameraController
    @StateObject private var vm: CourseRoundViewModel

    @State private var showCamera      = false
    @State private var showScoreEntry  = false
    @State private var showScorecard   = false
    @State private var showFinishAlert = false
    @State private var gpsOn           = true
    @State private var infoMessage: String?
    @State private var roundStartTime  = Date()
    @State private var recenterToken   = 0
    @State private var trackShotMode   = false                // when true, taps place a shot
    @State private var pendingShotEnd: CLLocationCoordinate2D?
    @State private var pendingShotLie: ShotLie = .unknown
    @State private var pendingLaunchMonitorShot: SavedShot?
    // HUD flight animation state
    @State private var flightRequest: FlightRequest?
    @State private var pendingFlight: FlightRequest?     // held until camera cover dismisses
    @State private var flightStart: Coordinate?
    @State private var flightShot: SavedShot?
    #if DEBUG
    @State private var showDiagnostics = false
    #endif

    let initialCourse: GolfCourse?
    let initialTeeBox: TeeBox?
    let initialRound:  CourseRound?

    // MARK: Computed Properties

    private var currentCourseHole: GolfHole? {
        guard let hole = vm.currentHole,
              let course = vm.selectedCourse else { return nil }
        return course.holes.first { $0.number == hole.holeNumber }
    }

    private var scorecardYardage: Int? {
        guard let gh = currentCourseHole,
              let tee = vm.selectedTeeBox else { return nil }
        return gh.teeYardsByTeeBox[tee.id]
    }

    private var gpsDistances: GreenDistances {
        guard let gh = currentCourseHole else { return GreenDistances() }
        return vm.location.greenDistances(
            front:  gh.greenFrontCoordinate?.clCoordinate,
            center: gh.greenCenterCoordinate?.clCoordinate,
            back:   gh.greenBackCoordinate?.clCoordinate
        )
    }

    private var displayYardage: Int? {
        if gpsOn, let gps = gpsDistances.center { return gps }
        return scorecardYardage
    }

    private var holeHandicap: Int {
        guard let hole = vm.currentHole,
              let gh = vm.selectedCourse?.holes.first(where: { $0.number == hole.holeNumber })
        else { return vm.currentHole?.par == 3 ? 9 : 7 }
        return gh.handicap ?? 9
    }

    private var userName: String { session.userProfile?.displayName ?? "Player" }

    private var userInitials: String {
        let parts = userName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].first ?? "P").uppercased()
                 + String(parts[1].first ?? "L").uppercased()
        }
        return String(userName.prefix(2)).uppercased()
    }

    private var topSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 44
    }

    private var timeElapsed: String {
        let elapsed = Int(Date().timeIntervalSince(roundStartTime))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private var scoreToPar: Int {
        (vm.activeRound?.scoreSummary.totalScore ?? 0)
      - (vm.activeRound?.scoreSummary.totalPar   ?? 0)
    }

    private var scoreToParString: String {
        if scoreToPar == 0 { return "E" }
        return scoreToPar > 0 ? "+\(scoreToPar)" : "\(scoreToPar)"
    }

    private var scoreToParColor: Color {
        scoreToPar < 0 ? Color(red: 0.22, green: 0.78, blue: 0.42)
            : scoreToPar == 0 ? Color(red: 0.42, green: 0.72, blue: 0.98)
            : TCTheme.textMuted
    }

    private var mapFocusId: String {
        let hole = vm.currentHole?.holeNumber ?? -1
        let greenLat = currentCourseHole?.greenCenterCoordinate?.latitude ?? 0
        let greenLon = currentCourseHole?.greenCenterCoordinate?.longitude ?? 0
        // Include the tee so the camera re-frames "down the hole" the moment geometry loads.
        let teeLat = currentCourseHole?.teeCoordinate?.latitude ?? 0
        let teeLon = currentCourseHole?.teeCoordinate?.longitude ?? 0
        return "\(hole)-\(greenLat)-\(greenLon)-\(teeLat)-\(teeLon)-\(gpsOn)"
    }

    // MARK: - Init

    init(userId: UUID, backend: AppBackend,
         initialCourse: GolfCourse? = nil,
         initialTeeBox: TeeBox? = nil,
         initialRound:  CourseRound? = nil) {
        _vm = StateObject(wrappedValue: CourseRoundViewModel(userId: userId, backend: backend))
        self.initialCourse = initialCourse
        self.initialTeeBox = initialTeeBox
        self.initialRound  = initialRound
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {

            // Full-screen satellite map
            SatelliteMapBackground(
                greenCoord:  currentCourseHole?.greenCenterCoordinate?.clCoordinate,
                teeCoord:    currentCourseHole?.teeCoordinate?.clCoordinate,
                userCoord:   gpsOn ? vm.location.currentLocation : nil,
                courseCoord: vm.selectedCourse?.coordinate ?? initialCourse?.coordinate,
                frontCoord:  currentCourseHole?.greenFrontCoordinate?.clCoordinate,
                backCoord:   currentCourseHole?.greenBackCoordinate?.clCoordinate,
                frontDist:   gpsOn ? gpsDistances.front  : nil,
                centerDist:  gpsOn ? gpsDistances.center : nil,
                backDist:    gpsOn ? gpsDistances.back   : nil,
                greenPolygon:   currentCourseHole?.greenPolygon?.clCoordinates,
                fairwayPolygon: currentCourseHole?.fairwayPolygon?.clCoordinates,
                bunkerPolygons: currentCourseHole?.bunkerPolygons.map(\.clCoordinates) ?? [],
                waterPolygons:  currentCourseHole?.waterPolygons.map(\.clCoordinates)  ?? [],
                trackedShots:   vm.currentHoleTrackedShots,
                onMapTap:       trackShotMode ? { coord in handleShotTap(coord) } : nil,
                focusId:        mapFocusId,
                recenterToken:  recenterToken,
                flightRequest:  flightRequest,
                onFlightCompleted: { landing in handleFlightCompleted(landing) }
            )
            .ignoresSafeArea()

            // Loading geometry indicator
            if vm.isLoading {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Loading course map…")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    Spacer()
                }
                .transition(.opacity)
                .zIndex(5)
            }

            // Top dark gradient
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.72), Color.black.opacity(0.36), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 150)
                .ignoresSafeArea(edges: .top)
                Spacer()
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 180)
            }
            .ignoresSafeArea()

            // ── Layout layers ──────────────────────────────────────────────
            VStack(spacing: 0) {

                // Top bar
                topBar
                    .padding(.top, topSafeArea + 4)

                // Hole info strip
                holeInfoStrip
                    .padding(.top, 6)
                    .padding(.horizontal, 16)

                Spacer()
            }
            .ignoresSafeArea(edges: .bottom)

            // Left sidebar
            leftSidebar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.top, topSafeArea + 84)
                .padding(.bottom, 170)
                .ignoresSafeArea(edges: .bottom)

            // Right sidebar
            rightSidebar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
                .padding(.top, topSafeArea + 132)
                .padding(.bottom, 210)
                .ignoresSafeArea(edges: .bottom)

            // Track-shot mode banner
            placeModeBanner

            // OSM attribution — bottom-left, translucent, compliant.
            VStack {
                Spacer()
                HStack {
                    OSMAttributionBadge()
                        .padding(.leading, 10)
                        .padding(.bottom, 96)   // above the bottom bar
                        // Long-press attribution badge to toggle the dev overlay.
                        #if DEBUG
                        .onLongPressGesture(minimumDuration: 0.6) {
                            showDiagnostics.toggle()
                        }
                        #endif
                    Spacer()
                }
            }
            .allowsHitTesting(true)
            .ignoresSafeArea(edges: .bottom)

            #if DEBUG
            if showDiagnostics {
                VStack {
                    HStack {
                        Spacer()
                        DiagnosticsOverlay(hole: currentCourseHole,
                                            courseSource: vm.selectedCourse?.source)
                            .padding(.top, topSafeArea + 60)
                            .padding(.trailing, 60)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            #endif
        }
        // Bottom bar
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarHidden(true)
        // Alerts
        .alert("Finish Round?", isPresented: $showFinishAlert) {
            Button("Finish & Save", role: .destructive) {
                Task { await vm.finishRound(); dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your round will be saved.")
        }
        .alert("Course Tool", isPresented: Binding(
            get:  { infoMessage != nil },
            set:  { if !$0 { infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoMessage ?? "")
        }
        // Sheets
        .fullScreenCover(isPresented: $showCamera) {
            RangeCameraScreen(
                shotCount: vm.activeRound?.shotIds.count ?? 0,
                context:   buildContext(),
                onShotSaved: { shot in
                    Task {
                        await vm.addShot(shot)
                        await MainActor.run {
                            beginHudFlight(for: shot)
                        }
                    }
                }
            )
            .ignoresSafeArea()
            .statusBarHidden(true)
        }
        .sheet(isPresented: $showScoreEntry) {
            if let hole = vm.currentHole {
                ScoreEntryView(
                    holeNumber:     hole.holeNumber,
                    par:            hole.par,
                    existingScore:  hole.score,
                    existingPutts:  hole.putts,
                    holeYardage:    scorecardYardage,
                    handicap:       currentCourseHole?.handicap
                ) { s, p, f, g in
                    let idx = vm.currentHoleIndex
                    Task { await vm.setScore(holeIndex: idx, score: s, putts: p, fairwayHit: f, gir: g) }
                }
                .preferredColorScheme(.dark)
            }
        }
        .sheet(isPresented: $showScorecard) {
            if let round = vm.activeRound {
                NavigationStack {
                    ScorecardView(round: round, course: vm.selectedCourse)
                }
                .preferredColorScheme(.dark)
            }
        }
        .sheet(item: Binding(
            get: { pendingShotEnd.map { CoordinateBox(coord: $0) } },
            set: { if $0 == nil { pendingShotEnd = nil } }
        )) { box in
            if let start = startCoordForNewShot() {
                ShotEntryConfirmSheet(
                    startCoord: start,
                    endCoord:   Coordinate(box.coord),
                    preselectedLie: pendingShotLie,
                    preselectedClub: inferredShotClub(from: pendingLaunchMonitorShot),
                    onSave: { club, lie, result in
                        Task {
                            _ = await vm.appendTrackedShot(
                                start: start,
                                end:   Coordinate(box.coord),
                                club:  club,
                                lie:   lie,
                                result: result,
                                linkedSavedShotId: pendingLaunchMonitorShot?.id
                            )
                            pendingShotEnd = nil
                            pendingLaunchMonitorShot = nil
                            setTrackShotMode(false)
                        }
                    },
                    onCancel: {
                        pendingShotEnd = nil
                        pendingLaunchMonitorShot = nil
                        setTrackShotMode(false)
                    }
                )
                .preferredColorScheme(.dark)
            }
        }
        .task {
            if let round = initialRound {
                await vm.resumeRound(round)
            } else if let course = initialCourse, let tee = initialTeeBox {
                await vm.startRoundEnriching(course: course, teeBox: tee)
            }
        }
        .onChange(of: vm.currentHoleIndex) { _ in
            recenterToken += 1
            setTrackShotMode(false)
        }
        .onChange(of: gpsOn) { _ in
            recenterToken += 1
        }
        .onChange(of: showCamera) { showing in
            // Camera cover dismissed — now play the deferred HUD flight on the visible map.
            guard !showing, let pending = pendingFlight else { return }
            pendingFlight = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                flightRequest = pending
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Button { showFinishAlert = true } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 44, height: 44)
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black.opacity(0.82))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 12) {
                Button {
                    if vm.currentHoleIndex > 0 { vm.goToHole(vm.currentHoleIndex - 1) }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 28, height: 28)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white.opacity(0.92))
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.72, green: 0.90, blue: 0.22))

                    if let hole = vm.currentHole {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(hole.holeNumber)")
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text(ordinalSuffix(hole.holeNumber).uppercased())
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundColor(.white.opacity(0.90))
                                .baselineOffset(8)
                        }
                    } else {
                        Text("—")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .frame(minWidth: 84)

                Button {
                    if let round = vm.activeRound, vm.currentHoleIndex < round.holes.count - 1 {
                        vm.advanceHole()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 28, height: 28)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white.opacity(0.92))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.66))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )

            Spacer()

            Button { recenterToken += 1 } label: {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.72))
                        .frame(width: 44, height: 44)
                    Image(systemName: "scope")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Hole Info Strip

    private var holeInfoStrip: some View {
        Group {
            if let hole = vm.currentHole {
                HStack(spacing: 12) {
                    Text("Par \(hole.par)")
                    Rectangle()
                        .fill(Color.white.opacity(0.88))
                        .frame(width: 8, height: 8)
                    Text(scorecardYardage.map { "\($0) yds" } ?? "— yds")
                    Circle()
                        .strokeBorder(Color.white.opacity(0.92), lineWidth: 1.2)
                        .frame(width: 8, height: 8)
                    Text("Hcp \(holeHandicap)")
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.94))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Left Sidebar

    private var leftSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)

            if gpsOn && gpsDistances.isAvailable {
                sideCard {
                    VStack(alignment: .leading, spacing: 6) {
                        if let f = gpsDistances.front {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(red: 0.67, green: 0.92, blue: 0.25))
                                Text("\(f)")
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                        }
                        if let c = gpsDistances.center {
                            Text("\(c)")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        if let b = gpsDistances.back {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.70))
                                Text("\(b)")
                                    .font(.system(size: 19, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.92))
                            }
                        }
                    }
                    .frame(minWidth: 84, alignment: .leading)
                }
            }
        }
    }

    /// Dark pill card wrapper used in the left sidebar
    @ViewBuilder
    private func sideCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
    }

    // MARK: - Right Sidebar

    private var rightSidebar: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 18) {
                railButton("location.fill", isActive: gpsOn) { gpsOn.toggle() }
                railButton(trackShotMode ? "scope" : "figure.golf", isActive: trackShotMode) {
                    setTrackShotMode(!trackShotMode)
                }
                railButton("camera.fill", isActive: false) { showCamera = true }
                railButton("list.number", isActive: false) { showScorecard = true }
                railButton("plus", isActive: false) { showScoreEntry = true }
            }
            .padding(.vertical, 18)
            .frame(width: 58)
            .background(Color.black.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
            Spacer(minLength: 0)
        }
    }

    private func toolButton(_ icon: String, _ label: String, action: (() -> Void)? = nil) -> some View {
        Button {
            if let a = action { a() }
            else { infoMessage = "\(label) is ready for the course overlay once GPS target data is available." }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.80))
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white.opacity(0.50))
            }
            .frame(width: 44, height: 44)
            .background(Color.black.opacity(0.55))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func railButton(_ icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if isActive {
                    Circle()
                        .fill(Color(red: 0.11, green: 0.48, blue: 0.20))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle()
                                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                        )
                }

                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isActive ? .white : .white.opacity(0.86))
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.31, green: 0.17, blue: 0.21))
                        .frame(width: 44, height: 44)
                    Circle()
                        .strokeBorder(.white.opacity(0.75), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                    Text(userInitials)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(userName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    HStack(spacing: 6) {
                        Text(scoreToParString)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(scoreToParColor)
                        Text("Hole \(vm.currentHoleIndex + 1)")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.70))
                    }
                }
            }

            Spacer()

            Button { setTrackShotMode(!trackShotMode) } label: {
                HStack(spacing: 6) {
                    Image(systemName: trackShotMode ? "scope" : "target")
                        .font(.system(size: 14, weight: .semibold))
                    Text(trackShotMode ? "Tap Map" : "Track")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(trackShotMode ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(trackShotMode ? TCTheme.gold : Color.black.opacity(0.60))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button { showCamera = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("HUD")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.60))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button { showScoreEntry = true } label: {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Add")
                    Text("Score")
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Place-mode banner

    @ViewBuilder
    private var placeModeBanner: some View {
        if trackShotMode {
            VStack {
                HStack(spacing: 8) {
                    Image(systemName: "scope")
                        .foregroundColor(.black)
                    Text(pendingLaunchMonitorShot == nil
                         ? "Tap the map to place where the ball landed"
                         : "Tap the map to place the launch-monitor shot on the hole")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                    Spacer()
                    Button("Cancel") { setTrackShotMode(false) }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black.opacity(0.65))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(TCTheme.gold)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, topSafeArea + 76)
                Spacer()
            }
            .allowsHitTesting(true)
        }
    }

    // MARK: - Shot tap handler

    private func handleShotTap(_ coord: CLLocationCoordinate2D) {
        guard trackShotMode else { return }
        pendingShotEnd = coord
        pendingShotLie = vm.classifyLie(
            at: Coordinate(coord),
            hole: currentCourseHole
        )
    }

    /// Compute the start coordinate for a new shot:
    /// 1. If there is a previous tracked shot for this hole, start = its end.
    /// 2. Otherwise start = current GPS.
    /// 3. As a last resort, start = current hole's tee coordinate.
    private func startCoordForNewShot() -> Coordinate? {
        if let last = vm.currentHoleTrackedShots.last {
            return last.endCoordinate
        }
        if let user = vm.location.currentLocation {
            return Coordinate(user)
        }
        return currentCourseHole?.teeCoordinate
    }

    private func setTrackShotMode(_ enabled: Bool) {
        trackShotMode = enabled
        if !enabled {
            pendingLaunchMonitorShot = nil
        }
    }

    // MARK: - HUD flight (launch-monitor → on-course)

    /// After a HUD shot, project where the ball landed on THIS hole using the measured
    /// distance, aimed at the pin and offset by the shot's horizontal launch angle, then
    /// animate the ball flying there. Falls back to manual placement if there's no pin.
    private func beginHudFlight(for shot: SavedShot) {
        guard let start = startCoordForNewShot(),
              let pin = currentCourseHole?.greenCenterCoordinate else {
            // No geometry to project onto — let the user place it manually.
            pendingLaunchMonitorShot = shot
            setTrackShotMode(true)
            return
        }
        let distanceYds = shot.metrics.totalYards > 0 ? shot.metrics.totalYards
                        : shot.metrics.carryYards
        guard distanceYds > 0 else {
            pendingLaunchMonitorShot = shot
            setTrackShotMode(true)
            return
        }
        let bearingToPin = Self.bearing(from: start.clCoordinate, to: pin.clCoordinate)
        let signedHLA = shot.metrics.hlaDirection.lowercased() == "left"
            ? -shot.metrics.hlaDegrees : shot.metrics.hlaDegrees
        let landing = Self.project(from: start.clCoordinate,
                                   bearingDegrees: bearingToPin + signedHLA,
                                   distanceMeters: distanceYds / 1.09361)
        flightStart = start
        flightShot  = shot
        // Defer the actual animation until the camera cover dismisses (see .onChange below)
        // so it plays on the visible map, not underneath the full-screen camera.
        pendingFlight = FlightRequest(id: UUID(), start: start.clCoordinate, end: landing)
    }

    private func handleFlightCompleted(_ landing: CLLocationCoordinate2D) {
        guard let start = flightStart, let shot = flightShot else { return }
        let lie = vm.classifyLie(at: Coordinate(landing), hole: currentCourseHole)
        Task {
            _ = await vm.appendTrackedShot(
                start: start,
                end:   Coordinate(landing),
                club:  inferredShotClub(from: shot),
                lie:   lie,
                result: .inPlay,
                linkedSavedShotId: shot.id
            )
            await MainActor.run {
                flightShot = nil
                flightStart = nil
                flightRequest = nil
            }
        }
    }

    /// Initial bearing (degrees, 0 = north) from one coordinate to another.
    private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi).truncatingRemainder(dividingBy: 360)
    }

    /// Destination coordinate given a start, bearing (deg), and distance (m). Great-circle.
    private static func project(from origin: CLLocationCoordinate2D,
                                bearingDegrees: Double,
                                distanceMeters: Double) -> CLLocationCoordinate2D {
        let R = 6_371_000.0
        let d = distanceMeters / R
        let brng = bearingDegrees * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brng))
        let lon2 = lon1 + atan2(sin(brng) * sin(d) * cos(lat1),
                                cos(d) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    // MARK: - Helpers

    private func buildContext() -> ShotContext {
        ShotContext(
            sourceMode:    .course,
            courseRoundId: vm.activeRound?.id,
            holeNumber:    vm.currentHole?.holeNumber,
            holePar:       vm.currentHole?.par,
            holeYardage:   scorecardYardage,
            courseName:    vm.activeRound?.courseName,
            holeHandicap:  holeHandicap
        )
    }

    private func inferredShotClub(from shot: SavedShot?) -> ShotClub? {
        guard let name = shot?.clubName, !name.isEmpty else { return nil }
        let lower = name.lowercased()
        let category: ShotClub.ClubCategory
        if lower.contains("putter") {
            category = .putter
        } else if lower.contains("wedge") || lower.contains("pw") || lower.contains("gw") || lower.contains("sw") || lower.contains("lw") {
            category = .wedge
        } else if lower.contains("driver") {
            category = .driver
        } else if lower.contains("wood") || lower.contains("3w") || lower.contains("5w") {
            category = .wood
        } else if lower.contains("hybrid") || lower.contains("rescue") {
            category = .hybrid
        } else {
            category = .iron
        }
        return ShotClub(clubId: shot?.clubId, name: name, category: category)
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n {
        case 11, 12, 13: suffix = "th"
        default:
            switch n % 10 {
            case 1:  suffix = "st"
            case 2:  suffix = "nd"
            case 3:  suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    private func ordinalSuffix(_ n: Int) -> String {
        String(ordinal(n).drop { $0.isNumber })
    }
}
