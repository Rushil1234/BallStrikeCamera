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

private final class GreenDistanceStackAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let front: Int?
    let center: Int?
    let back: Int?

    init(coordinate: CLLocationCoordinate2D, front: Int?, center: Int?, back: Int?) {
        self.coordinate = coordinate
        self.front = front
        self.center = center
        self.back = back
    }
}

private final class GreenDistanceStackAnnotationView: MKAnnotationView {
    private let card = UIStackView()
    private let frontLabel = UILabel()
    private let centerLabel = UILabel()
    private let backLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 86, height: 82)
        centerOffset = CGPoint(x: 0, y: -52)
        backgroundColor = .clear

        card.axis = .vertical
        card.alignment = .leading
        card.spacing = 2
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        card.frame = bounds
        card.backgroundColor = UIColor(white: 0.03, alpha: 0.74)
        card.layer.cornerRadius = 16
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        card.layer.borderWidth = 1
        card.layer.masksToBounds = true
        addSubview(card)

        [frontLabel, centerLabel, backLabel].forEach {
            $0.textColor = .white
            $0.adjustsFontSizeToFitWidth = true
            $0.minimumScaleFactor = 0.75
            card.addArrangedSubview($0)
        }
        frontLabel.font = UIFont.systemFont(ofSize: 16, weight: .heavy)
        centerLabel.font = UIFont.systemFont(ofSize: 30, weight: .black)
        backLabel.font = UIFont.systemFont(ofSize: 16, weight: .heavy)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var annotation: MKAnnotation? {
        didSet {
            guard let a = annotation as? GreenDistanceStackAnnotation else { return }
            frontLabel.attributedText = row(symbol: "↑", value: a.front, tint: UIColor(red: 0.70, green: 0.95, blue: 0.24, alpha: 1))
            centerLabel.text = a.center.map(String.init) ?? "—"
            backLabel.attributedText = row(symbol: "↓", value: a.back, tint: UIColor.white.withAlphaComponent(0.68))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.frame = bounds
    }

    private func row(symbol: String, value: Int?, tint: UIColor) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: "\(symbol) ",
            attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .heavy),
                .foregroundColor: tint
            ]
        )
        text.append(NSAttributedString(
            string: value.map(String.init) ?? "—",
            attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.94)
            ]
        ))
        return text
    }
}

// MARK: - Flag / Pin Annotation

private class GreenPinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
    var title: String? { nil }
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

/// Preferred hole strategy/path line. Usually comes from OSM `golf=hole`; otherwise inferred.
private final class HolePathPolyline: MKPolyline {}
private final class HolePathCasingPolyline: MKPolyline {}

/// One strategic segment of the aim-path (tee→aim1, aim1→aim2, aim2→green).
private final class AimSegmentPolyline: MKPolyline {}
private final class AimSegmentCasingPolyline: MKPolyline {}

// MARK: - Aim Point (draggable circle on the map)

private final class AimPointAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let index: Int

    init(coordinate: CLLocationCoordinate2D, index: Int) {
        self.coordinate = coordinate
        self.index = index
    }
}

private final class AimPointAnnotationView: MKAnnotationView {
    private let ring = UIView()
    private let dot  = UIView()
    /// Called every animation frame while the user drags this aim point.
    var onCenterChanged: ((CGPoint) -> Void)?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        centerOffset = .zero
        backgroundColor = .clear
        isDraggable = true

        ring.frame = bounds
        ring.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        ring.layer.cornerRadius = 22
        ring.layer.borderColor = UIColor.white.withAlphaComponent(0.92).cgColor
        ring.layer.borderWidth = 2.5
        ring.layer.shadowColor  = UIColor.black.cgColor
        ring.layer.shadowRadius = 5
        ring.layer.shadowOpacity = 0.55
        ring.layer.shadowOffset = .zero
        addSubview(ring)

        dot.frame = CGRect(x: 19, y: 19, width: 6, height: 6)
        dot.backgroundColor = .white
        dot.layer.cornerRadius = 3
        addSubview(dot)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MapKit updates `center` each frame during drag but only sets `coordinate`
    // at drag-end, so observe center instead for real-time line rebuilds.
    override var center: CGPoint {
        didSet {
            if dragState == .dragging { onCenterChanged?(center) }
        }
    }
}

// MARK: - Tee Marker (navy dot at tee coordinate)

private final class TeeAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

private final class TeeAnnotationView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 14, height: 14)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        let dot = UIView(frame: bounds)
        dot.backgroundColor = UIColor(red: 0.08, green: 0.18, blue: 0.42, alpha: 1.0) // navy
        dot.layer.cornerRadius = 7
        dot.layer.borderColor = UIColor.white.withAlphaComponent(0.88).cgColor
        dot.layer.borderWidth  = 1.5
        dot.layer.shadowColor  = UIColor.black.cgColor
        dot.layer.shadowRadius = 3
        dot.layer.shadowOpacity = 0.45
        dot.layer.shadowOffset  = .zero
        addSubview(dot)
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Segment Distance Label (floats over the midpoint of each aim segment)

private final class SegmentLabelAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let yardage: Int
    init(coordinate: CLLocationCoordinate2D, yardage: Int) {
        self.coordinate = coordinate
        self.yardage    = yardage
    }
}

private final class SegmentLabelAnnotationView: MKAnnotationView {
    private let pill  = UIView()
    private let label = UILabel()
    private static let labelFont = UIFont.systemFont(ofSize: 14, weight: .bold)

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 48, height: 26)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        pill.backgroundColor = UIColor(white: 0.04, alpha: 0.82)
        pill.layer.cornerRadius = 13
        pill.layer.borderColor  = UIColor.white.withAlphaComponent(0.22).cgColor
        pill.layer.borderWidth  = 0.5
        pill.frame = bounds
        addSubview(pill)

        label.textColor     = .white
        label.textAlignment = .center
        label.font = Self.labelFont
        label.frame = pill.bounds
        pill.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var annotation: MKAnnotation? {
        didSet {
            guard let a = annotation as? SegmentLabelAnnotation else { return }
            label.text = "\(a.yardage)"
            let tw = (label.text! as NSString).size(withAttributes: [
                .font: Self.labelFont
            ]).width + 18
            let w = max(38, tw)
            frame = CGRect(x: 0, y: 0, width: w, height: 26)
            pill.frame = bounds
            label.frame = bounds
        }
    }
}

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

private final class AimTargetAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

private final class AimTargetAnnotationView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        backgroundColor = .clear
        let ring = UIView(frame: bounds)
        ring.backgroundColor    = UIColor.white.withAlphaComponent(0.15)
        ring.layer.cornerRadius = 14
        ring.layer.borderColor  = UIColor.white.withAlphaComponent(0.85).cgColor
        ring.layer.borderWidth  = 2
        ring.layer.shadowColor  = UIColor.black.cgColor
        ring.layer.shadowRadius = 4
        ring.layer.shadowOpacity = 0.5
        ring.layer.shadowOffset = .zero
        addSubview(ring)
        let dot = UIView(frame: CGRect(x: 11, y: 11, width: 6, height: 6))
        dot.backgroundColor    = .white
        dot.layer.cornerRadius = 3
        ring.addSubview(dot)
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
    var pathCoordinates: [CLLocationCoordinate2D] = []
    /// Strategic aim-point coordinates. Empty = no aim overlay (par 3, short holes).
    var aimPoints: [CLLocationCoordinate2D] = []
    /// Called when the user finishes dragging an aim point. (index, newCoord)
    var onAimPointMoved: ((Int, CLLocationCoordinate2D) -> Void)? = nil
    /// Called when the user manually pans the map.
    var onUserPanned: (() -> Void)? = nil

    // Tracked shot polylines + markers (current hole only)
    var trackedShots:    [TrackedShot] = []

    // UI inset hints so the camera frames the hole within the usable (non-overlapped) area.
    var topUIInset:    CGFloat = 100   // pts: safe area + top pills height
    var bottomUIInset: CGFloat = 100   // pts: bottom bar + home indicator height
    var gpsKey:        String = ""
    // Custom aim target placed by a tap within 225 yards of the green.
    var customAimTarget: CLLocationCoordinate2D? = nil
    // Per-polygon hazard hit counts: "bunker_0", "water_1" → 0…3.
    var hazardCounts: [String: Int] = [:]
    var onHazardCountChanged: ((String, Int) -> Void)? = nil

    // Non-hazard taps on the map are forwarded here.
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

    static func metersBetween(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        MKMapPoint(a).distance(to: MKMapPoint(b))
    }

    private func preferredHolePath(start: CLLocationCoordinate2D, green: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        guard pathCoordinates.count >= 2 else { return [start, green] }
        var snapped = pathCoordinates.filter { coord in
            Self.metersBetween(coord, start) > 3 && Self.metersBetween(coord, green) > 3
        }
        snapped.insert(start, at: 0)
        snapped.append(green)
        return snapped
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
        // Limit zoom: min 50m (green detail) → max 2500m (~6× a long par-5).
        map.cameraZoomRange = MKMapView.CameraZoomRange(
            minCenterCoordinateDistance: 50,
            maxCenterCoordinateDistance: 2500
        )
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                          action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        // Crop ~12% from each side horizontally and stretch to fill, making the fairway
        // appear wider without changing the vertical zoom level.
        map.transform = CGAffineTransform(scaleX: Self.kHorizStretch, y: 1.0)
        return map
    }

    /// Horizontal stretch applied to the map view. Annotation views apply the
    /// inverse so labels/circles render at their natural (non-squished) size.
    static let kHorizStretch: CGFloat = 1.30

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self

        // The drawn content (polygons, tee line, flag, aim, shots) depends only on the HOLE — not
        // the live GPS dot, which SwiftUI re-renders many times a second. Skip the expensive
        // overlay teardown/rebuild when nothing visual changed; this is the key to a smooth map.
        let g = greenCoord.map { "\($0.latitude),\($0.longitude)" } ?? "-"
        let t = teeCoord.map { "\($0.latitude),\($0.longitude)" } ?? "-"
        let aimKey = aimPoints.map { "\(Int($0.latitude * 10000)),\(Int($0.longitude * 10000))" }.joined(separator: "|")
        let aimTgtKey = customAimTarget.map { "\(Int($0.latitude * 10000)),\(Int($0.longitude * 10000))" } ?? ""
        let renderKey = "\(focusId)|\(g)|\(t)|\(trackedShots.count)|\(aimKey)|\(recenterToken)|\(gpsKey)|\(aimTgtKey)"
        let flightPending = flightRequest != nil && flightRequest!.id != context.coordinator.lastFlightId
        if renderKey == context.coordinator.lastRenderKey && !flightPending {
            return
        }
        context.coordinator.lastRenderKey = renderKey

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
                                                                recenterToken: recenterToken,
                                                                gpsKey: gpsKey)

        // Compute the UI-aware camera framing constants.
        // We need flag visible below the top bar and tee/GPS visible above the bottom bar.
        let screenH = Double(UIScreen.main.bounds.height)
        let topF    = Double(topUIInset)    / max(screenH, 1)
        let botF    = Double(bottomUIInset) / max(screenH, 1)
        let usableF = max(0.40, 1.0 - topF - botF)   // fraction of screen that's un-occluded
        // t-value along path [tee→green] that appears at screen center (pos=0.5).
        // Derivation: pos(t) = topF + (1-t)·usableF → set pos=0.5 → t = (0.5-botF)/usableF
        let centerT = (0.5 - botF) / max(usableF, 0.01)

        // Always start the aim line from the user's GPS when available; fall back to tee.
        let lineStart: CLLocationCoordinate2D? = userCoord ?? teeCoord
        // Custom aim target overrides the pin as the effective aim endpoint.
        let effectiveGreen: CLLocationCoordinate2D? = customAimTarget ?? greenCoord

        var holePathForOverlay: [CLLocationCoordinate2D] = []
        if let green = effectiveGreen, let start = lineStart, !coordsEqual(start, green) {
            holePathForOverlay = preferredHolePath(start: start, green: green)
            if shouldRecenter {
                let routeStart = holePathForOverlay.first ?? start
                let routeEnd   = holePathForOverlay.last  ?? green
                let heading    = Self.bearing(from: routeStart, to: routeEnd)

                let kPad     = 20.0
                let h_rad    = heading * .pi / 180.0
                let cosLat   = cos(start.latitude * .pi / 180.0)
                let kMPerDeg = 111_320.0
                var minX = Double.infinity, maxX = -Double.infinity
                var minY = Double.infinity, maxY = -Double.infinity
                for coord in holePathForOverlay {
                    let dn = (coord.latitude  - start.latitude)  * kMPerDeg
                    let de = (coord.longitude - start.longitude) * kMPerDeg * cosLat
                    let sy =  dn * cos(h_rad) + de * sin(h_rad)
                    let sx = -dn * sin(h_rad) + de * cos(h_rad)
                    minX = min(minX, sx); maxX = max(maxX, sx)
                    minY = min(minY, sy); maxY = max(maxY, sy)
                }
                let vertExtent  = (maxY - minY) + 2 * kPad
                let horizExtent = max((maxX - minX) + 2 * kPad, kPad * 2)
                let midX        = (minX + maxX) / 2.0

                let centerOnPath = Self.interpolate(routeStart, routeEnd, t: centerT)
                let cosLatC = cos(centerOnPath.latitude * .pi / 180.0)
                let biasedCenter = CLLocationCoordinate2D(
                    latitude:  centerOnPath.latitude  - midX * sin(h_rad) / kMPerDeg,
                    longitude: centerOnPath.longitude + midX * cos(h_rad) / (kMPerDeg * max(cosLatC, 1e-6))
                )

                // Build a virtual MKMapRect whose N-S dimension = vertExtent (along-hole) and
                // E-W dimension = horizExtent (across-hole). setVisibleMapRect with the UI
                // edge insets then gives MapKit's own altitude — no assumed ratio needed.
                // Two setProgrammaticRegionChange calls are needed because setVisibleMapRect
                // (animated:false) fires regionDidChangeAnimated synchronously, consuming the flag.
                let ptsPerMeter = MKMapPointsPerMeterAtLatitude(biasedCenter.latitude)
                let centerPt    = MKMapPoint(biasedCenter)
                let fittingRect = MKMapRect(
                    x: centerPt.x - (horizExtent / 2) * ptsPerMeter,
                    y: centerPt.y - (vertExtent  / 2) * ptsPerMeter,
                    width:  horizExtent * ptsPerMeter,
                    height: vertExtent  * ptsPerMeter
                )
                let edgePad = UIEdgeInsets(top: topUIInset, left: 8,
                                           bottom: bottomUIInset, right: 8)
                context.coordinator.setProgrammaticRegionChange(true)
                map.setVisibleMapRect(fittingRect, edgePadding: edgePad, animated: false)
                let fittedAlt = max(map.camera.altitude * 0.90, 150.0)

                let cam = MKMapCamera(lookingAtCenter: biasedCenter,
                                      fromDistance: fittedAlt,
                                      pitch: 0,
                                      heading: heading)
                context.coordinator.setProgrammaticRegionChange(true)
                map.setCamera(cam, animated: context.coordinator.hasInitializedRegion)
                context.coordinator.completeRecenter(focusId: focusId, recenterToken: recenterToken, gpsKey: gpsKey)
            }
        } else if let green = greenCoord {
            if shouldRecenter {
                let kPad = 20.0
                let ptsPerMeter = MKMapPointsPerMeterAtLatitude(green.latitude)
                let greenPt = MKMapPoint(green)
                let padPts = kPad * ptsPerMeter
                let rect = MKMapRect(x: greenPt.x - padPts, y: greenPt.y - padPts,
                                     width: padPts * 2, height: padPts * 2)
                let edgePad = UIEdgeInsets(top: topUIInset, left: 8, bottom: bottomUIInset, right: 8)
                context.coordinator.setProgrammaticRegionChange(true)
                map.setVisibleMapRect(rect, edgePadding: edgePad, animated: false)
                let alt = max(map.camera.altitude, 50.0)
                let cam = MKMapCamera(lookingAtCenter: green, fromDistance: alt, pitch: 0, heading: 0)
                context.coordinator.setProgrammaticRegionChange(true)
                map.setCamera(cam, animated: context.coordinator.hasInitializedRegion)
                context.coordinator.completeRecenter(focusId: focusId, recenterToken: recenterToken, gpsKey: gpsKey)
            }
        } else {
            let center = courseCoord ?? CLLocationCoordinate2D(latitude: 37.785834, longitude: -122.406417)
            if shouldRecenter {
                context.coordinator.setProgrammaticRegionChange(true)
                map.setRegion(
                    MKCoordinateRegion(center: center,
                                       latitudinalMeters: 650 / usableF,
                                       longitudinalMeters: 650 / usableF),
                    animated: context.coordinator.hasInitializedRegion
                )
                context.coordinator.completeRecenter(focusId: focusId, recenterToken: recenterToken, gpsKey: gpsKey)
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
        // Polygon overlays (green, fairway, bunker, water) are intentionally not rendered —
        // the satellite imagery already shows these features clearly. Tap detection still
        // works because handleTap uses the raw coordinate arrays, not MKOverlay objects.

        // Custom aim target circle
        if let at = customAimTarget {
            map.addAnnotation(AimTargetAnnotation(coordinate: at))
        }

        // Aim segments (when aim points are active) replace the single HolePathPolyline.
        // For par 3 / straight short holes, aimPoints is empty and we fall back to path line.
        if !aimPoints.isEmpty, let lineStart = userCoord ?? teeCoord, let green = effectiveGreen {
            // Draw segments: lineStart → aim[0] → aim[1] → … → effective green
            let waypoints = [lineStart] + aimPoints + [green]
            // Store in coordinator so drag handler can rebuild lines in real-time.
            context.coordinator.currentAimWaypoints = waypoints
            for i in 0..<waypoints.count - 1 {
                var pts = [waypoints[i], waypoints[i + 1]]
                map.addOverlay(AimSegmentCasingPolyline(coordinates: &pts, count: 2), level: .aboveLabels)
                map.addOverlay(AimSegmentPolyline(coordinates: &pts, count: 2), level: .aboveLabels)
                // Distance label at segment midpoint
                let mid = Self.midpoint(waypoints[i], waypoints[i + 1])
                let yards = Int((MKMapPoint(waypoints[i]).distance(to: MKMapPoint(waypoints[i + 1])) * 1.09361).rounded())
                map.addAnnotation(SegmentLabelAnnotation(coordinate: mid, yardage: yards))
            }
            // Tee dot
            if let tee = teeCoord {
                map.addAnnotation(TeeAnnotation(coordinate: tee))
            }
            // Draggable aim-point rings
            for (i, ap) in aimPoints.enumerated() {
                map.addAnnotation(AimPointAnnotation(coordinate: ap, index: i))
            }
        } else if holePathForOverlay.count >= 2 {
            // Straight line (par 3 or no aim points)
            var pts = holePathForOverlay
            map.addOverlay(HolePathCasingPolyline(coordinates: &pts, count: pts.count), level: .aboveLabels)
            map.addOverlay(HolePathPolyline(coordinates: &pts, count: pts.count), level: .aboveLabels)
            if let tee = teeCoord {
                map.addAnnotation(TeeAnnotation(coordinate: tee))
            }
        }

        // Yellow flag at green center
        if let green = greenCoord {
            map.addAnnotation(GreenPinAnnotation(coordinate: green))
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
        var lastRenderKey = ""
        private var lastFocusId = ""
        private var lastRecenterToken = -1
        private var lastGpsKey = ""
        private var isProgrammaticRegionChange = false
        // Full waypoints [lineStart, aim[0], …, green] — kept in sync so the drag handler can
        // rebuild segment overlays in real-time without a SwiftUI round-trip.
        var currentAimWaypoints: [CLLocationCoordinate2D] = []

        // Flight animation state
        var lastFlightId: UUID?
        private var flightTimer: Timer?
        private weak var flightBall: FlightBallAnnotation?
        private weak var flightTrail: FlightTrailPolyline?

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let map = gr.view as? MKMapView else { return }
            let pt    = gr.location(in: map)
            let coord = map.convert(pt, toCoordinateFrom: map)

            // Hazard polygons take priority — cycle count 0→1→2→3→0.
            if let p = parent {
                for (i, ring) in p.bunkerPolygons.enumerated() where ring.count >= 3 {
                    if pointInPolygon(coord, polygon: ring) {
                        let key = "bunker_\(i)"
                        let next = ((p.hazardCounts[key] ?? 0) + 1) % 4
                        p.onHazardCountChanged?(key, next)
                        return
                    }
                }
                for (i, ring) in p.waterPolygons.enumerated() where ring.count >= 3 {
                    if pointInPolygon(coord, polygon: ring) {
                        let key = "water_\(i)"
                        let next = ((p.hazardCounts[key] ?? 0) + 1) % 4
                        p.onHazardCountChanged?(key, next)
                        return
                    }
                }
            }

            // Non-hazard tap — forward to parent handler (custom aim target, etc.)
            parent?.onMapTap?(coord)
        }

        private func pointInPolygon(_ point: CLLocationCoordinate2D,
                                     polygon: [CLLocationCoordinate2D]) -> Bool {
            var inside = false
            let n = polygon.count
            var j = n - 1
            for i in 0..<n {
                let xi = polygon[i].longitude, yi = polygon[i].latitude
                let xj = polygon[j].longitude, yj = polygon[j].latitude
                if ((yi > point.latitude) != (yj > point.latitude)) &&
                   (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi) {
                    inside = !inside
                }
                j = i
            }
            return inside
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

        func shouldRecenter(for focusId: String, recenterToken: Int, gpsKey: String) -> Bool {
            // Never reframe just because the user walked — only on hole change or manual recenter.
            !hasInitializedRegion || focusId != lastFocusId || recenterToken != lastRecenterToken
        }

        func completeRecenter(focusId: String, recenterToken: Int, gpsKey: String) {
            hasInitializedRegion = true
            lastFocusId = focusId
            lastRecenterToken = recenterToken
            lastGpsKey = gpsKey
        }

        func setProgrammaticRegionChange(_ value: Bool) {
            isProgrammaticRegionChange = value
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if isProgrammaticRegionChange {
                isProgrammaticRegionChange = false
            } else {
                // User manually panned — notify SwiftUI to show the recenter button.
                parent?.onUserPanned?()
            }
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState,
                     fromOldState oldState: MKAnnotationView.DragState) {
            guard let aim = view.annotation as? AimPointAnnotation else { return }

            switch newState {
            case .starting:
                // MapKit only updates annotation.coordinate at drag-end, not each frame.
                // Hook into the annotation view's `center` instead — it tracks the finger live.
                if let aimView = view as? AimPointAnnotationView {
                    let idx = aim.index
                    aimView.onCenterChanged = { [weak self, weak mapView] screenCenter in
                        guard let self, let map = mapView else { return }
                        let coord = map.convert(screenCenter, toCoordinateFrom: map)
                        self.rebuildAimSegments(on: map, movingIndex: idx, to: coord)
                    }
                }

            case .canceling, .none:
                (view as? AimPointAnnotationView)?.onCenterChanged = nil

            case .ending:
                (view as? AimPointAnnotationView)?.onCenterChanged = nil
                // Final position — update stored waypoints and notify SwiftUI.
                let wi = aim.index + 1
                if wi > 0, wi < currentAimWaypoints.count - 1 {
                    currentAimWaypoints[wi] = aim.coordinate
                }
                parent?.onAimPointMoved?(aim.index, aim.coordinate)

            default:
                break
            }
        }

        // Swaps only the aim-segment overlays/labels so lines follow the dragged point live.
        // Annotation views (aim rings, tee dot, flag) are untouched to avoid any flicker.
        private func rebuildAimSegments(on mapView: MKMapView,
                                        movingIndex: Int,
                                        to newCoord: CLLocationCoordinate2D) {
            var waypoints = currentAimWaypoints
            let wi = movingIndex + 1
            guard wi > 0, wi < waypoints.count - 1 else { return }
            waypoints[wi] = newCoord

            let oldOverlays = mapView.overlays.filter {
                $0 is AimSegmentPolyline || $0 is AimSegmentCasingPolyline
            }
            mapView.removeOverlays(oldOverlays)
            let oldLabels = mapView.annotations.filter { $0 is SegmentLabelAnnotation }
            mapView.removeAnnotations(oldLabels)

            for i in 0..<waypoints.count - 1 {
                var pts = [waypoints[i], waypoints[i + 1]]
                mapView.addOverlay(AimSegmentCasingPolyline(coordinates: &pts, count: 2), level: .aboveLabels)
                mapView.addOverlay(AimSegmentPolyline(coordinates: &pts, count: 2), level: .aboveLabels)
                let mid   = SatelliteMapBackground.midpoint(waypoints[i], waypoints[i + 1])
                let yards = Int((MKMapPoint(waypoints[i]).distance(to: MKMapPoint(waypoints[i + 1])) * 1.09361).rounded())
                mapView.addAnnotation(SegmentLabelAnnotation(coordinate: mid, yardage: yards))
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? TaggedPolygon {
                let r = MKPolygonRenderer(polygon: polygon)
                // Translucent fills so real satellite detail (turf, sand, water) stays visible —
                // a refined caddie overlay rather than a flat debug map.
                switch polygon.kind {
                case "green":
                    r.fillColor   = UIColor(red: 0.45, green: 0.85, blue: 0.50, alpha: 0.30)
                    r.strokeColor = UIColor(red: 0.20, green: 0.58, blue: 0.30, alpha: 0.85)
                    r.lineWidth   = 1.6
                case "fairway":
                    r.fillColor   = UIColor(red: 0.40, green: 0.70, blue: 0.38, alpha: 0.22)
                    r.strokeColor = UIColor(red: 0.22, green: 0.50, blue: 0.24, alpha: 0.45)
                    r.lineWidth   = 1.0
                case "bunker":
                    r.fillColor   = UIColor(red: 0.96, green: 0.88, blue: 0.66, alpha: 0.45)
                    r.strokeColor = UIColor(red: 0.82, green: 0.70, blue: 0.44, alpha: 0.75)
                    r.lineWidth   = 1.0
                case "water":
                    r.fillColor   = UIColor(red: 0.22, green: 0.54, blue: 0.88, alpha: 0.40)
                    r.strokeColor = UIColor(red: 0.12, green: 0.38, blue: 0.72, alpha: 0.70)
                    r.lineWidth   = 1.0
                default:
                    r.fillColor   = UIColor.systemGreen.withAlphaComponent(0.28)
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
            if overlay is AimSegmentCasingPolyline, let line = overlay as? MKPolyline {
                let r         = MKPolylineRenderer(polyline: line)
                r.strokeColor = UIColor.black.withAlphaComponent(0.28)
                r.lineWidth   = 6.0
                r.lineCap     = .round
                r.lineJoin    = .round
                return r
            }
            if overlay is AimSegmentPolyline, let line = overlay as? MKPolyline {
                let r         = MKPolylineRenderer(polyline: line)
                r.strokeColor = UIColor.white.withAlphaComponent(0.90)
                r.lineWidth   = 2.8
                r.lineCap     = .round
                r.lineJoin    = .round
                return r
            }
            if overlay is HolePathCasingPolyline, let line = overlay as? MKPolyline {
                let r             = MKPolylineRenderer(polyline: line)
                r.strokeColor     = UIColor.black.withAlphaComponent(0.32)
                r.lineWidth       = 5.0
                r.lineCap         = .round
                r.lineJoin        = .round
                return r
            }
            if overlay is HolePathPolyline, let line = overlay as? MKPolyline {
                let r             = MKPolylineRenderer(polyline: line)
                r.strokeColor     = UIColor.white.withAlphaComponent(0.92)
                r.lineWidth       = 2.4
                r.lineCap         = .round
                r.lineJoin        = .round
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

            let invStretch = CGAffineTransform(scaleX: 1.0 / SatelliteMapBackground.kHorizStretch, y: 1.0)

            if let bubble = annotation as? DistanceBubbleAnnotation {
                let id  = "distBubble"
                let v   = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                            as? DistanceBubbleAnnotationView
                            ?? DistanceBubbleAnnotationView(annotation: bubble, reuseIdentifier: id)
                v.annotation      = bubble
                v.displayPriority = .required
                v.transform       = invStretch
                v.setNeedsLayout()
                v.layoutIfNeeded()
                return v
            }

            if let stack = annotation as? GreenDistanceStackAnnotation {
                let id = "greenDistanceStack"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    as? GreenDistanceStackAnnotationView
                    ?? GreenDistanceStackAnnotationView(annotation: stack, reuseIdentifier: id)
                v.annotation  = stack
                v.displayPriority = .required
                v.transform   = invStretch
                return v
            }

            if let aim = annotation as? AimPointAnnotation {
                let id = "aimPoint"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    as? AimPointAnnotationView
                    ?? AimPointAnnotationView(annotation: aim, reuseIdentifier: id)
                v.annotation  = aim
                v.displayPriority = .required
                v.transform   = invStretch
                return v
            }

            if annotation is AimTargetAnnotation {
                let id = "aimTarget"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    as? AimTargetAnnotationView
                    ?? AimTargetAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation  = annotation
                v.displayPriority = .required
                v.transform   = invStretch
                return v
            }

            if annotation is TeeAnnotation {
                let id = "teeMarker"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    as? TeeAnnotationView
                    ?? TeeAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation  = annotation
                v.displayPriority = .required
                v.transform   = invStretch
                return v
            }

            if annotation is SegmentLabelAnnotation {
                let id = "segLabel"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    as? SegmentLabelAnnotationView
                    ?? SegmentLabelAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation  = annotation
                v.displayPriority = .required
                v.transform   = invStretch
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
    @State private var showRecenter    = false    // true after user pans away
    @State private var showLandingConfirm = false
    // Aim-point drag overrides: key = aim point index, value = dragged position
    @State private var userAimPointOverrides: [Int: CLLocationCoordinate2D] = [:]
    // Custom tap-to-aim target (within 225 yd of green)
    @State private var aimTarget: CLLocationCoordinate2D?
    // Hazard hit counts per polygon: "bunker_0", "water_1", etc. (0→1→2→3→0)
    @State private var hazardCounts: [String: Int] = [:]
    // HUD flight animation state
    @State private var flightRequest: FlightRequest?
    @State private var pendingFlight: FlightRequest?     // held until camera cover dismisses
    @State private var flightStart: Coordinate?
    @State private var flightShot: SavedShot?

    let initialCourse: GolfCourse?
    let initialTeeBox: TeeBox?
    let initialRound:  CourseRound?

    // MARK: Computed Properties

    private var currentCourseHole: GolfHole? {
        guard let hole = vm.currentHole,
              let course = vm.selectedCourse else { return nil }
        return course.holes.first { $0.number == hole.holeNumber }
    }

    private var currentMapHole: GolfHole? {
        guard vm.selectedCourse?.hasTrustedGeometry == true else { return nil }
        return currentCourseHole
    }

    private var scorecardYardage: Int? {
        guard let gh = currentCourseHole,
              let tee = vm.selectedTeeBox else { return nil }
        return gh.teeYardsByTeeBox[tee.id]
    }

    private var gpsDistances: GreenDistances {
        guard let gh = currentMapHole else { return GreenDistances() }
        return vm.location.greenDistances(
            front:  gh.greenFrontCoordinate?.clCoordinate,
            center: gh.greenCenterCoordinate?.clCoordinate,
            back:   gh.greenBackCoordinate?.clCoordinate
        )
    }

    private var userIsNearCurrentHole: Bool {
        guard let user = vm.location.currentLocation,
              let center = currentMapHole?.greenCenterCoordinate?.clCoordinate else { return false }
        return Self.metersBetween(user, center) < 2_400
    }

    private var estimatedTeeDistances: GreenDistances {
        guard let gh = currentMapHole ?? currentCourseHole else { return GreenDistances() }
        let tee = gh.teeCoordinate?.clCoordinate
        let measuredCenter = tee.flatMap { start in
            gh.greenCenterCoordinate.map { Int((Self.metersBetween(start, $0.clCoordinate) * 1.09361).rounded()) }
        }
        let center = scorecardYardage ?? measuredCenter
        let frontOffset = greenDepthOffsetYards(center: gh.greenCenterCoordinate,
                                                edge: gh.greenFrontCoordinate)
        let backOffset = greenDepthOffsetYards(center: gh.greenCenterCoordinate,
                                               edge: gh.greenBackCoordinate)
        let front = center.map { max($0 - frontOffset, 0) } ?? tee.flatMap { start in
            gh.greenFrontCoordinate.map { Int((Self.metersBetween(start, $0.clCoordinate) * 1.09361).rounded()) }
        }
        let back = center.map { $0 + backOffset } ?? tee.flatMap { start in
            gh.greenBackCoordinate.map { Int((Self.metersBetween(start, $0.clCoordinate) * 1.09361).rounded()) }
        }
        return GreenDistances(front: front, center: center, back: back)
    }

    private var mapDistances: GreenDistances {
        if gpsOn && userIsNearCurrentHole && gpsDistances.isAvailable {
            return gpsDistances
        }
        return estimatedTeeDistances
    }

    private var displayYardage: Int? {
        if gpsOn, userIsNearCurrentHole, let gps = gpsDistances.center { return gps }
        return scorecardYardage
    }

    private var currentHolePathCoordinates: [CLLocationCoordinate2D] {
        if let tee = currentMapHole?.teeCoordinate?.clCoordinate,
           let green = currentMapHole?.greenCenterCoordinate?.clCoordinate {
            if let coords = currentMapHole?.pathCoordinates, coords.count >= 2 {
                var path = coords.map(\.clCoordinate).filter { coord in
                    Self.metersBetween(coord, tee) > 3 && Self.metersBetween(coord, green) > 3
                }
                path.insert(tee, at: 0)
                path.append(green)
                return path
            }
            return [tee, green]
        }
        return []
    }

    /// Returns default aim-point coordinates along the hole path.
    /// Empty for par 3 and short/straight par 4s — those just show a direct line.
    private var suggestedAimPoints: [CLLocationCoordinate2D] {
        guard currentHolePathCoordinates.count >= 2,
              let hole = vm.currentHole else { return [] }
        // Par 3: always a straight line, no aim circle needed.
        guard hole.par >= 4 else { return [] }
        let totalMeters = Self.pathLengthMeters(currentHolePathCoordinates)
        guard totalMeters > 25 else { return [] }
        let totalYards = Double(scorecardYardage ?? Int((totalMeters * 1.09361).rounded()))
        // Short par 4 with no dogleg: skip aim point, just draw the line.
        if hole.par == 4 && totalYards < 320 && !Self.isSignificantDogleg(currentHolePathCoordinates) {
            return []
        }
        if hole.par >= 5 {
            // Two aim points for par 5: first carry (~255 yds), second layup (~halfway remaining).
            let t1 = min(255.0, max(200.0, totalYards * 0.40)) / 1.09361
            let t2 = t1 + min(250.0, max(150.0, (totalMeters - t1) * 0.55))
            return [
                Self.coordinate(onPath: currentHolePathCoordinates, atMeters: min(t1, totalMeters - 50)),
                Self.coordinate(onPath: currentHolePathCoordinates, atMeters: min(t2, totalMeters - 20))
            ]
        } else {
            // Par 4: one aim point.
            let t1 = min(255.0, max(185.0, totalYards - 120.0)) / 1.09361
            return [Self.coordinate(onPath: currentHolePathCoordinates, atMeters: min(t1, totalMeters - 20))]
        }
    }

    /// Merges default aim points with any user-dragged overrides.
    /// For par 5s: if aim point 0 is within 225 yards of the green, collapses to a
    /// single-segment line so the intermediate waypoint disappears automatically.
    private var activeAimPoints: [CLLocationCoordinate2D] {
        let pts = suggestedAimPoints.enumerated().map { i, def in
            userAimPointOverrides[i] ?? def
        }
        if pts.count >= 2,
           let green = currentMapHole?.greenCenterCoordinate?.clCoordinate {
            let yardsToGreen = Self.metersBetween(pts[0], green) * 1.09361
            if yardsToGreen <= 225 {
                return [pts[0]]
            }
        }
        return pts
    }

    /// True if the hole path bends more than 30 m from a straight tee-to-green line.
    private static func isSignificantDogleg(_ path: [CLLocationCoordinate2D]) -> Bool {
        guard path.count >= 3, let tee = path.first, let green = path.last else { return false }
        let teePt   = MKMapPoint(tee)
        let greenPt = MKMapPoint(green)
        let lineLen = teePt.distance(to: greenPt)
        guard lineLen > 1 else { return false }
        for coord in path.dropFirst().dropLast() {
            let p = MKMapPoint(coord)
            // Perpendicular distance from p to the tee-green line segment.
            let t = max(0, min(1, ((p.x - teePt.x) * (greenPt.x - teePt.x) +
                                    (p.y - teePt.y) * (greenPt.y - teePt.y)) / (lineLen * lineLen)))
            let projX = teePt.x + t * (greenPt.x - teePt.x)
            let projY = teePt.y + t * (greenPt.y - teePt.y)
            let perp = MKMapPoint(x: projX, y: projY).distance(to: p)
            if perp > 30 { return true }  // 30 m offset = dogleg
        }
        return false
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

    private var bottomSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 34
    }

    /// GPS rounded to ~40 m resolution. Changes here trigger a camera reframe (GPS→green zoom-in).
    private var coarseGpsKey: String {
        guard gpsOn, userIsNearCurrentHole,
              let loc = vm.location.currentLocation else { return "" }
        let lat = (loc.latitude  / 0.0004).rounded() * 0.0004
        let lon = (loc.longitude / 0.0004).rounded() * 0.0004
        return "\(lat),\(lon)"
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

    private var scoreToParWord: String {
        if scoreToPar == 0 { return "Even" }
        return scoreToPar > 0 ? "+\(scoreToPar)" : "\(scoreToPar)"
    }

    private var displayPlayerName: String {
        let n = userName.trimmingCharacters(in: .whitespaces)
        if n.isEmpty || n.caseInsensitiveCompare("Guest") == .orderedSame || n.caseInsensitiveCompare("Player") == .orderedSame {
            return "Guest Player"
        }
        return n
    }

    private var scoreToParColor: Color {
        scoreToPar < 0 ? Color(red: 0.22, green: 0.78, blue: 0.42)
            : scoreToPar == 0 ? Color(red: 0.42, green: 0.72, blue: 0.98)
            : TCTheme.textMuted
    }

    private func pushWidgetData() {
        guard let round = vm.activeRound, let hole = vm.currentHole else {
            WidgetBridge.clear()
            WatchConnectivityBridge.shared.clearRound()
            if #available(iOS 16.2, *) { ActivityBridge.end() }
            return
        }
        let d = mapDistances
        let front  = d.front  ?? d.center.map { max($0 - 10, 0) } ?? 0
        let center = d.center ?? 0
        let back   = d.back   ?? d.center.map { $0 + 10 } ?? 0
        WidgetBridge.write(RoundWidgetData(
            holeNumber: hole.holeNumber, scoreToPar: scoreToPar,
            totalScore: round.scoreSummary.totalScore,
            frontYards: front, centerYards: center, backYards: back,
            courseName: round.courseName, hasActiveRound: true
        ))
        WatchConnectivityBridge.shared.publishRound(WatchCompanionRoundSnapshot(
            courseName: round.courseName,
            holeNumber: hole.holeNumber,
            holeCount: round.holes.count,
            par: hole.par,
            score: hole.score,
            scoreToPar: scoreToPar,
            totalScore: round.scoreSummary.totalScore,
            frontYards: front,
            centerYards: center,
            backYards: back,
            canGoPrevious: vm.currentHoleIndex > 0,
            canGoNext: vm.currentHoleIndex < round.holes.count - 1
        ))
        if #available(iOS 16.2, *) {
            ActivityBridge.updateOrStart(
                courseId: round.courseId,
                state: RoundActivityAttributes.ContentState(
                    holeNumber: hole.holeNumber, scoreToPar: scoreToPar,
                    totalScore: round.scoreSummary.totalScore,
                    frontYards: front, centerYards: center, backYards: back,
                    courseName: round.courseName
                )
            )
        }
    }

    private func registerWatchRoundControls() {
        WatchConnectivityBridge.shared.registerRoundCommandHandler { command in
            await handleWatchRoundCommand(command)
        }
        pushWidgetData()
    }

    private func handleWatchRoundCommand(_ command: WatchCommand) async -> WatchCommandResult {
        switch command.kind {
        case .refresh:
            pushWidgetData()
            return .success()
        case .roundNextHole:
            guard let round = vm.activeRound else {
                return .failure("No active round on iPhone.")
            }
            guard vm.currentHoleIndex < round.holes.count - 1 else {
                return .success("Already on the last hole.")
            }
            vm.advanceHole()
            pushWidgetData()
            return .success()
        case .roundPreviousHole:
            guard vm.activeRound != nil else {
                return .failure("No active round on iPhone.")
            }
            guard vm.currentHoleIndex > 0 else {
                return .success("Already on the first hole.")
            }
            vm.goToHole(vm.currentHoleIndex - 1)
            pushWidgetData()
            return .success()
        case .roundSetScore:
            guard let round = vm.activeRound else {
                return .failure("No active round on iPhone.")
            }
            guard let holeNumber = command.holeNumber,
                  let score = command.score,
                  (1...12).contains(score) else {
                return .failure("Choose a score from 1 to 12.")
            }
            guard let index = round.holes.firstIndex(where: { $0.holeNumber == holeNumber }) else {
                return .failure("That hole is not in the active round.")
            }
            await vm.setScore(holeIndex: index, score: score)
            if index != vm.currentHoleIndex {
                vm.goToHole(index)
            }
            pushWidgetData()
            return .success()
        case .rangeStart, .rangeEnd, .rangeRefresh:
            return .failure("That command is for Range mode.")
        }
    }

    private var mapFocusId: String {
        let hole = vm.currentHole?.holeNumber ?? -1
        let greenLat = currentMapHole?.greenCenterCoordinate?.latitude ?? 0
        let greenLon = currentMapHole?.greenCenterCoordinate?.longitude ?? 0
        // Include the tee so the camera re-frames "down the hole" the moment geometry loads.
        let teeLat = currentMapHole?.teeCoordinate?.latitude ?? 0
        let teeLon = currentMapHole?.teeCoordinate?.longitude ?? 0
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
                greenCoord:  currentMapHole?.greenCenterCoordinate?.clCoordinate,
                teeCoord:    currentMapHole?.teeCoordinate?.clCoordinate,
                userCoord:   (gpsOn && userIsNearCurrentHole) ? vm.location.currentLocation : nil,
                courseCoord: vm.selectedCourse?.coordinate ?? initialCourse?.coordinate,
                frontCoord:  currentMapHole?.greenFrontCoordinate?.clCoordinate,
                backCoord:   currentMapHole?.greenBackCoordinate?.clCoordinate,
                frontDist:   mapDistances.front,
                centerDist:  mapDistances.center,
                backDist:    mapDistances.back,
                greenPolygon:   currentMapHole?.greenPolygon?.clCoordinates,
                fairwayPolygon: currentMapHole?.fairwayPolygon?.clCoordinates,
                bunkerPolygons: currentMapHole?.bunkerPolygons.map(\.clCoordinates) ?? [],
                waterPolygons:  currentMapHole?.waterPolygons.map(\.clCoordinates)  ?? [],
                pathCoordinates: currentHolePathCoordinates,
                aimPoints:      activeAimPoints,
                onAimPointMoved: { idx, coord in
                    userAimPointOverrides[idx] = coord
                },
                onUserPanned: {
                    withAnimation(.spring(response: 0.3)) { showRecenter = true }
                },
                trackedShots:   vm.currentHoleTrackedShots,
                topUIInset:    topSafeArea + 82, // safe area + topBar(44) + gap(2) + infoStrip(30) + margin(6)
                bottomUIInset: bottomSafeArea + 76, // bottom bar content + home indicator
                gpsKey:        coarseGpsKey,
                customAimTarget: aimTarget,
                hazardCounts:  hazardCounts,
                onHazardCountChanged: { key, count in hazardCounts[key] = count },
                onMapTap: { coord in
                    guard let green = currentMapHole?.greenCenterCoordinate?.clCoordinate,
                          let userLoc = vm.location.currentLocation else { return }
                    let yardsToGreen = SatelliteMapBackground.metersBetween(userLoc, green) * 1.09361
                    guard yardsToGreen <= 225 else { return }
                    let tapToGreen = SatelliteMapBackground.metersBetween(coord, green) * 1.09361
                    aimTarget = tapToGreen < 25 ? nil : coord
                },
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
                    HStack(spacing: 10) {
                        ProgressView().tint(HUDStyle.pin)
                        Text("Loading course map…")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .hudGlass(22)
                    Spacer()
                }
                .transition(.opacity)
                .zIndex(5)
            }

            if let unavailable = vm.courseUnavailable {
                courseUnavailableOverlay(unavailable)
                    .zIndex(30)
            }

            if vm.courseUnavailable == nil, let note = vm.degradedTierNote {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: vm.courseTier == .rangefinder ? "location.fill" : "list.bullet.rectangle")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(HUDStyle.live)
                        Text(note)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.95))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .hudGlass(20)
                    .fixedSize()
                    .padding(.top, topSafeArea + 128)   // sits below the hole selector + info strip
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(6)
                .allowsHitTesting(false)
                .task(id: note) {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    withAnimation(.easeInOut(duration: 0.4)) { vm.degradedTierNote = nil }
                }
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

                // Top bar — sit as close to the notch/island as possible
                topBar
                    .padding(.top, 4)

                // Hole info strip
                holeInfoStrip
                    .padding(.top, 2)
                    .padding(.horizontal, 16)

                Spacer()
            }
            .ignoresSafeArea(edges: .bottom)

            // Left sidebar — pinned just above the OSM attribution badge
            leftSidebar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 6)
                .padding(.top, topSafeArea + 120)
                .padding(.bottom, 130)
                .ignoresSafeArea(edges: .bottom)

            // Right sidebar
            rightSidebar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
                .padding(.top, topSafeArea + 132)
                .padding(.bottom, 210)
                .ignoresSafeArea(edges: .bottom)

            // Hazard count badges — top-left, below top bar
            if !hazardCounts.filter({ $0.value > 0 }).isEmpty {
                VStack {
                    HStack(spacing: 5) {
                        hazardCountBadge
                        Spacer()
                    }
                    .padding(.top, topSafeArea + 88)
                    .padding(.leading, 10)
                    Spacer()
                }
                .ignoresSafeArea(edges: .bottom)
            }

            // GPS live/estimate badge — bottom-right above OSM attribution
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    gpsStatusBadge
                        .padding(.trailing, 10)
                        .padding(.bottom, 104)
                }
            }
            .ignoresSafeArea(edges: .bottom)

            // OSM attribution — required by the ODbL license whenever OSM geometry is shown.
            VStack {
                Spacer()
                HStack {
                    OSMAttributionBadge()
                        .padding(.leading, 10)
                        .padding(.bottom, 96)   // above the bottom bar
                    Spacer()
                }
            }
            .ignoresSafeArea(edges: .bottom)

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
                Task {
                    await vm.finishRound()
                    WidgetBridge.clear()
                    if #available(iOS 16.2, *) { ActivityBridge.end() }
                    dismiss()
                }
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
            if let uid = session.currentUser?.id {
                RangeCameraScreen(
                    userId:   uid,
                    backend:  session.backend,
                    context:  buildContext(),
                    onShotSaved: { shot in
                        Task {
                            await vm.addShot(shot)
                            await MainActor.run { beginHudFlight(for: shot) }
                        }
                    }
                )
                .ignoresSafeArea()
                .statusBarHidden(true)
            }
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
                    Task {
                        await vm.setScore(holeIndex: idx, score: s, putts: p, fairwayHit: f, gir: g)
                        // Auto-advance to the next hole after saving score.
                        if vm.currentHoleIndex < (vm.activeRound?.holes.count ?? 0) - 1 {
                            vm.advanceHole()
                        }
                    }
                }
                .tcAppearance()
            }
        }
        .sheet(isPresented: $showScorecard) {
            if let round = vm.activeRound {
                NavigationStack {
                    ScorecardView(round: round, course: vm.selectedCourse)
                }
                .tcAppearance()
            }
        }
        .confirmationDialog(
            "Is this where shot \(vm.currentHoleTrackedShots.count) landed?",
            isPresented: $showLandingConfirm,
            titleVisibility: .visible
        ) {
            Button("Yes — update landing spot") {
                if let gps = vm.location.currentLocation,
                   let last = vm.currentHoleTrackedShots.last {
                    var updated = last
                    updated.endCoordinate = Coordinate(gps)
                    Task { await vm.updateTrackedShot(updated) }
                }
                showCamera = true
            }
            Button("No — keep projected landing") { showCamera = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You're standing at your ball. Confirming will save your current GPS location as where that shot ended.")
        }
        .task {
            if let round = initialRound {
                await vm.resumeRound(round)
            } else if let course = initialCourse, let tee = initialTeeBox {
                await vm.startRoundEnriching(course: course, teeBox: tee)
            }
            pushWidgetData()
        }
        .onAppear {
            registerWatchRoundControls()
        }
        .onDisappear {
            WatchConnectivityBridge.shared.unregisterRoundCommandHandler()
        }
        .onChange(of: vm.activeRound?.id) { _ in
            pushWidgetData()
        }
        .onChange(of: vm.currentHoleIndex) { _ in
            recenterToken += 1
            userAimPointOverrides = [:]
            aimTarget = nil
            hazardCounts = [:]
            showRecenter = false
            pushWidgetData()
        }
        .onChange(of: mapDistances.center) { _ in
            pushWidgetData()
        }
        .onChange(of: vm.activeRound?.scoreSummary.totalScore) { _ in
            pushWidgetData()
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

    // MARK: - Course Unavailable

    private func courseUnavailableOverlay(_ report: CourseAvailabilityReport) -> some View {
        ZStack {
            TrueCarryBackground()
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(TCTheme.panelRaised)
                            .frame(width: 72, height: 72)
                        Circle()
                            .strokeBorder(TCTheme.borderMedium, lineWidth: 1)
                            .frame(width: 72, height: 72)
                        Image(systemName: "map.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(TCTheme.gold)
                    }

                    VStack(spacing: 8) {
                        Text("Course Not Available Yet")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(TCTheme.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(report.courseName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(TCTheme.textSecondary)
                            .multilineTextAlignment(.center)

                        if !report.locationLabel.isEmpty {
                            Text(report.locationLabel)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(TCTheme.textMuted)
                        }
                    }

                    Text(report.message)
                        .font(.system(size: 14))
                        .foregroundColor(TCTheme.textMuted)
                        .lineSpacing(4)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        unavailableMetricRow(
                            title: "Scorecard",
                            value: "\(report.scorecardHoleCount) holes",
                            icon: "list.bullet.rectangle"
                        )
                        TCDivider()
                        unavailableMetricRow(
                            title: "Verified GPS",
                            value: "\(report.geometryHoleCount) holes",
                            icon: "location.viewfinder"
                        )
                        if !report.missingHoleNumbers.isEmpty {
                            TCDivider()
                            unavailableMetricRow(
                                title: "Missing",
                                value: missingHoleLabel(report.missingHoleNumbers),
                                icon: "exclamationmark.triangle"
                            )
                        }
                    }
                    .tcCard(padding: 0)
                }
                .padding(.horizontal, 24)

                VStack(spacing: 10) {
                    TCPrimaryGoldButton(title: "Back to Play", icon: "arrow.left") {
                        dismiss()
                    }

                    Text("We logged this course for geometry backfill and added it to unavailable_courses.csv.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TCTheme.textUltraMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .allowsHitTesting(true)
    }

    private func unavailableMetricRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(TCTheme.gold)
                .frame(width: 24, alignment: .leading)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(TCTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TCTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func missingHoleLabel(_ holes: [Int]) -> String {
        guard !holes.isEmpty else { return "None" }
        if holes.count <= 6 {
            return holes.map(String.init).joined(separator: ", ")
        }
        return "\(holes.prefix(6).map(String.init).joined(separator: ", ")) +\(holes.count - 6)"
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Button { showFinishAlert = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white.opacity(0.95))
                    .hudGlassCircle(44)
            }
            .buttonStyle(HUDPressStyle())

            Spacer()

            HStack(spacing: 14) {
                Button {
                    if vm.currentHoleIndex > 0 { vm.goToHole(vm.currentHoleIndex - 1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(.white.opacity(vm.currentHoleIndex > 0 ? 0.95 : 0.32))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(HUDPressStyle())
                .disabled(vm.currentHoleIndex == 0)

                HStack(spacing: 7) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(TCTheme.sageDeep)

                    if let hole = vm.currentHole {
                        Text(ordinal(hole.holeNumber))
                            .font(.system(size: 20, weight: .semibold, design: .serif))
                            .foregroundColor(.white)
                            .contentTransition(.numericText())
                    } else {
                        Text("—")
                            .font(.system(size: 20, weight: .semibold, design: .serif))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .frame(minWidth: 62)

                Button {
                    if let round = vm.activeRound, vm.currentHoleIndex < round.holes.count - 1 {
                        vm.advanceHole()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(.white.opacity(canAdvanceHole ? 0.95 : 0.32))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(HUDPressStyle())
                .disabled(!canAdvanceHole)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .hudGlass(20)

            Spacer()

            // Recenter button — only visible after the user pans away
            Button {
                recenterToken += 1
                withAnimation(.spring(response: 0.3)) { showRecenter = false }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(HUDStyle.pin)
                    .hudGlassCircle(44)
            }
            .buttonStyle(HUDPressStyle())
            .opacity(showRecenter ? 1 : 0)
            .scaleEffect(showRecenter ? 1 : 0.7)
            .allowsHitTesting(showRecenter)
        }
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: vm.currentHoleIndex)
    }

    private var canAdvanceHole: Bool {
        guard let round = vm.activeRound else { return false }
        return vm.currentHoleIndex < round.holes.count - 1
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        let mod100 = n % 100
        let mod10  = n % 10
        if mod100 >= 11 && mod100 <= 13 { suffix = "th" }
        else if mod10 == 1              { suffix = "st" }
        else if mod10 == 2              { suffix = "nd" }
        else if mod10 == 3             { suffix = "rd" }
        else                            { suffix = "th" }
        return "\(n)\(suffix)"
    }

    // MARK: - Hole Info Strip

    private var holeInfoStrip: some View {
        Group {
            if let hole = vm.currentHole {
                HStack(spacing: 0) {
                    infoText("Par \(hole.par)")
                    stripDivider
                    infoText(scorecardYardage.map { "\($0) yds" } ?? "— yds")
                    stripDivider
                    infoText("HCP \(holeHandicap)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .hudGlass(14)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func infoText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
    }

    private var stripDivider: some View {
        Rectangle().fill(.white.opacity(0.18)).frame(width: 1, height: 13)
    }

    // MARK: - Left Sidebar

    private var leftSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)

            if mapDistances.isAvailable {
                VStack(alignment: .leading, spacing: 5) {
                    if let f = mapDistances.front {
                        distanceRow(label: "F", yards: f, isHero: false)
                    }
                    if let c = mapDistances.center {
                        distanceRow(label: "C", yards: c, isHero: true)
                    }
                    if let b = mapDistances.back {
                        distanceRow(label: "B", yards: b, isHero: false)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .hudGlass(18)
                .frame(minWidth: 90, alignment: .leading)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mapDistances.center)
            }
        }
    }

    private func distanceRow(label: String, yards: Int, isHero: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: isHero ? 11 : 9, weight: .black, design: .rounded))
                .foregroundColor(isHero ? .white : .white.opacity(0.5))
                .frame(width: 12, alignment: .leading)
            Text("\(yards)")
                .font(.system(size: isHero ? 38 : 15, weight: isHero ? .black : .semibold,
                              design: .rounded))
                .foregroundColor(isHero ? .white : .white.opacity(0.75))
                .contentTransition(.numericText())
                .shadow(color: .black.opacity(isHero ? 0.5 : 0.2), radius: isHero ? 5 : 2, y: 1)
            if isHero {
                Text("yd")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // MARK: - GPS Status Badge

    private var gpsStatusBadge: some View {
        let isLive = gpsOn && userIsNearCurrentHole
        return HStack(spacing: 4) {
            if isLive {
                LivePulseDot(color: HUDStyle.live)
            } else {
                Circle()
                    .fill(.white.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
            Text(isLive ? "GPS" : "Est")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(isLive ? HUDStyle.live : .white.opacity(0.45))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black.opacity(0.45))
        .clipShape(Capsule())
    }

    // MARK: - Hazard Count Badge

    private var hazardCountBadge: some View {
        let active = hazardCounts
            .filter { $0.value > 0 }
            .sorted(by: { $0.key < $1.key })
        return HStack(spacing: 5) {
            ForEach(active, id: \.key) { key, count in
                HStack(spacing: 3) {
                    Image(systemName: key.hasPrefix("water") ? "drop.fill" : "circle.fill")
                        .font(.system(size: 7))
                        .foregroundColor(key.hasPrefix("water")
                            ? Color(red: 0.35, green: 0.62, blue: 0.78)
                            : Color(red: 0.92, green: 0.85, blue: 0.67))
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.5))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Right Sidebar

    private var rightSidebar: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                railButton("location.fill", isActive: gpsOn) { gpsOn.toggle() }
                railButton("camera.fill", isActive: false) { openCamera() }
                railButton("list.number", isActive: false) { showScorecard = true }
            }
            .padding(.vertical, 14)
            .frame(width: 56)
            .hudGlass(28)
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
                        .fill(TCTheme.sage)
                        .frame(width: 38, height: 38)
                        .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                        .shadow(color: TCTheme.sage.opacity(0.6), radius: 8)
                }
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isActive ? .white : .white.opacity(0.88))
            }
            .frame(width: 42, height: 42)
            .contentShape(Circle())
        }
        .buttonStyle(HUDPressStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isActive)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle().fill(TCTheme.goldGradient).frame(width: 38, height: 38)
                Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1).frame(width: 38, height: 38)
                Text(userInitials)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(TCTheme.deepGreen)
            }

            // Player + score info
            VStack(alignment: .leading, spacing: 2) {
                Text(displayPlayerName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(scoreToParString)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(scoreToParColor)
                    Text("· \(vm.activeRound?.scoreSummary.totalScore ?? 0) strokes")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                }
            }

            Spacer(minLength: 0)

            // Camera
            Button { openCamera() } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.12))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(HUDPressStyle())

            // Add Score — stacked gold button
            Button { showScoreEntry = true } label: {
                VStack(spacing: 2) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .bold))
                    Text("Add Score")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                }
                .foregroundColor(TCTheme.deepGreen)
                .frame(width: 70, height: 48)
                .background(TCTheme.goldGradient)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: TCTheme.gold.opacity(0.4), radius: 6, y: 2)
            }
            .buttonStyle(HUDPressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(HUDStyle.tint.opacity(0.42))
            }
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LinearGradient(
                    colors: [.white.opacity(0.18), .white.opacity(0.06)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(height: 1)
        }
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
        return currentMapHole?.teeCoordinate
    }

    /// Open the camera, first asking the user to confirm their last shot's landing when applicable.
    private func openCamera() {
        if !vm.currentHoleTrackedShots.isEmpty, vm.location.currentLocation != nil {
            showLandingConfirm = true
        } else {
            showCamera = true
        }
    }

    // MARK: - HUD flight (launch-monitor → on-course)

    /// After a HUD shot, project where the ball landed on THIS hole using the measured
    /// distance, aimed at the pin and offset by the shot's horizontal launch angle, then
    /// animate the ball flying there. Falls back to manual placement if there's no pin.
    private func beginHudFlight(for shot: SavedShot) {
        guard let start = startCoordForNewShot() else { return }
        // Use green center; fall back to last hole-path point so we can still project a landing.
        let pin = currentMapHole?.greenCenterCoordinate
               ?? currentHolePathCoordinates.last.map { Coordinate($0) }
        guard let pin else { return }
        let distanceYds = shot.metrics.totalYards > 0 ? shot.metrics.totalYards
                        : shot.metrics.carryYards
        guard distanceYds > 0 else { return }
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
        let lie = vm.classifyLie(at: Coordinate(landing), hole: currentMapHole)
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

    private static func metersBetween(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private func greenDepthOffsetYards(center: Coordinate?, edge: Coordinate?) -> Int {
        guard let center, let edge else { return 12 }
        let yards = Self.metersBetween(center.clCoordinate, edge.clCoordinate) * 1.09361
        return max(6, min(35, Int(yards.rounded())))
    }

    private static func pathLengthMeters(_ path: [CLLocationCoordinate2D]) -> Double {
        guard path.count >= 2 else { return 0 }
        return zip(path, path.dropFirst()).reduce(0) { partial, pair in
            partial + metersBetween(pair.0, pair.1)
        }
    }

    private static func coordinate(onPath path: [CLLocationCoordinate2D],
                                   atMeters targetMeters: Double) -> CLLocationCoordinate2D {
        guard let first = path.first else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        guard path.count >= 2 else { return first }
        var remaining = max(0, targetMeters)
        for (start, end) in zip(path, path.dropFirst()) {
            let segment = metersBetween(start, end)
            if remaining <= segment {
                let t = segment <= 0 ? 0 : remaining / segment
                return CLLocationCoordinate2D(
                    latitude: start.latitude + (end.latitude - start.latitude) * t,
                    longitude: start.longitude + (end.longitude - start.longitude) * t
                )
            }
            remaining -= segment
        }
        return path.last ?? first
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
        // Player origin: last shot end → GPS → tee (mirrors startCoordForNewShot logic).
        let playerCoord: CLLocationCoordinate2D? =
            vm.currentHoleTrackedShots.last?.endCoordinate.clCoordinate
            ?? vm.location.currentLocation
            ?? currentMapHole?.teeCoordinate?.clCoordinate

        return ShotContext(
            sourceMode:            .course,
            courseRoundId:         vm.activeRound?.id,
            holeNumber:            vm.currentHole?.holeNumber,
            holePar:               vm.currentHole?.par,
            holeYardage:           scorecardYardage,
            courseName:            vm.activeRound?.courseName,
            holeHandicap:          holeHandicap,
            playerCoordinate:      playerCoord,
            greenCenterCoordinate: currentMapHole?.greenCenterCoordinate?.clCoordinate,
            teeCoordinate:         currentMapHole?.teeCoordinate?.clCoordinate,
            holePathCoordinates:   currentHolePathCoordinates
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

    private func ordinalSuffix(_ n: Int) -> String {
        String(ordinal(n).drop { $0.isNumber })
    }
}

// MARK: - On-course HUD styling
//
// A premium frosted-glass HUD that floats over the satellite imagery: real material blur
// (forced dark for legibility over bright fairways), a forest tint, and a hairline bone edge —
// True Carry's brand applied to the on-course experience. Replaces the old flat black pills.

enum HUDStyle {
    /// Marker-gold pin accent (flag, primary targets).
    static let pin = TCTheme.goldLight
    /// Vivid Fairway green used only for the "live GPS" pulse + front-edge arrow.
    static let live = Color(red: 0.45, green: 0.80, blue: 0.52)
    /// Forest tint layered under the blur.
    static let tint = Color(red: 0.055, green: 0.094, blue: 0.071)
}

extension View {
    /// Frosted-glass HUD surface — material blur + forest tint + bone hairline + soft lift.
    func hudGlass(_ radius: CGFloat = 18,
                  strokeOpacity: Double = 0.14,
                  tintOpacity: Double = 0.34) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(HUDStyle.tint.opacity(tintOpacity))
                }
                .environment(\.colorScheme, .dark)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(strokeOpacity + 0.06),
                                                Color.white.opacity(strokeOpacity * 0.4)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.38), radius: 16, x: 0, y: 8)
    }

    /// Circular frosted-glass button surface.
    func hudGlassCircle(_ size: CGFloat) -> some View {
        self
            .frame(width: size, height: size)
            .background(
                Circle().fill(.ultraThinMaterial)
                    .overlay(Circle().fill(HUDStyle.tint.opacity(0.34)))
                    .environment(\.colorScheme, .dark)
            )
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
    }
}

/// Tactile press feedback for HUD controls.
struct HUDPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A soft pulsing dot used to signal a live GPS fix.
struct LivePulseDot: View {
    var color: Color = HUDStyle.live
    @State private var on = false
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay(
                Circle().stroke(color.opacity(0.5), lineWidth: 4)
                    .scaleEffect(on ? 2.1 : 1)
                    .opacity(on ? 0 : 0.8)
            )
            .shadow(color: color.opacity(0.8), radius: 4)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true }
            }
    }
}
