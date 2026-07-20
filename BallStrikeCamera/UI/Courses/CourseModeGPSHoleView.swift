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
        frame = CGRect(x: 0, y: 0, width: 58, height: 52)
        centerOffset = CGPoint(x: 0, y: -36)
        backgroundColor = .clear

        card.axis = .vertical
        card.alignment = .leading
        card.spacing = 1
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        card.frame = bounds
        card.backgroundColor = UIColor(white: 0.03, alpha: 0.74)
        card.layer.cornerRadius = 10
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
        frontLabel.font = UIFont.systemFont(ofSize: 10, weight: .heavy)
        centerLabel.font = UIFont.systemFont(ofSize: 18, weight: .black)
        backLabel.font = UIFont.systemFont(ofSize: 10, weight: .heavy)
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
                .font: UIFont.systemFont(ofSize: 9, weight: .heavy),
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
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
    var title: String? { nil }
}

/// Small reference dot left at the true green center after the user moves the flag.
private final class GreenCenterDotAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

/// Draggable flag view — same continuous-pan approach as AimPointAnnotationView. The parent
/// applies the rules on drag end (snap to center ≤3yd, clamp to 15yd, or spawn a waypoint).
private final class DraggableFlagAnnotationView: MKAnnotationView {
    var onDragEnded: ((CLLocationCoordinate2D) -> Void)?
    weak var mapView: MKMapView?
    /// Green center + boundary so the ring can preview live whether releasing here keeps
    /// the flag (gold ring) or spawns a waypoint (white ring) — prevents accidental
    /// waypoint creation when the intended pin spot is near the 20y boundary.
    var greenCenter: CLLocationCoordinate2D?
    var waypointBoundaryYds: Double = 30

    private var ring: UIView!

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        isDraggable    = false
        canShowCallout = false
        backgroundColor = .clear
        // Same grab affordance as the aim-point rings — big hit area + visible ring —
        // so the flag reads as draggable the way waypoints do.
        let hitSize:  CGFloat = 88
        let ringSize: CGFloat = 40
        frame = CGRect(x: 0, y: 0, width: hitSize, height: hitSize)
        centerOffset = .zero

        ring = UIView(frame: CGRect(
            x: (hitSize - ringSize) / 2, y: (hitSize - ringSize) / 2,
            width: ringSize, height: ringSize))
        ring.layer.cornerRadius = ringSize / 2
        ring.layer.borderWidth  = 2.5
        ring.layer.shadowColor  = UIColor.black.cgColor
        ring.layer.shadowRadius = 5
        ring.layer.shadowOpacity = 0.55
        ring.layer.shadowOffset  = .zero
        ring.isUserInteractionEnabled = false
        addSubview(ring)
        setRingStyle(isFlag: true)

        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        let img = UIImage(systemName: "flag.fill", withConfiguration: cfg)?
            .withTintColor(UIColor(red: 1.0, green: 0.82, blue: 0.0, alpha: 1.0),
                           renderingMode: .alwaysOriginal)
        let iv = UIImageView(image: img)
        iv.center = CGPoint(x: bounds.midX, y: bounds.midY)
        iv.isUserInteractionEnabled = false
        addSubview(iv)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -20, dy: -20).contains(point)
    }

    private func setRingStyle(isFlag: Bool) {
        if isFlag {
            ring.backgroundColor    = UIColor(red: 1.0, green: 0.82, blue: 0.0, alpha: 0.12)
            ring.layer.borderColor  = UIColor(red: 1.0, green: 0.82, blue: 0.0, alpha: 0.92).cgColor
        } else {
            ring.backgroundColor    = UIColor.white.withAlphaComponent(0.15)
            ring.layer.borderColor  = UIColor.white.withAlphaComponent(0.92).cgColor
        }
    }

    private func previewDropState(at coord: CLLocationCoordinate2D) {
        guard let green = greenCenter else { return }
        let a = MKMapPoint(coord), b = MKMapPoint(green)
        let yards = a.distance(to: b) * 1.09361
        setRingStyle(isFlag: yards <= waypointBoundaryYds)
    }

    /// Transform to restore after a drag (set by the factory: inverse-stretch correction).
    private var restingTransform: CGAffineTransform = .identity

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let map = mapView,
              let pin = annotation as? GreenPinAnnotation else { return }
        let coord = map.convert(gesture.location(in: map), toCoordinateFrom: map)
        switch gesture.state {
        case .began:
            map.isScrollEnabled = false
            pin.coordinate = coord
            // Grow while dragging — makes the gold↔white (flag↔waypoint) boundary preview
            // readable under the finger.
            restingTransform = transform
            UIView.animate(withDuration: 0.12) {
                self.transform = self.restingTransform.scaledBy(x: 1.45, y: 1.45)
            }
            previewDropState(at: coord)
        case .changed:
            pin.coordinate = coord
            previewDropState(at: coord)
        case .ended, .cancelled:
            map.isScrollEnabled = true
            UIView.animate(withDuration: 0.12) {
                self.transform = self.restingTransform
            }
            setRingStyle(isFlag: true)
            onDragEnded?(coord)
        default:
            break
        }
    }
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

/// A single dispersion shot dot — the selected club's typical landing pattern (#7).
private final class DispersionDotCircle: MKCircle { var fill: UIColor = .systemGreen }

/// A projected dispersion shot: where it lands + its fill color (proximity-graded for a single
/// club, or the club's identity color when several clubs are overlaid at once).
private struct DispersionDot {
    let coord: CLLocationCoordinate2D
    let fill: UIColor
}

extension CLLocationCoordinate2D {
    /// Bearing in degrees (clockwise from north) toward another coordinate.
    func bearing(to b: CLLocationCoordinate2D) -> Double {
        let dLon = (b.longitude - longitude) * .pi / 180
        let la1 = latitude * .pi / 180, la2 = b.latitude * .pi / 180
        let y = sin(dLon) * cos(la2)
        let x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Great-circle distance to another coordinate, in yards.
    func yards(to b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) * 1.0936133
    }

    /// Move `forward` yards along `bearingDeg`, then `right` yards perpendicular
    /// (positive = right of the aim line). Used to place dispersion dots.
    func projected(yardsForward f: Double, yardsRight r: Double, bearingDeg: Double) -> CLLocationCoordinate2D {
        let mPerYd = 1.0 / 1.0936133
        let fwd = f * mPerYd, rgt = r * mPerYd
        let b = bearingDeg * .pi / 180
        let east  = fwd * sin(b) + rgt * cos(b)
        let north = fwd * cos(b) - rgt * sin(b)
        return CLLocationCoordinate2D(
            latitude:  latitude  + north / 111320.0,
            longitude: longitude + east  / (111320.0 * cos(latitude * .pi / 180))
        )
    }
}

/// Which distance figure a dispersion dot is projected at: where the shot first landed, or where
/// it finally came to rest (including roll). Mirrors the same toggle on the Insights dispersion chart.
private enum DispersionMetric: String, CaseIterable {
    case carry = "Carry", total = "Total"
}

/// Which shots feed the on-course dispersion overlay — everything, range/sim captures only,
/// or only shots hit during real rounds. Mirrors the Insights source toggle.
enum DispersionShotSource: String, CaseIterable {
    case all = "All", range = "Range & Sim", course = "On-Course"

    func includes(_ s: SavedShot) -> Bool {
        switch self {
        case .all:    return true
        case .course: return s.mode == .course || s.roundId != nil
        case .range:  return s.mode != .course && s.roundId == nil
        }
    }
}

/// Per-shot (plotted distance, signed lateral yards) — same model the insights dispersion
/// chart uses, reused to place the on-course dispersion overlay. `metric` selects whether the
/// returned distance is the carry (first landing) or total (after roll) yardage; the lateral
/// curve math is unchanged either way since it's derived from the true landing fraction.
private enum ShotDispersion {
    static func point(for shot: SavedShot, metric: DispersionMetric = .carry) -> (carry: Double, lateral: Double)? {
        let carry = shot.metrics.carryYards
        guard carry > 0 else { return nil }
        let total = shot.metrics.totalYards > 0 ? shot.metrics.totalYards : carry
        let signedHLA = shot.metrics.hlaDirection.lowercased() == "left"
            ? -shot.metrics.hlaDegrees : shot.metrics.hlaDegrees
        let hlaRad = signedHLA * .pi / 180.0
        let spinAxis = shot.metrics.spinAxisDegrees
        let sidespin = shot.metrics.sidespinRpm
        let curveStrength: Double
        if abs(spinAxis) > 0.5 {
            curveStrength = (spinAxis > 0 ? 1.0 : -1.0) * min(abs(spinAxis) / 16.0, 1.0)
        } else if abs(sidespin) > 30 {
            curveStrength = (sidespin > 0 ? 1.0 : -1.0) * min(abs(sidespin) / 1100.0, 1.0)
        } else {
            curveStrength = 0
        }
        let curveMagnitude = abs(curveStrength) * max(total * 0.10, 8.0)
        let curveSign: Double = curveStrength >= 0 ? 1.0 : -1.0
        let carryFrac = carry / total
        let lateral = tan(hlaRad) * total * carryFrac + curveSign * curveMagnitude * pow(carryFrac, 1.6)
        return (metric == .carry ? carry : total, lateral)
    }
}

// MARK: - Aim Point (draggable circle on the map)

private final class AimPointAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    /// Index into the PARENT's activeAimPoints (original index — not the drawn position,
    /// which can differ when the backwards-filter drops points).
    let index: Int
    /// Flag-spawned waypoints render smaller than the hole's own waypoints.
    var isFlagSpawned = false

    init(coordinate: CLLocationCoordinate2D, index: Int) {
        self.coordinate = coordinate
        self.index = index
    }
}

private final class AimPointAnnotationView: MKAnnotationView {
    /// Fires on every pan-gesture .changed with (aimIndex, newCoord).
    var onDragChanged: ((Int, CLLocationCoordinate2D) -> Void)?
    /// Fires on pan-gesture .ended/.cancelled with final coord.
    var onDragEnded:   ((Int, CLLocationCoordinate2D) -> Void)?
    /// Must be set by the factory so handlePan can convert screen → map coord.
    weak var mapView: MKMapView?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        isDraggable    = false   // own pan gesture instead — gives continuous updates
        canShowCallout = false
        backgroundColor = .clear
        centerOffset    = .zero

        let hitSize:  CGFloat = 88   // was 64 — field feedback: rings were hard to grab
        let ringSize: CGFloat = 42   // was 48 — field feedback: slightly too big
        frame = CGRect(x: 0, y: 0, width: hitSize, height: hitSize)

        let ring = UIView(frame: CGRect(
            x: (hitSize - ringSize) / 2, y: (hitSize - ringSize) / 2,
            width: ringSize, height: ringSize))
        ring.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        ring.layer.cornerRadius = ringSize / 2
        ring.layer.borderColor  = UIColor.white.withAlphaComponent(0.92).cgColor
        ring.layer.borderWidth  = 2.5
        ring.layer.shadowColor  = UIColor.black.cgColor
        ring.layer.shadowRadius = 5
        ring.layer.shadowOpacity = 0.55
        ring.layer.shadowOffset  = .zero
        ring.isUserInteractionEnabled = false
        addSubview(ring)

        let dotSize: CGFloat = 8
        let dot = UIView(frame: CGRect(
            x: (hitSize - dotSize) / 2, y: (hitSize - dotSize) / 2,
            width: dotSize, height: dotSize))
        dot.backgroundColor = .white
        dot.layer.cornerRadius = dotSize / 2
        dot.isUserInteractionEnabled = false
        addSubview(dot)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Expand the touch area beyond the visible bounds.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -20, dy: -20).contains(point)
    }

    /// Transform to restore after a drag (set by the factory: inverse-stretch correction).
    private var restingTransform: CGAffineTransform = .identity

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let map  = mapView,
              let aim  = annotation as? AimPointAnnotation else { return }
        let coord = map.convert(gesture.location(in: map), toCoordinateFrom: map)
        aim.coordinate = coord
        switch gesture.state {
        case .began:
            // Prevent MapKit's own pan gesture from competing and stealing events.
            map.isScrollEnabled = false
            // Grow while dragging so the ring stays visible under the finger.
            restingTransform = transform
            UIView.animate(withDuration: 0.12) {
                self.transform = self.restingTransform.scaledBy(x: 1.45, y: 1.45)
            }
        case .changed:
            onDragChanged?(aim.index, coord)
        case .ended, .cancelled:
            map.isScrollEnabled = true
            UIView.animate(withDuration: 0.12) {
                self.transform = self.restingTransform
            }
            onDragEnded?(aim.index, coord)
        default:
            break
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
    private static let labelFont = UIFont.systemFont(ofSize: 15, weight: .bold)

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 50, height: 28)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        pill.backgroundColor = UIColor(white: 0.04, alpha: 0.82)
        pill.layer.cornerRadius = 14
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
            ]).width + 20
            let w = max(40, tw)
            frame = CGRect(x: 0, y: 0, width: w, height: 28)
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
    /// Live GPS fix, ungated by hole proximity — used only as a last-resort centering anchor
    /// when there's no hole geometry at all (GPS-estimate courses), where "near current hole"
    /// can't be evaluated in the first place. `userCoord` above stays proximity-gated for the
    /// aim-line/tee-to-green framing paths, which do assume the player is actually at the hole.
    var rawUserCoord: CLLocationCoordinate2D?
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

    // Dispersion dots for the selected club (#7) — projected landing points.
    var dispersionDots:  [DispersionDot] = []

    // UI inset hints so the camera frames the hole within the usable (non-overlapped) area.
    var topUIInset:    CGFloat = 100   // pts: safe area + top pills height
    var bottomUIInset: CGFloat = 100   // pts: bottom bar + home indicator height
    var gpsKey:        String = ""
    // Fine-grained (~5m) GPS key: redraws the aim lines/labels as the player walks, without
    // triggering the camera reframe that gpsKey (coarse, ~20yd) governs.
    var fineGpsKey:    String = ""
    /// activeAimPoints index of the flag-spawned waypoint (nil when none) — drawn smaller.
    var flagSpawnedIndex: Int? = nil
    // Custom aim target placed by a tap within 225 yards of the green.
    var customAimTarget: CLLocationCoordinate2D? = nil
    // User-moved pin position (≤15yd from green center). Lines target this; flag renders here.
    var pinCoord: CLLocationCoordinate2D? = nil
    // Fires when the user drags the flag; parent applies the snap/limit/waypoint rules.
    var onPinMoved: ((CLLocationCoordinate2D) -> Void)? = nil
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
        // A single fairway waypoint is enough to form a dogleg ([start, waypoint, green]); only a
        // truly empty path falls back to a straight line.
        guard pathCoordinates.count >= 1 else { return [start, green] }
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
        map.mapType = .satellite
        map.isScrollEnabled     = true
        map.isZoomEnabled       = true
        map.isRotateEnabled     = true    // two-finger rotation; recenter arrow restores heading
        map.isPitchEnabled      = false
        map.showsUserLocation   = true
        map.showsCompass        = false
        map.delegate            = context.coordinator
        context.coordinator.parent = self
        // Limit zoom: min 50m (green detail) → max 4000m (accommodates long par-5s). Assigning
        // cameraZoomRange can synchronously fire `regionDidChangeAnimated` on the delegate (MapKit
        // re-validates/clamps the region as part of applying the new range). Without marking this
        // as a programmatic change first, the Coordinator mistakes it for a user pan and calls
        // `onUserPanned`, which mutates `@State` while this makeUIView call is itself still inside
        // SwiftUI's view-update pass — undefined behavior that can silently drop the render pass
        // (blank/white screen) until something else (e.g. backgrounding the app) forces a fresh one.
        context.coordinator.setProgrammaticRegionChange(true)
        map.cameraZoomRange = MKMapView.CameraZoomRange(
            minCenterCoordinateDistance: 50,
            maxCenterCoordinateDistance: 4000
        )
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                          action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)
        // Crop ~12% from each side horizontally and stretch to fill, making the fairway
        // appear wider without changing the vertical zoom level.
        map.transform = CGAffineTransform(scaleX: Self.kHorizStretch, y: 1.0)
        // Seed an initial region so the map never renders blank/white before framing runs. Courses
        // with no hole geometry (scorecard-only) otherwise had nothing to frame → white screen.
        if let seed = teeCoord ?? greenCoord ?? courseCoord ?? userCoord ?? rawUserCoord {
            context.coordinator.setProgrammaticRegionChange(true)
            map.setRegion(MKCoordinateRegion(center: seed,
                                             latitudinalMeters: 1400,
                                             longitudinalMeters: 1400),
                          animated: false)
        }
        return map
    }

    /// Default horizontal stretch. Par 5s use a reduced stretch so the narrow
    /// fairway corridor is expanded to fill the screen width proportionally.
    static let kHorizStretch:    CGFloat = 1.30
    static let kHorizStretchPar5: CGFloat = 1.20

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self

        // Par 5s use a reduced horizontal stretch so the narrow fairway corridor fills
        // the screen proportionally rather than appearing as a skinny central strip.
        let targetStretch = aimPoints.count >= 2 ? Self.kHorizStretchPar5 : Self.kHorizStretch
        // Always enforce the stretch — the frame was laid out under it, so any drop to identity
        // shrinks the rendered map and exposes white bands at the edges.
        if abs(map.transform.a - targetStretch) > 0.01 {
            map.transform = CGAffineTransform(scaleX: targetStretch, y: 1.0)
        }

        // The drawn content (polygons, tee line, flag, aim, shots) depends only on the HOLE — not
        // the live GPS dot, which SwiftUI re-renders many times a second. Skip the expensive
        // overlay teardown/rebuild when nothing visual changed; this is the key to a smooth map.
        let g = greenCoord.map { "\($0.latitude),\($0.longitude)" } ?? "-"
        let t = teeCoord.map { "\($0.latitude),\($0.longitude)" } ?? "-"
        let aimKey = aimPoints.map { "\(Int($0.latitude * 10000)),\(Int($0.longitude * 10000))" }.joined(separator: "|")
        let aimTgtKey = customAimTarget.map { "\(Int($0.latitude * 10000)),\(Int($0.longitude * 10000))" } ?? ""
        // Include the dispersion set so toggling/selecting a club rebuilds the overlays
        // immediately. Must reflect EVERY dot's full position: the old key (count + first
        // dot's latitude at ~1.1m) missed carry/total, slope, and wind toggles entirely —
        // those keep the count constant and shift dots along the aim line, which on an
        // east-west hole changes longitude while latitude stays put, so the map never redrew.
        let dispKey: String = {
            guard !dispersionDots.isEmpty else { return "0" }
            var acc: Int64 = 0
            for d in dispersionDots {
                acc &+= Int64((d.coord.latitude * 1_000_000).rounded())
                acc &+= Int64((d.coord.longitude * 1_000_000).rounded()) &* 31
            }
            return "\(dispersionDots.count)@\(acc)"
        }()
        let pinKey = pinCoord.map { "\(Int($0.latitude * 1_000_000)),\(Int($0.longitude * 1_000_000))" } ?? ""
        let renderKey = "\(focusId)|\(g)|\(t)|\(trackedShots.count)|\(aimKey)|\(recenterToken)|\(gpsKey)|\(fineGpsKey)|\(aimTgtKey)|\(dispKey)|\(pinKey)"
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

        // Dispersion dots for the selected club(s) (#7) — circles on the turf.
        for dot in dispersionDots {
            let circle = DispersionDotCircle(center: dot.coord, radius: 2.0)
            circle.fill = dot.fill
            map.addOverlay(circle, level: .aboveLabels)
        }

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
        // Draw-time sanity on the tap-to-aim target: it must sit between the player and the
        // green (or right around the green). A stale/bad target — e.g. one placed before the
        // placement rules tightened — otherwise drags the whole line into the woods.
        var validAimTarget = customAimTarget
        if let at = validAimTarget, let g = greenCoord {
            let targetToGreen = MKMapPoint(at).distance(to: MKMapPoint(g)) * 1.09361
            let startToGreen  = lineStart.map { MKMapPoint($0).distance(to: MKMapPoint(g)) * 1.09361 }
            if targetToGreen > max(startToGreen ?? 0, 40) { validAimTarget = nil }
        }
        // Custom aim target overrides the pin; the (possibly user-moved) FLAG position is the
        // final line target — never the green center dot once the flag has been moved.
        let effectiveGreen: CLLocationCoordinate2D? = validAimTarget ?? pinCoord ?? greenCoord

        var holePathForOverlay: [CLLocationCoordinate2D] = []
        if let green = effectiveGreen, let start = lineStart, !coordsEqual(start, green) {
            // Live GPS: the line is ALWAYS direct player → pin. preferredHolePath splices the
            // OSM hole-path waypoints between start and green, and those include points the
            // player has already walked past — mid-hole that drew player → tee-side waypoint
            // → green, i.e. the infamous "line back to the tees". The dogleg routing is only
            // for planning views with no live fix (start = tee).
            // With the flag moved, the OSM hole path (which terminates at the green CENTER)
            // would draw start → center → flag. The moved flag always owns the line: direct.
            holePathForOverlay = (userCoord != nil || (pinCoord != nil && validAimTarget == nil))
                ? [start, green]
                : preferredHolePath(start: start, green: green)
            if shouldRecenter {
                // Always frame the FULL hole tee → green (like every reference GPS app): the
                // camera is set once per hole and stays fixed while the player dot walks it.
                // No progressive zoom-in toward the green — that constant reframing was
                // disorienting and made the view creep in as the player approached the pin.
                let frameStart = teeCoord ?? (holePathForOverlay.first ?? start)
                let routeEnd   = holePathForOverlay.last  ?? green
                // The overlay's aim line still starts at the player; the CAMERA path must
                // start at frameStart or a player behind the tee drags the fit off the hole.
                let cameraPath = preferredHolePath(start: frameStart, green: routeEnd)
                let heading    = Self.bearing(from: frameStart, to: routeEnd)

                let kPad     = 20.0
                let h_rad    = heading * .pi / 180.0
                let cosLat   = cos(frameStart.latitude * .pi / 180.0)
                let kMPerDeg = 111_320.0
                var minX = Double.infinity, maxX = -Double.infinity
                var minY = Double.infinity, maxY = -Double.infinity
                // Bounds: the whole hole — tee, full camera path, green.
                let boundsCoords = (teeCoord.map { [$0] } ?? [])
                    + cameraPath + [routeEnd]
                for coord in boundsCoords {
                    let dn = (coord.latitude  - frameStart.latitude)  * kMPerDeg
                    let de = (coord.longitude - frameStart.longitude) * kMPerDeg * cosLat
                    let sy =  dn * cos(h_rad) + de * sin(h_rad)
                    let sx = -dn * sin(h_rad) + de * cos(h_rad)
                    minX = min(minX, sx); maxX = max(maxX, sx)
                    minY = min(minY, sy); maxY = max(maxY, sy)
                }
                let horizExtent = max((maxX - minX) + 2 * kPad, kPad * 2)
                let midX        = (minX + maxX) / 2.0

                let centerOnPath = Self.interpolate(frameStart, routeEnd, t: centerT)
                let cosLatC = cos(centerOnPath.latitude * .pi / 180.0)
                let biasedCenter = CLLocationCoordinate2D(
                    latitude:  centerOnPath.latitude  - midX * sin(h_rad) / kMPerDeg,
                    longitude: centerOnPath.longitude + midX * cos(h_rad) / (kMPerDeg * max(cosLatC, 1e-6))
                )

                // Altitude by the design's own equation instead of the old edge-padded
                // fit + 0.92 zoom-in + 600 m par-5 cap (the cap meant holes longer than
                // ~570 m along-path could NEVER show their tee, and the multiplier ate
                // the fit's margin on the rest — the recenter arrow only "fixed" it
                // because mid-hole the remaining route is shorter). The layout wants
                // the anchor (tee/player) at screen fraction 1−botF and the green at
                // topF, i.e. the hole's along-path span fills the usable band exactly:
                // full-screen vertical meters = span / usableF. Fit a zero-padding rect
                // of that height and take MapKit's altitude — vertical screen meters
                // at pitch 0 depend only on altitude, so the later heading rotation
                // can't invalidate it, and there is no post-hoc correction to fail.
                let spanMeters       = (maxY - minY) + 2 * kPad
                let fullScreenMeters = spanMeters / usableF
                let ptsPerMeter = MKMapPointsPerMeterAtLatitude(biasedCenter.latitude)
                let centerPt    = MKMapPoint(biasedCenter)
                let fittingRect = MKMapRect(
                    x: centerPt.x - (horizExtent / 2) * ptsPerMeter,
                    y: centerPt.y - (fullScreenMeters / 2) * ptsPerMeter,
                    width:  horizExtent * ptsPerMeter,
                    height: fullScreenMeters * ptsPerMeter
                )
                // The PREVIOUS hole's cameraBoundary is still active here; with it in
                // place setVisibleMapRect gets clamped and the altitude read below
                // comes out wrong. Clear it first. (Two setProgrammaticRegionChange
                // calls: setVisibleMapRect (animated:false) fires regionDidChange
                // synchronously, consuming the flag.)
                map.cameraBoundary = nil
                context.coordinator.setProgrammaticRegionChange(true)
                map.setVisibleMapRect(fittingRect, edgePadding: .zero, animated: false)
                // Let the player pan a bit beyond the hole itself (to check a bailout or the next
                // tee) without being able to scroll away indefinitely — mirrors cameraZoomRange's
                // "limited but not locked" zoom behavior, just for panning.
                let panPad = 200.0 * ptsPerMeter
                map.cameraBoundary = MKMapView.CameraBoundary(mapRect: fittingRect.insetBy(dx: -panPad, dy: -panPad))
                let fittedAlt = max(map.camera.altitude, 150.0)

                let cam = MKMapCamera(lookingAtCenter: biasedCenter,
                                      fromDistance: fittedAlt,
                                      pitch: 0,
                                      heading: heading)
                context.coordinator.setProgrammaticRegionChange(true)
                context.coordinator.lastProgrammaticHeading = heading
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
                map.cameraBoundary = nil   // stale boundary from the previous hole clamps the fit
                context.coordinator.setProgrammaticRegionChange(true)
                map.setVisibleMapRect(rect, edgePadding: edgePad, animated: false)
                let panPad = 200.0 * ptsPerMeter
                map.cameraBoundary = MKMapView.CameraBoundary(mapRect: rect.insetBy(dx: -panPad, dy: -panPad))
                // Reuse the center setVisibleMapRect already solved for (which correctly biases
                // upward for topUIInset > bottomUIInset) instead of re-centering dead-on `green` —
                // MKMapCamera(lookingAtCenter:) always places its point at the screen's true 50%
                // regardless of edge padding, which was leaving a large gap between the green and
                // the top bar since topUIInset is roughly double bottomUIInset.
                let biasedCenter = map.camera.centerCoordinate
                let alt = max(map.camera.altitude, 50.0)
                let cam = MKMapCamera(lookingAtCenter: biasedCenter, fromDistance: alt, pitch: 0, heading: 0)
                context.coordinator.setProgrammaticRegionChange(true)
                map.setCamera(cam, animated: context.coordinator.hasInitializedRegion)
                context.coordinator.completeRecenter(focusId: focusId, recenterToken: recenterToken, gpsKey: gpsKey)
            }
        } else {
            // No hole geometry: center on the course, else the player's live location, else a
            // neutral default. (Previously fell straight to San Francisco, ignoring the player.)
            let center = courseCoord ?? userCoord ?? rawUserCoord ?? CLLocationCoordinate2D(latitude: 37.785834, longitude: -122.406417)
            if shouldRecenter {
                map.cameraBoundary = nil   // stale boundary from the previous hole clamps the fit
                context.coordinator.setProgrammaticRegionChange(true)
                let span = 650 / usableF
                map.setRegion(
                    MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span),
                    animated: context.coordinator.hasInitializedRegion
                )
                // No hole geometry to bound against — still cap panning to a generous area around
                // the fallback center rather than leaving it unlimited.
                let ptsPerMeter = MKMapPointsPerMeterAtLatitude(center.latitude)
                let panPad = 200.0 * ptsPerMeter
                let centerPt = MKMapPoint(center)
                let halfSpan = (span / 2) * ptsPerMeter
                let baseRect = MKMapRect(x: centerPt.x - halfSpan, y: centerPt.y - halfSpan,
                                         width: halfSpan * 2, height: halfSpan * 2)
                map.cameraBoundary = MKMapView.CameraBoundary(mapRect: baseRect.insetBy(dx: -panPad, dy: -panPad))
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
        if let at = validAimTarget {
            map.addAnnotation(AimTargetAnnotation(coordinate: at))
        }

        // HARD RULE: lines never run backwards. Any aim point farther from the green than the
        // player is dropped at draw time (belt-and-suspenders on top of activeAimPoints; a
        // stale/late GPS fix could otherwise draw player → tee-side waypoint → green).
        // Capped at 3 — a corrupted override state once produced 10+ criss-crossing lines.
        // Each entry keeps its ORIGINAL activeAimPoints index — the filter can drop earlier
        // points, and drag callbacks must report the original index or overrides land on the
        // wrong waypoint (and the flag-spawned waypoint gets mistaken for a base one).
        // Waypoints draw with OR without a live fix — suppressing them under live GPS made
        // every dogleg render as a straight player→pin line ("the waypoints never showed").
        // The stale-ring/criss-cross fears are already handled by the two HARD RULES below:
        // anything behind the player is dropped, and segments are drawn sorted toward the
        // green — so a live fix simply becomes the first point of the waypoint chain.
        var drawnAim: [(idx: Int, coord: CLLocationCoordinate2D)] =
            aimPoints.enumerated().prefix(3).map { ($0.offset, $0.element) }
        if let u = lineStart, let g = effectiveGreen {
            let startToGreen = MKMapPoint(u).distance(to: MKMapPoint(g))
            drawnAim = drawnAim.filter {
                MKMapPoint($0.coord).distance(to: MKMapPoint(g)) < startToGreen - 5
            }
        }
        // HARD RULE #2: segments always run toward the green. Draw order is by distance to
        // the green (farthest first) regardless of array order, so no state can ever produce
        // backwards / crossing lines.
        if let g = effectiveGreen {
            let gp = MKMapPoint(g)
            drawnAim.sort {
                MKMapPoint($0.coord).distance(to: gp) > MKMapPoint($1.coord).distance(to: gp)
            }
        }
        let drawnAimPoints = drawnAim.map(\.coord)

        // Aim segments (when aim points are active) replace the single HolePathPolyline.
        // For par 3 / straight short holes, aimPoints is empty and we fall back to path line.
        if !drawnAimPoints.isEmpty, let lineStart = userCoord ?? teeCoord, let green = effectiveGreen {
            // Draw segments: lineStart → aim[0] → aim[1] → … → effective green
            let waypoints = [lineStart] + drawnAimPoints + [green]
            // Store in coordinator so drag handler can rebuild lines in real-time.
            context.coordinator.currentAimWaypoints = waypoints
            context.coordinator.currentAimOriginalIndices = drawnAim.map(\.idx)
            for i in 0..<waypoints.count - 1 {
                var pts = [waypoints[i], waypoints[i + 1]]
                map.addOverlay(AimSegmentCasingPolyline(coordinates: &pts, count: 2), level: .aboveLabels)
                map.addOverlay(AimSegmentPolyline(coordinates: &pts, count: 2), level: .aboveLabels)
                // Distance label at segment midpoint
                let mid = Self.midpoint(waypoints[i], waypoints[i + 1])
                let yards = Int((MKMapPoint(waypoints[i]).distance(to: MKMapPoint(waypoints[i + 1])) * 1.09361).rounded())
                map.addAnnotation(SegmentLabelAnnotation(coordinate: mid, yardage: yards))
            }
            // Tee dot — only when there's no live player fix on the hole (the player IS the
            // line origin once GPS is live; the tee marker is just clutter behind them).
            if userCoord == nil, let tee = teeCoord {
                map.addAnnotation(TeeAnnotation(coordinate: tee))
            }
            // Draggable aim-point rings (original indices; flag-spawned renders smaller)
            for entry in drawnAim {
                let a = AimPointAnnotation(coordinate: entry.coord, index: entry.idx)
                a.isFlagSpawned = (entry.idx == flagSpawnedIndex)
                map.addAnnotation(a)
            }
        } else if holePathForOverlay.count >= 2 {
            // Straight line (par 3 or no aim points)
            var pts = holePathForOverlay
            map.addOverlay(HolePathCasingPolyline(coordinates: &pts, count: pts.count), level: .aboveLabels)
            map.addOverlay(HolePathPolyline(coordinates: &pts, count: pts.count), level: .aboveLabels)
            if userCoord == nil, let tee = teeCoord {
                map.addAnnotation(TeeAnnotation(coordinate: tee))
            }
            // Yardage bubble on the direct line too (par 3s / within 240) — same label the
            // aim segments carry, at the midpoint of the start→target line.
            if let s = holePathForOverlay.first, let e = holePathForOverlay.last {
                let yards = Int((MKMapPoint(s).distance(to: MKMapPoint(e)) * 1.09361).rounded())
                if yards > 0 {
                    map.addAnnotation(SegmentLabelAnnotation(coordinate: Self.midpoint(s, e), yardage: yards))
                }
            }
        }

        // Yellow flag at the pin (user-moved position when set, else green center). When the
        // flag has been moved, keep a small dot at the true green center for reference.
        if let green = greenCoord {
            map.addAnnotation(GreenPinAnnotation(coordinate: pinCoord ?? green))
            if pinCoord != nil {
                map.addAnnotation(GreenCenterDotAnnotation(coordinate: green))
            }
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

    /// SwiftUI's actual teardown hook for `UIViewRepresentable` — called when the map is removed
    /// from the hierarchy. Without this, the flight-animation timer could keep firing against a
    /// map that's going away, and nothing ever cleared the delegate/user-location tracking.
    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        coordinator.tearDown()
        uiView.delegate = nil
        uiView.showsUserLocation = false
    }

    // MARK: Coordinator

    class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {

        var parent: SatelliteMapBackground?
        var hasInitializedRegion = false
        // True after a manual pan/zoom/rotate; suspends GPS auto-follow until recenter.
        var userAdjustedCamera = false
        // Heading last set programmatically — used to distinguish rotation from pan.
        var lastProgrammaticHeading: Double = 0
        var lastRenderKey = ""
        private var lastFocusId = ""
        private var lastRecenterToken = -1
        private var lastGpsKey = ""
        private var isProgrammaticRegionChange = false
        // Full waypoints [lineStart, aim[0], …, green] — kept in sync so the drag handler can
        // rebuild segment overlays in real-time without a SwiftUI round-trip.
        var currentAimWaypoints: [CLLocationCoordinate2D] = []
        /// Original activeAimPoints index for each drawn aim point (parallel to the aim
        /// entries inside currentAimWaypoints, which is [start] + aims + [green]).
        var currentAimOriginalIndices: [Int] = []

        // Flight animation state
        var lastFlightId: UUID?
        private var flightTimer: Timer?
        private weak var flightBall: FlightBallAnnotation?
        private weak var flightTrail: FlightTrailPolyline?

        /// Stops the repeating flight-animation timer so it can't keep firing against a map
        /// that's being torn down. Called from `dismantleUIView` and as a deinit backstop.
        func tearDown() {
            flightTimer?.invalidate()
            flightTimer = nil
            parent = nil
        }

        deinit {
            flightTimer?.invalidate()
        }

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

        /// True when this render is framing a hole for the first time (hole switch or fresh
        /// open) — the one case that must show the tee even if the player hasn't reached it
        /// yet. Progressive-follow reframes and mid-hole recenter-arrow taps return false.
        func isHoleSwitch(for focusId: String) -> Bool {
            !hasInitializedRegion || focusId != lastFocusId
        }

        func shouldRecenter(for focusId: String, recenterToken: Int, gpsKey: String) -> Bool {
            // Camera reframes only on hole switch or an explicit recenter tap. The old
            // progressive follow (reframe every ~20yd GPS quantum, zooming toward the green
            // as the player advanced) is gone: the view now frames the full hole tee→green
            // once and stays put while the player dot walks it.
            !hasInitializedRegion || focusId != lastFocusId || recenterToken != lastRecenterToken
        }

        func completeRecenter(focusId: String, recenterToken: Int, gpsKey: String) {
            hasInitializedRegion = true
            lastFocusId = focusId
            lastRecenterToken = recenterToken
            lastGpsKey = gpsKey
            userAdjustedCamera = false
        }

        private var lastProgrammaticChangeAt = Date.distantPast

        func setProgrammaticRegionChange(_ value: Bool) {
            isProgrammaticRegionChange = value
            if value { lastProgrammaticChangeAt = Date() }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // One animated setCamera can fire MULTIPLE regionDidChange callbacks; the boolean
            // flag only absorbs the first. The trailing time window absorbs the rest — without
            // it, hole switches were spuriously flagged as user pans (recenter arrow appearing
            // the moment a hole loads).
            if isProgrammaticRegionChange || Date().timeIntervalSince(lastProgrammaticChangeAt) < 1.0 {
                isProgrammaticRegionChange = false
            } else {
                // User manually panned/zoomed/rotated — stop auto-follow, show recenter button.
                // NOTE: never touch the stretch transform here. SwiftUI sized the frame while the
                // stretch was active (bounds = width / stretch), so dropping to .identity renders
                // the map at ~77% width — white bands on both sides. A slightly stretched rotated
                // map beats a shrunken one.
                userAdjustedCamera = true
                // Async: MapKit can fire a second regionDidChange for one programmatic
                // setCamera (animation begin/end) after the flag was consumed — landing this
                // @State write inside SwiftUI's update pass ("Modifying state during view
                // update" console warnings). Deferring a tick is always safe here.
                DispatchQueue.main.async { [weak self] in
                    self?.parent?.onUserPanned?()
                }
            }
        }

        // Aim-point drag is handled by UIPanGestureRecognizer in AimPointAnnotationView
        // (isDraggable = false). MapKit's didChange dragState is no longer needed.
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState,
                     fromOldState oldState: MKAnnotationView.DragState) {
            // no-op — aim points use their own pan gesture
        _ = newState
        }

        // Swaps only the aim-segment overlays/labels so lines follow the dragged point live.
        // Annotation views (aim rings, tee dot, flag) are untouched to avoid any flicker.
        private func rebuildAimSegments(on mapView: MKMapView,
                                        movingIndex: Int,
                                        to newCoord: CLLocationCoordinate2D,
                                        isDragging: Bool = true) {
            var waypoints = currentAimWaypoints
            // movingIndex is the ORIGINAL activeAimPoints index; map it to the drawn slot
            // (the backwards-filter can drop earlier points, shifting positions).
            guard let pos = currentAimOriginalIndices.firstIndex(of: movingIndex) else { return }
            let wi = pos + 1
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
                // Skip dark casing while dragging — it flashes black before the
                // white renderer fires. Re-added on drag end via the static render.
                if !isDragging {
                    mapView.addOverlay(AimSegmentCasingPolyline(coordinates: &pts, count: 2), level: .aboveLabels)
                }
                mapView.addOverlay(AimSegmentPolyline(coordinates: &pts, count: 2), level: .aboveLabels)
                let mid   = SatelliteMapBackground.midpoint(waypoints[i], waypoints[i + 1])
                let yards = Int((MKMapPoint(waypoints[i]).distance(to: MKMapPoint(waypoints[i + 1])) * 1.09361).rounded())
                mapView.addAnnotation(SegmentLabelAnnotation(coordinate: mid, yardage: yards))
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let dot = overlay as? DispersionDotCircle {
                let r = MKCircleRenderer(circle: dot)
                // Per-dot color (proximity-graded or club identity). Opaque so overlapping dots of
                // different colors never blend into brown; a thin white border keeps them legible.
                r.fillColor   = dot.fill
                r.strokeColor = UIColor.white.withAlphaComponent(0.85)
                r.lineWidth   = 0.5
                return r
            }
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

            // Read the live transform so annotation views auto-correct for the current stretch.
            let invStretch = CGAffineTransform(scaleX: 1.0 / mapView.transform.a, y: 1.0)

            if let pin = annotation as? GreenPinAnnotation {
                let id = "greenPin"
                let v  = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                            as? DraggableFlagAnnotationView
                            ?? DraggableFlagAnnotationView(annotation: pin, reuseIdentifier: id)
                v.annotation      = pin
                v.mapView         = mapView
                v.displayPriority = .required
                v.transform       = invStretch
                v.greenCenter     = parent?.greenCoord
                v.onDragEnded     = { [weak self] coord in
                    self?.parent?.onPinMoved?(coord)
                }
                return v
            }

            if annotation is GreenCenterDotAnnotation {
                let id = "greenCenterDot"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.displayPriority = .required
                v.isUserInteractionEnabled = false
                if v.subviews.isEmpty {
                    v.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
                    let dot = UIView(frame: v.bounds)
                    dot.backgroundColor = UIColor.white.withAlphaComponent(0.9)
                    dot.layer.cornerRadius = 5
                    dot.layer.borderColor = UIColor.black.withAlphaComponent(0.5).cgColor
                    dot.layer.borderWidth = 1
                    dot.isUserInteractionEnabled = false
                    v.addSubview(dot)
                }
                v.transform = invStretch
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
                v.annotation     = aim
                v.mapView        = mapView
                v.displayPriority = .required
                v.transform      = invStretch
                v.onDragChanged  = { [weak self, weak mapView] idx, coord in
                    guard let self, let map = mapView else { return }
                    self.rebuildAimSegments(on: map, movingIndex: idx, to: coord)
                }
                v.onDragEnded    = { [weak self] idx, coord in
                    // Persist override in SwiftUI and update stored waypoints.
                    self?.parent?.onAimPointMoved?(idx, coord)
                }
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
    @ObservedObject private var nfcManager = NFCManager.shared
    @StateObject private var elevation = ElevationService()
    @StateObject private var wind = WindService()
    @State private var windEnabled = false     // show live wind + plays-like adjustment

    // Club suggestion (Pro/Unlimited)
    @State private var showCaddie = false
    @State private var caddieLoading = false
    @State private var caddieResult: CaddieEngine.Suggestion?
    @State private var caddiePlan: CourseManagementEngine.Plan?
    @State private var caddieMessage: String?

    @State private var clubs: [UserClub] = []
    @State private var showCamera      = false
    @State private var showScoreEntry  = false
    @State private var showScorecard   = false
    @State private var showFinalScorecard = false
    @State private var showFinishAlert = false
    @State private var showDeleteRoundConfirm = false
    @State private var showLeaveDialog = false
    // In-round logged-shots editor (opened by tapping a hole on the scorecard).
    @State private var editingShotsHole: Int?

    private struct EditingShotsHole: Identifiable {
        let number: Int
        var id: Int { number }
    }
    @State private var gpsOn           = true
    @State private var dispersionClubIds: [UUID] = []          // empty = overlay off; multiple = multi-club
    @State private var dispersionShotsByClub: [UUID: [SavedShot]] = [:]
    @State private var showDispersionPicker = false
    @State private var slopeAdjustDots = false     // shift dispersion dots by slope (plays-like)
    @State private var dispersionMetric: DispersionMetric = .carry   // plot dots at carry or total
    @State private var dispersionSource: DispersionShotSource = .all // all / range+sim / on-course shots
    /// Aggressive per-club outlier trim (median±band) so the overlay shows the NORMAL number.
    /// Off = every shot, chunks and all.
    @State private var dispersionExcludeOutliers = true
    @State private var infoMessage: String?
    @State private var roundStartTime  = Date()
    @State private var recenterToken   = 0
    @State private var showRecenter    = false    // true after user pans away
    @State private var showLandingConfirm = false
    // Aim-point drag overrides: key = aim point index, value = dragged position
    @State private var userAimPointOverrides: [Int: CLLocationCoordinate2D] = [:]
    // Custom tap-to-aim target (within 225 yd of green)
    @State private var aimTarget: CLLocationCoordinate2D?
    // User-moved flag position (≤15 yd from green center); nil = flag at center.
    @State private var pinOverride: CLLocationCoordinate2D?
    // Waypoint spawned by dragging the flag beyond 15 yd while within 240 of the green —
    // the one allowed exception to the "never more waypoints than the hole started with" cap.
    @State private var flagWaypoint: CLLocationCoordinate2D?
    // Shot tracker (replaces the old GPS on/off rail button)
    @State private var showShotLogSheet = false
    @State private var showStationaryPrompt = false
    @State private var lastStationaryCheckCoord: CLLocationCoordinate2D?
    @State private var stationarySince: Date?
    @State private var loggedShotCoords: [CLLocationCoordinate2D] = []
    // Hazard hit counts per polygon: "bunker_0", "water_1", etc. (0→1→2→3→0)
    @State private var hazardCounts: [String: Int] = [:]
    // HUD flight animation state
    @State private var flightRequest: FlightRequest?
    @State private var pendingFlight: FlightRequest?     // held until camera cover dismisses
    @State private var flightStart: Coordinate?
    @State private var flightShot: SavedShot?
    // Fixed 1s heartbeat for the widget / Live Activity: GPS yardages must tick on the lock
    // screen without any user interaction, so pushes can't ride on SwiftUI onChange alone
    // (which stops firing the moment the app isn't foreground-active). Dedupe in
    // pushWidgetData keeps the once-a-second tick from spamming identical writes.
    private let widgetHeartbeat = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var lastWidgetPushKey = ""

    // Ghost match — persists across app restarts via GhostPersistence
    @State private var ghostRound: CourseRound?
    @State private var ghostCandidates: [CourseRound] = []
    @State private var showGhostPicker = false
    @State private var ghostOfferDismissed = false

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

    /// Returns existing score, or the smart-scored estimate, or nil (→ ScoreEntryView defaults to par).
    private func scoreEntryInitialScore(for hole: RoundHole) -> Int? {
        if let existing = hole.score { return existing }
        return vm.inferredStrokes(forHole: hole.holeNumber)
    }

    /// Returns existing putts, or the smart-scored putts estimate, or nil (→ ScoreEntryView defaults to 2).
    private func scoreEntryInitialPutts(for hole: RoundHole) -> Int? {
        if let existing = hole.putts { return existing }
        return vm.smartScore(forHole: hole.holeNumber).putts
    }

    /// Tee club from the hole's first non-putter NFC tap (chronological).
    private func teeClubName(for hole: RoundHole) -> String? {
        (vm.activeRound?.nfcShots ?? [])
            .filter { $0.holeNumber == hole.holeNumber }
            .sorted { $0.tappedAt < $1.tappedAt }
            .first(where: { !$0.clubName.lowercased().contains("putter") })?.clubName
    }

    /// First-putt distance (feet) from the hole's first putter tap's distance-to-pin.
    private func firstPuttFeet(for hole: RoundHole) -> Int? {
        let taps = (vm.activeRound?.nfcShots ?? [])
            .filter { $0.holeNumber == hole.holeNumber }
            .sorted { $0.tappedAt < $1.tappedAt }
        guard let putt = taps.first(where: { $0.clubName.lowercased().contains("putter") }),
              let yds = putt.distanceToPinYards else { return nil }
        return max(0, Int((yds * 3.0).rounded()))   // yards → feet
    }

    /// Called when an NFC club tag is tapped; records shot and fires haptic silently.
    private func handleNFCClubTap() {
        guard let clubId = NFCManager.shared.lastScannedClubId,
              let club = clubs.first(where: { $0.id == clubId }) else { return }
        vm.recordNFCShot(club: club)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private var scorecardYardage: Int? {
        guard let gh = currentCourseHole, let course = vm.selectedCourse else { return nil }
        guard let tee = vm.selectedTeeBox else {
            return gh.teeYardsByTeeBox.values.first(where: { $0 > 0 })
        }
        // Match by selected tee box id/name, else step down to the nearest shorter tee with
        // trusted data (GPS-estimate tees don't carry reliable per-hole numbers of their own),
        // else fall back to any available yardage as a last resort.
        return course.resolvedHoleYardage(gh, for: tee)
            ?? gh.teeYardsByTeeBox.values.first(where: { $0 > 0 })
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
        // Threshold = hole yardage + 100y buffer, so GPS activates from the tee box.
        let holeYards = Double(scorecardYardage ?? Int((Self.metersBetween(
            currentMapHole?.teeCoordinate?.clCoordinate ?? center, center) * 1.09361).rounded()))
        let thresholdMeters = (holeYards + 100) / 1.09361
        return Self.metersBetween(user, center) < thresholdMeters
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

    // MARK: - Slope-adjusted distances (#6)

    /// "Plays-like" distance = sqrt(horizontal² + vertical²), where horizontal is
    /// the live player→target yardage and vertical is the interpolated elevation
    /// change (yards). Only meaningful with live GPS (player position + the same
    /// reference for horizontal and elevation), so it's gated on that.
    private var slopeDistances: SlopeReadout {
        _ = elevation.revision   // recompute when a new grid loads
        // Mirror the left pill: show whenever distances are available (live GPS or
        // estimated from the tee), using the matching reference point for elevation.
        let d = mapDistances
        guard d.isAvailable, let gh = currentMapHole ?? currentCourseHole else { return SlopeReadout() }
        // Reference point for the elevation delta: your live position if we have a
        // fix at all, otherwise the tee, otherwise the green itself (slope ≈ flat).
        // Only trust the live GPS when you're actually on the hole; otherwise the
        // sim/off-course location poisons the elevation delta. Fall back to the tee.
        let reference = (userIsNearCurrentHole ? vm.location.currentLocation : nil)
            ?? gh.teeCoordinate?.clCoordinate
            ?? gh.greenCenterCoordinate?.clCoordinate
        // Direction of play — used to sample tree-filtered elevations PERPENDICULAR to the
        // shot line (the fairway corridor is clear; one side or the other is often trees).
        // Base waypoints only: a flag-spawned waypoint must not rotate the probe direction
        // (moving it was visibly changing plays-like on par 3s).
        let playTarget = baseActiveAimPoints.first ?? gh.greenCenterCoordinate?.clCoordinate
        let playBearing = (reference != nil && playTarget != nil)
            ? reference!.bearing(to: playTarget!) : 0
        guard let ref = reference,
              let refElev = treeFilteredElevation(at: ref, playBearingDeg: playBearing) else { return SlopeReadout() }

        func slope(_ coord: Coordinate?, _ horiz: Int?) -> Int? {
            guard let coord, let horiz,
                  let targetElev = treeFilteredElevation(at: coord.clCoordinate, playBearingDeg: playBearing) else { return nil }
            // Plays-like = horizontal + (target elevation − your elevation).
            // Uphill (target higher) plays longer (+); if you're above it, shorter (−).
            let vertYds = (targetElev - refElev) * ElevationService.yardsPerMeter
            return max(0, Int((Double(horiz) + vertYds).rounded()))
        }
        let vert = gh.greenCenterCoordinate.flatMap { c -> Int? in
            treeFilteredElevation(at: c.clCoordinate, playBearingDeg: playBearing).map {
                Int((($0 - refElev) * ElevationService.yardsPerMeter).rounded())
            }
        }
        return SlopeReadout(
            front:  slope(gh.greenFrontCoordinate,  d.front),
            center: slope(gh.greenCenterCoordinate, d.center),
            back:   slope(gh.greenBackCoordinate,   d.back),
            verticalYards: vert
        )
    }

    /// Elevation with tree-canopy rejection. Surface-model grids read the TOP of tree cover,
    /// so a point under/near trees can read 6m+ high. Sample the point plus two probes ±8m
    /// PERPENDICULAR to the direction of play (the shot corridor is clear ground; trees sit
    /// to one side, not both) — if the spread exceeds 6m, the high readings are canopy and
    /// the LOWEST sample is the ground.
    private func treeFilteredElevation(at coord: CLLocationCoordinate2D, playBearingDeg: Double) -> Double? {
        guard let center = elevation.elevation(at: coord) else { return nil }
        let leftCoord  = coord.projected(yardsForward: 0, yardsRight: -8.75, bearingDeg: playBearingDeg)  // ~8m
        let rightCoord = coord.projected(yardsForward: 0, yardsRight:  8.75, bearingDeg: playBearingDeg)
        let sides = [elevation.elevation(at: leftCoord), elevation.elevation(at: rightCoord)].compactMap { $0 }
        guard !sides.isEmpty else { return center }
        let all = [center] + sides
        let spread = all.max()! - all.min()!
        // Canopy only ever ADDS height — when the samples disagree badly, ground = minimum.
        return spread >= 6 ? all.min()! : center
    }

    // MARK: - Wind (#2, WeatherKit)

    /// Player reference position for wind/aim (live GPS on the hole, else tee, else green).
    private var windReference: CLLocationCoordinate2D? {
        let gh = currentMapHole ?? currentCourseHole
        return (userIsNearCurrentHole ? vm.location.currentLocation : nil)
            ?? gh?.teeCoordinate?.clCoordinate
            ?? gh?.greenCenterCoordinate?.clCoordinate
    }

    /// (speed, from-degrees) applied to dispersion dots / arrows when wind mode is on.
    private var windDotEffect: (speedMph: Double, fromDegrees: Double)? {
        guard windEnabled, let r = wind.reading, r.speedMph > 0 else { return nil }
        return (r.speedMph, r.fromDegrees)
    }

    /// Compass heading the map is rotated to (tee→green runs bottom-to-top), so screen-up = this
    /// bearing. Used to orient the wind arrows to what the player actually sees, not true north.
    private var mapHeading: Double {
        let gh = currentMapHole ?? currentCourseHole
        let path = currentHolePathCoordinates
        let start = gh?.teeCoordinate?.clCoordinate ?? path.first
        let end   = path.last ?? gh?.greenCenterCoordinate?.clCoordinate
        guard let start, let end else { return 0 }
        return start.bearing(to: end)
    }

    private func refreshWind(force: Bool = false) {
        guard let ref = windReference else { return }
        Task { await wind.fetch(at: ref, force: force) }
    }

    // MARK: - Club suggestion (#3, Pro/Unlimited)

    private func openCaddie() {
        caddieResult = nil
        caddiePlan = nil
        caddieMessage = nil
        caddieLoading = true
        showCaddie = true
        Task { await computeCaddie() }
    }

    @MainActor
    private func computeCaddie() async {
        defer { caddieLoading = false }
        guard let uid = session.currentUser?.id,
              let gh = currentMapHole ?? currentCourseHole,
              let green = gh.greenCenterCoordinate?.clCoordinate,
              let ref = windReference,
              let baseYards = mapDistances.center else {
            caddieMessage = "No green distance yet — get a GPS fix on the hole first."
            return
        }

        // Best-effort live wind so the suggestion factors it in (no-op if WeatherKit isn't provisioned).
        await wind.fetch(at: ref)
        let bearing = ref.bearing(to: green)

        // Slope: slopeDistances.center already folds in the plays-like elevation change.
        let slopeDelta = slopeDistances.center.map { $0 - baseYards } ?? 0

        var windDelta = 0
        var aimAdvice = ""
        var windSummary = ""
        if let r = wind.reading {
            let eff = WindModel.effect(distanceYards: Double(baseYards),
                                       shotBearingDegrees: bearing,
                                       windSpeedMph: r.speedMph,
                                       windFromDegrees: r.fromDegrees,
                                       profile: .mid)
            windDelta = eff.playsLikeYards - baseYards
            aimAdvice = eff.aimAdvice
            let rel = WindModel.relativeLabel(headwindMph: eff.headwindMph, crosswindMph: eff.crosswindMph)
            windSummary = "\(Int(r.speedMph.rounded())) mph \(rel)"
        }

        let playing = Double(baseYards + slopeDelta + windDelta)

        // Green depth from the front↔back coords; width uses a sensible default.
        let greenDepth: Double = {
            if let f = gh.greenFrontCoordinate?.clCoordinate, let b = gh.greenBackCoordinate?.clCoordinate {
                return Self.metersBetween(f, b) * ElevationService.yardsPerMeter
            }
            return 16
        }()

        let data = await loadCaddieData(uid: uid)
        guard !data.stats.isEmpty else {
            caddieMessage = "Not enough tracked shots yet — log a few with each club to unlock suggestions."
            return
        }

        // Live position drives hazards and the off-line note; the tee stands in when planning.
        let liveCoord = userIsNearCurrentHole ? vm.location.currentLocation : nil
        let origin = liveCoord ?? gh.teeCoordinate?.clCoordinate

        var input = CourseManagementEngine.Input(
            playingYards: playing, baseYards: baseYards,
            slopeDelta: slopeDelta, windDelta: windDelta,
            greenDepthYards: greenDepth, greenWidthYards: 18,
            aimAdvice: aimAdvice, windSummary: windSummary,
            clubs: data.stats)
        input.origin = origin
        input.green = green
        input.centerline = currentHolePathCoordinates
        input.bunkers = gh.bunkerPolygons.map(\.clCoordinates)
        input.waters = gh.waterPolygons.map(\.clCoordinates)
        input.approach = data.approach
        input.avgPutts = data.avgPutts
        input.courseSamples = data.courseSamples
        input.totalSamples = data.totalSamples
        input.originIsLive = liveCoord != nil

        if let plan = CourseManagementEngine.plan(input) {
            caddiePlan = plan
            caddieResult = plan.suggestion
            if plan.suggestion.isLayup {
                caddieMessage = "No club holds the green from \(Int(playing.rounded())) yds — smart advance instead."
            }
        } else {
            caddieMessage = "Not a green-light shot — no club in your bag holds the green from \(Int(playing.rounded())) yds. Play for position."
        }
    }

    private struct CaddieData {
        var stats: [CaddieEngine.ClubStat] = []
        var approach: CourseManagementEngine.ApproachSuccessModel?
        var avgPutts: Double?
        var courseSamples = 0
        var totalSamples = 0
    }

    /// Per-club (carry, lateral, total) distributions from EVERYTHING the golfer has hit —
    /// launch-monitor captures plus verified on-course GPS shots — each club aggressively
    /// outlier-trimmed so a chunked 120 never drags a 180 club's number. Also learns their
    /// real approach-success curve and putts-per-hole from round history.
    private func loadCaddieData(uid: UUID) async -> CaddieData {
        var data = CaddieData()
        let svc = ShotPersistenceService(userId: uid, backend: session.backend)
        let all = (try? await svc.loadShots(limit: 600)) ?? []
        var byClub: [String: [CaddieEngine.ShotSample]] = [:]
        for shot in all where !shot.isBadShot {
            guard let p = ShotDispersion.point(for: shot) else { continue }
            let key = shot.clubName ?? shot.clubId?.uuidString ?? "Unknown"
            let total = shot.metrics.totalYards > 0 ? shot.metrics.totalYards : nil
            byClub[key, default: []].append(
                CaddieEngine.ShotSample(carry: p.carry, lateral: p.lateral, total: total))
        }

        // Verified on-course shots: real GPS distance + lateral, plus the golfer's actual
        // green-hit rate by distance and their putts per scored hole.
        var approachBuckets: [Int: (hits: Int, n: Int)] = [:]
        var puttsTotal = 0, puttsHoles = 0
        let rounds = (try? await session.backend.loadCourseRounds(userId: uid)) ?? []
        for round in rounds {
            let course = OSMGolfService.shared.loadCached(courseId: round.courseId)
            for h in round.holes {
                if let p = h.putts { puttsTotal += p; puttsHoles += 1 }
            }
            for vs in RoundShotVerifier.verifiedShots(round: round, course: course) {
                guard let hole = course?.holes.first(where: { $0.number == vs.holeNumber }),
                      let greenCL = hole.greenCenterCoordinate?.clCoordinate else { continue }
                let fromYds = vs.start.yards(to: greenCL)
                let endYds  = vs.end.yards(to: greenCL)
                if fromYds > 30 {
                    var b = approachBuckets[Int(fromYds / 25)] ?? (0, 0)
                    b.n += 1
                    if endYds <= 14 { b.hits += 1 }
                    approachBuckets[Int(fromYds / 25)] = b
                }
                if let name = vs.clubName, !name.lowercased().contains("putt"),
                   vs.distanceYards > 25 {
                    byClub[name, default: []].append(CaddieEngine.ShotSample(
                        carry: vs.distanceYards, lateral: vs.lateralYards,
                        total: vs.distanceYards))
                    data.courseSamples += 1
                }
            }
        }

        data.stats = byClub.compactMap { name, samples in
            let kept = ClubDistanceModel.trim(samples)
            data.totalSamples += kept.count
            return CaddieEngine.stat(name: name, shots: kept)
        }
        data.approach = CourseManagementEngine.ApproachSuccessModel(buckets: approachBuckets)
        data.avgPutts = puttsHoles > 0 ? Double(puttsTotal) / Double(puttsHoles) : nil
        return data
    }

    // MARK: - Dispersion overlay (#7)

    /// Projected landing dots for the chosen dispersion club. The "zero line" runs
    /// from where you're hitting (live GPS on the hole, else the tee) toward what
    /// you're actually aiming at: a custom tap target, else the next fairway
    /// waypoint ahead (activeAimPoints already filters to points ahead of you and
    /// is empty on par 3s / near the green), else the green. Each shot is offset
    /// by its lateral miss; large misses are flagged for the red coloring.
    private var dispersionDots: [DispersionDot] {
        guard !dispersionClubIds.isEmpty else { return [] }
        _ = elevation.revision   // recompute when a new elevation grid loads (slope mode)
        let gh = currentMapHole ?? currentCourseHole
        let greenCenter = gh?.greenCenterCoordinate?.clCoordinate
        let target = aimTarget
            ?? activeAimPoints.first
            ?? greenCenter
            ?? gh?.greenFrontCoordinate?.clCoordinate
        // Use live GPS only when on the hole; else project from the tee so the
        // pattern lands on the visible hole (not off-screen from a far sim fix).
        let origin = (userIsNearCurrentHole ? vm.location.currentLocation : nil)
            ?? gh?.teeCoordinate?.clCoordinate
            ?? gh?.greenFrontCoordinate?.clCoordinate
        guard let target, let origin else { return [] }
        let bearing = origin.bearing(to: target)
        // Slope mode: shift each landing point along the aim line by the net elevation change to
        // where it lands — uphill plays shorter (dot pulls in), downhill plays longer (dot pushes
        // out). Falls back to the flat landing point when no elevation grid is available.
        let originElev = slopeAdjustDots ? elevation.elevation(at: origin) : nil

        // Single-club approaches (≤220 yd to the green) and par 3s grade each dot by how close it
        // lands to the green center. With 2+ clubs we instead color by club so you can tell them
        // apart. Proximity is measured from the *final* (slope-adjusted) coord, so the colors shift
        // correctly when slope mode is toggled.
        let isPar3 = (gh?.par ?? 4) == 3
        let yardsToGreen = greenCenter.map { origin.yards(to: $0) } ?? .greatestFiniteMagnitude
        let multiClub = dispersionClubIds.count > 1
        let useProximity = !multiClub && (isPar3 || yardsToGreen <= 220)

        var dots: [DispersionDot] = []
        for (selectionIndex, clubId) in dispersionClubIds.enumerated() {
            // Club identity color is keyed by selection order, so it matches the selector and is
            // only meaningful when several clubs are overlaid at once.
            let clubColor = UIColor(TCDispersionColor.club(selectionIndex))
            // Aggressive per-club outlier trim (on the plotted distance) when "normal shots
            // only" is on — a chunked 120 among 180s shouldn't shape the pattern you aim with.
            var points = (dispersionShotsByClub[clubId] ?? []).compactMap {
                ShotDispersion.point(for: $0, metric: dispersionMetric)
            }
            if dispersionExcludeOutliers {
                let keep = Set(ClubDistanceModel.keptIndices(distances: points.map(\.carry)))
                points = points.enumerated().filter { keep.contains($0.offset) }.map(\.element)
            }
            for p in points {
                var carry = p.carry
                var lateral = p.lateral
                if let originElev {
                    let flat = origin.projected(yardsForward: p.carry, yardsRight: p.lateral, bearingDeg: bearing)
                    if let landElev = elevation.elevation(at: flat) {
                        let vertYds = (landElev - originElev) * ElevationService.yardsPerMeter
                        carry = max(1, p.carry - vertYds)   // uphill (+vert) → shorter; downhill (−) → longer
                    }
                }
                // Wind mode: blow each shot as it would actually fly — headwind pulls the carry in,
                // tailwind pushes it out, crosswind drifts it sideways.
                if let we = windDotEffect {
                    let eff = WindModel.effect(distanceYards: carry,
                                               shotBearingDegrees: bearing,
                                               windSpeedMph: we.speedMph,
                                               windFromDegrees: we.fromDegrees,
                                               profile: .mid)
                    carry = max(1, carry + Double(eff.carryDeltaYards))
                    lateral += Double(eff.lateralDriftYards)
                }
                let coord = origin.projected(yardsForward: carry, yardsRight: lateral, bearingDeg: bearing)
                let fill: UIColor
                if multiClub {
                    fill = clubColor
                } else if useProximity, let greenCenter {
                    fill = UIColor(TCDispersionColor.byGreenProximity(coord.yards(to: greenCenter)))
                } else {
                    fill = UIColor(TCDispersionColor.byLateral(abs(lateral)))
                }
                dots.append(DispersionDot(coord: coord, fill: fill))
            }
        }
        return dots
    }

    /// Toggle a club in/out of the dispersion overlay (multi-select).
    private func toggleDispersionClub(_ club: UserClub) {
        if let idx = dispersionClubIds.firstIndex(of: club.id) {
            dispersionClubIds.remove(at: idx)
            dispersionShotsByClub[club.id] = nil
        } else {
            dispersionClubIds.append(club.id)
            loadDispersionShots(clubId: club.id, clubName: club.name)
        }
    }

    /// Loads a club's past shots to project on the course (stored per club for multi-club overlay).
    private func loadDispersionShots(clubId: UUID, clubName: String?) {
        guard let uid = session.currentUser?.id else { return }
        let source = dispersionSource
        Task {
            let svc = ShotPersistenceService(userId: uid, backend: session.backend)
            let all = (try? await svc.loadShots(limit: 600)) ?? []
            let filtered = all.filter { s in
                s.clubId == clubId || (clubName != nil && s.clubName == clubName)
            }.filter { $0.metrics.carryYards > 0 && !$0.isBadShot }
            .filter { source.includes($0) }
            await MainActor.run { dispersionShotsByClub[clubId] = filtered }
        }
    }

    /// Re-pulls every selected club's shots — used when the source filter changes.
    private func reloadDispersionShots() {
        for id in dispersionClubIds {
            loadDispersionShots(clubId: id, clubName: clubs.first { $0.id == id }?.name)
        }
    }

    /// Pulls one elevation grid for the current hole (tee, green edges, player).
    private func loadElevationForHole() {
        guard let gh = currentMapHole ?? currentCourseHole else { return }
        var coords: [CLLocationCoordinate2D] = []
        [gh.teeCoordinate, gh.greenCenterCoordinate, gh.greenFrontCoordinate, gh.greenBackCoordinate]
            .compactMap { $0?.clCoordinate }.forEach { coords.append($0) }
        // Only widen the grid to the player when they're actually on the hole;
        // a far sim/off-course fix would make the grid span huge distances and
        // wreck the interpolation (flat holes showing 100+ yd of "slope").
        if userIsNearCurrentHole, let u = vm.location.currentLocation { coords.append(u) }
        guard !coords.isEmpty else { return }
        Task { await elevation.loadGrid(around: coords) }
    }

    private var displayYardage: Int? {
        if gpsOn, userIsNearCurrentHole, let gps = gpsDistances.center { return gps }
        return scorecardYardage
    }

    private var currentHolePathCoordinates: [CLLocationCoordinate2D] {
        if let tee = currentMapHole?.teeCoordinate?.clCoordinate,
           let green = currentMapHole?.greenCenterCoordinate?.clCoordinate {
            if let coords = currentMapHole?.pathCoordinates, coords.count >= 1 {
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

    /// Merges default aim points with any user-dragged overrides, then filters
    /// for the user's current position:
    /// - Drops any aim point that is behind the user (user is closer to the green)
    /// - Drops all aim points when user is within 225 yards of the green
    private var activeAimPoints: [CLLocationCoordinate2D] {
        var base = baseActiveAimPoints
        // Flag-spawned waypoint (drag beyond 15yd while inside 240) is the single allowed
        // addition beyond the hole's starting waypoint count.
        if let fw = flagWaypoint { base.append(fw) }
        return base
    }

    private var baseActiveAimPoints: [CLLocationCoordinate2D] {
        // HARD CAP: never more waypoints than the hole started with (stale overrides once
        // produced 10+ lines fanning in every direction).
        let pts = suggestedAimPoints.enumerated().map { i, def in
            userAimPointOverrides[i] ?? def
        }.prefix(suggestedAimPoints.count).map { $0 }
        guard let green = currentMapHole?.greenCenterCoordinate?.clCoordinate else { return pts }

        // When we have a live GPS position, filter aim points relative to the user.
        if let user = vm.location.currentLocation, userIsNearCurrentHole {
            let userToGreen = Self.metersBetween(user, green) * 1.09361
            // User is within 225 yards — show a direct line, no aim points.
            if userToGreen <= 240 { return [] }
            // Keep only aim points that are ahead of the user (closer to green than user).
            let ahead = pts.filter { ap in
                Self.metersBetween(ap, green) < Self.metersBetween(user, green)
            }
            if ahead.count >= 2 {
                // Par-5: if user is within 225y of aim[1], skip aim[0] — jump straight to aim[1].
                let userToAim1 = Self.metersBetween(user, ahead[1]) * 1.09361
                if userToAim1 <= 240 { return [ahead[1]] }
                // Par-5 collapse: if aim[0] is within 225y of green, drop it too.
                let aim0ToGreen = Self.metersBetween(ahead[0], green) * 1.09361
                if aim0ToGreen <= 240 { return [ahead[0]] }
            }
            return ahead
        }

        // No live GPS — apply the original par-5 collapse only.
        if pts.count >= 2 {
            let yardsToGreen = Self.metersBetween(pts[0], green) * 1.09361
            if yardsToGreen <= 240 { return [pts[0]] }
        }
        return pts
    }

    /// Flag ↔ waypoint boundary: within this many yards of the green center a drag moves the
    /// FLAG; beyond it the drag becomes a waypoint. The two can never coexist closer than this.
    static let kFlagWaypointBoundaryYds = 30.0
    /// Two waypoints can never sit closer than this — a new placement inside the ring moves
    /// the existing waypoint there instead, and drags clamp away from their nearest neighbor.
    static let kWaypointMinSeparationYds = 30.0

    private func handlePinMoved(_ coord: CLLocationCoordinate2D) {
        guard let green = currentMapHole?.greenCenterCoordinate?.clCoordinate else { return }
        let yards = Self.metersBetween(coord, green) * 1.09361
        if yards <= 5 {
            pinOverride = nil   // close enough — snap home to the center point
        } else if yards <= Self.kFlagWaypointBoundaryYds {
            // FLAG PRIORITY: a valid flag placement always wins. Any waypoint inside the
            // 30y separation yields to the flag instead of blocking it — so a validly
            // moved flag ALWAYS gets the line (never a waypoint line into the center).
            pinOverride = coord
            resolveWaypointConflicts(withFlagAt: coord)
        } else {
            // Dragged clear off the green (>30y): this becomes a waypoint, flag snaps home.
            pinOverride = nil
            placeFlagSpawnedWaypoint(at: coord, green: green)
        }
    }

    /// Flag priority: any waypoint within 30y of a newly-placed flag yields. Base waypoints
    /// go back to their ORIGINAL suggested spot (discarding prior user moves; clamped to the
    /// 30y ring if even home conflicts); the flag-spawned waypoint has no home — it's removed.
    private func resolveWaypointConflicts(withFlagAt flag: CLLocationCoordinate2D) {
        if let fw = flagWaypoint,
           Self.metersBetween(fw, flag) * 1.09361 < Self.kWaypointMinSeparationYds {
            flagWaypoint = nil
        }
        for i in suggestedAimPoints.indices {
            let eff = userAimPointOverrides[i] ?? suggestedAimPoints[i]
            guard Self.metersBetween(eff, flag) * 1.09361 < Self.kWaypointMinSeparationYds else { continue }
            let home = suggestedAimPoints[i]
            if Self.metersBetween(home, flag) * 1.09361 < Self.kWaypointMinSeparationYds {
                userAimPointOverrides[i] = flag.projected(
                    yardsForward: Self.kWaypointMinSeparationYds,
                    yardsRight: 0,
                    bearingDeg: flag.bearing(to: home))
            } else {
                userAimPointOverrides[i] = nil   // back to the original spot
            }
        }
    }

    /// Waypoint-from-flag placement with merge rules:
    ///  • within 30y of an existing waypoint, or BEHIND one (farther from the green than it),
    ///    don't add a second waypoint — move that existing waypoint to the drop point instead.
    ///  • otherwise it becomes the flag-spawned waypoint (the one cap exception).
    private func placeFlagSpawnedWaypoint(at coord: CLLocationCoordinate2D, green: CLLocationCoordinate2D) {
        var c = coord
        // Keep 30y clear of the flag itself when the flag sits off center.
        if let pin = pinOverride,
           Self.metersBetween(c, pin) * 1.09361 < Self.kWaypointMinSeparationYds {
            c = pin.projected(yardsForward: Self.kWaypointMinSeparationYds,
                              yardsRight: 0,
                              bearingDeg: pin.bearing(to: c))
        }
        let dropToGreen = Self.metersBetween(c, green)
        for wp in baseActiveAimPoints {
            let nearExisting   = Self.metersBetween(c, wp) * 1.09361 <= Self.kWaypointMinSeparationYds
            let behindExisting = dropToGreen > Self.metersBetween(wp, green)
            guard nearExisting || behindExisting else { continue }
            // baseActiveAimPoints is a filtered view — resolve wp back to its original
            // suggested-index so the override lands on the right waypoint.
            if let orig = suggestedAimPoints.indices.first(where: {
                let eff = userAimPointOverrides[$0] ?? suggestedAimPoints[$0]
                return Self.metersBetween(eff, wp) < 0.5
            }) {
                // The relocated waypoint must keep 30y from the OTHER waypoints too.
                var target = c
                for other in baseActiveAimPoints where Self.metersBetween(other, wp) > 0.5 {
                    if Self.metersBetween(target, other) * 1.09361 < Self.kWaypointMinSeparationYds {
                        target = other.projected(yardsForward: Self.kWaypointMinSeparationYds,
                                                 yardsRight: 0,
                                                 bearingDeg: other.bearing(to: target))
                    }
                }
                userAimPointOverrides[orig] = target
                flagWaypoint = nil
                return
            }
        }
        flagWaypoint = c
    }

    // MARK: - Stationary shot prompt

    /// Player has held position ~20s without logging a shot near here → surface the shot
    /// tracker. Never auto-inputs: dismissing (or ignoring) the banner records nothing.
    private func evaluateStationaryPrompt() {
        guard vm.roundActive, userIsNearCurrentHole,
              let loc = vm.location.currentLocation else {
            stationarySince = nil
            return
        }
        if let last = lastStationaryCheckCoord, Self.metersBetween(last, loc) < 8 {
            if stationarySince == nil { stationarySince = Date() }
        } else {
            stationarySince = nil
            if showStationaryPrompt { withAnimation { showStationaryPrompt = false } }
        }
        lastStationaryCheckCoord = loc

        guard let since = stationarySince, Date().timeIntervalSince(since) >= 20 else { return }
        let alreadyLoggedNearby = loggedShotCoords.contains { Self.metersBetween($0, loc) < 25 }
        let holeNum = vm.currentHole?.holeNumber ?? 0
        if !alreadyLoggedNearby,
           !vm.hasManualOrigin(nearCurrentPositionForHole: holeNum),
           !showShotLogSheet, !showStationaryPrompt, !showScoreEntry, !showCamera, !showFinalScorecard {
            withAnimation(.spring(response: 0.35)) { showStationaryPrompt = true }
        }
    }

    private var stationaryPromptBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.golf.circle.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(HUDStyle.pin)
            VStack(alignment: .leading, spacing: 1) {
                Text("Hitting from here?")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Tap to log your club — GPS marks this spot.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            Button {
                withAnimation { showStationaryPrompt = false }
                // Remember the dismissal spot so we don't re-prompt until they move on.
                if let loc = vm.location.currentLocation { loggedShotCoords.append(loc) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .hudGlass(22)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation { showStationaryPrompt = false }
            showShotLogSheet = true
        }
    }

    /// One-tap escape hatch: wipe every waypoint/pin customization and re-apply the standard
    /// True Carry rules from the player's current position (used when overrides get tangled).
    private func resetWaypointsAndRecenter() {
        userAimPointOverrides = [:]
        aimTarget = nil
        pinOverride = nil
        flagWaypoint = nil
        recenterToken += 1
        withAnimation(.spring(response: 0.3)) { showRecenter = false }
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
        return gh.strokeIndex(for: session.userProfile?.gender) ?? 9
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

    /// GPS rounded to ~20 yd resolution. Changes here trigger a camera reframe (GPS→green
    /// progressive zoom-in as the player walks the hole).
    private var coarseGpsKey: String {
        guard gpsOn, userIsNearCurrentHole,
              let loc = vm.location.currentLocation else { return "" }
        let lat = (loc.latitude  / 0.0002).rounded() * 0.0002
        let lon = (loc.longitude / 0.0002).rounded() * 0.0002
        return "\(lat),\(lon)"
    }

    /// GPS rounded to ~3 m — redraws aim lines/labels continuously as the player walks,
    /// without waiting for the coarser camera quantum. This is what makes lines/yardages
    /// live instead of requiring a GPS toggle to force a refresh.
    private var fineGpsKey: String {
        guard gpsOn, userIsNearCurrentHole,
              let loc = vm.location.currentLocation else { return "" }
        let lat = (loc.latitude  / 0.00003).rounded() * 0.00003
        let lon = (loc.longitude / 0.00003).rounded() * 0.00003
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
        // Over par is MOST rounds — muted gray made the number disappear on the map HUD.
        scoreToPar < 0 ? Color(red: 0.22, green: 0.78, blue: 0.42)
            : scoreToPar == 0 ? Color(red: 0.42, green: 0.72, blue: 0.98)
            : .white
    }

    private func pushWidgetData() {
        guard let round = vm.activeRound, let hole = vm.currentHole else {
            WidgetBridge.clear()
            WatchConnectivityBridge.shared.clearRound()
            if #available(iOS 16.2, *) { ActivityBridge.end() }
            lastWidgetPushKey = ""
            return
        }
        let d = mapDistances
        // The 1s heartbeat calls this unconditionally — skip when nothing the widget shows
        // has changed so standing still doesn't rewrite the widget store every second.
        let pushKey = "\(hole.holeNumber)|\(scoreToPar)|\(round.scoreSummary.totalScore)|\(d.front ?? -1)|\(d.center ?? -1)|\(d.back ?? -1)"
        guard pushKey != lastWidgetPushKey else { return }
        lastWidgetPushKey = pushKey
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
        // Courses with no hole geometry at all (GPS-estimate/failed enrichment) have nothing
        // above to key off of, so the map falls back to centering on the course or the player's
        // live GPS. Track whether either has become available yet so that transition — which
        // otherwise wouldn't change any of the fields above — still forces one recenter, instead
        // of leaving the view stuck on whatever placeholder region existed at first render.
        let hasAnchor = (vm.selectedCourse?.coordinate ?? initialCourse?.coordinate) != nil
                     || vm.location.currentLocation != nil
        return "\(hole)-\(greenLat)-\(greenLon)-\(teeLat)-\(teeLon)-\(gpsOn)-\(hasAnchor)"
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

    // MARK: - Aim point drags
    // (extracted from the body closure — the inline version pushed the body
    // expression past the type-checker's budget once the ghost UI landed)

    private func handleAimPointMoved(_ idx: Int, _ coord: CLLocationCoordinate2D) {
        // The flag-spawned waypoint rides at the END of the array — route its
        // drags to flagWaypoint, not the override dict (indices must never grow
        // the override set past the hole's starting waypoint count).
        if flagWaypoint != nil && idx == activeAimPoints.count - 1 {
            guard let green = currentMapHole?.greenCenterCoordinate?.clCoordinate else {
                flagWaypoint = coord; return
            }
            let yards = Self.metersBetween(coord, green) * 1.09361
            if yards <= Self.kFlagWaypointBoundaryYds {
                // Dragged back inside the flag boundary → the waypoint dissolves.
                // The FLAG never moves from anything but its own drag: it stays
                // exactly where it was (home or a prior valid placement).
                flagWaypoint = nil
            } else {
                // Re-run the merge/ordering rules: dragging it back past an existing
                // waypoint must merge into that waypoint, never draw backwards lines.
                flagWaypoint = nil
                placeFlagSpawnedWaypoint(at: coord, green: green)
            }
        } else if idx < suggestedAimPoints.count {
            // Normal waypoints can never enter the flag's 30y zone — clamp to the ring.
            var c = coord
            if let green = currentMapHole?.greenCenterCoordinate?.clCoordinate {
                let yards = Self.metersBetween(coord, green) * 1.09361
                if yards < Self.kFlagWaypointBoundaryYds {
                    c = green.projected(yardsForward: Self.kFlagWaypointBoundaryYds,
                                        yardsRight: 0,
                                        bearingDeg: green.bearing(to: coord))
                }
            }
            // …and never within 30y of another waypoint OR the (moved) flag —
            // clamp to the separation ring around the nearest along the drag.
            var others: [CLLocationCoordinate2D] = suggestedAimPoints.indices
                .filter { $0 != idx }
                .map { userAimPointOverrides[$0] ?? suggestedAimPoints[$0] }
            if let flag = flagWaypoint { others.append(flag) }
            if let pin = pinOverride { others.append(pin) }
            if let near = others.min(by: {
                Self.metersBetween($0, c) < Self.metersBetween($1, c)
            }), Self.metersBetween(near, c) * 1.09361 < Self.kWaypointMinSeparationYds {
                c = near.projected(yardsForward: Self.kWaypointMinSeparationYds,
                                   yardsRight: 0,
                                   bearingDeg: near.bearing(to: c))
            }
            userAimPointOverrides[idx] = c
        }
    }

    // MARK: - Body

    // Extracted from body: the 25-arg map call blew the type-check budget
    // once the ghost-race overlays were added.
    private var mapLayer: some View {
        SatelliteMapBackground(
            greenCoord:  currentMapHole?.greenCenterCoordinate?.clCoordinate,
            teeCoord:    currentMapHole?.teeCoordinate?.clCoordinate,
            userCoord:   (gpsOn && userIsNearCurrentHole) ? vm.location.currentLocation : nil,
            rawUserCoord: gpsOn ? vm.location.currentLocation : nil,
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
            onAimPointMoved: { idx, coord in handleAimPointMoved(idx, coord) },
            onUserPanned: {
                withAnimation(.spring(response: 0.3)) { showRecenter = true }
            },
            trackedShots:   vm.currentHoleTrackedShots,
            dispersionDots: dispersionDots,
            topUIInset:    topSafeArea + 140, // clears the lowered top bar + info strip
            bottomUIInset: bottomSafeArea + 130, // raised bottom stack (score bar, badges, pills) — keeps the tee dot visible above it
            gpsKey:        coarseGpsKey,
            fineGpsKey:    fineGpsKey,
            flagSpawnedIndex: flagWaypoint != nil ? activeAimPoints.count - 1 : nil,
            customAimTarget: aimTarget,
            pinCoord:      pinOverride,
            onPinMoved:    { coord in handlePinMoved(coord) },
            hazardCounts:  hazardCounts,
            onHazardCountChanged: { key, count in hazardCounts[key] = count },
            onMapTap: { coord in
                guard let green = currentMapHole?.greenCenterCoordinate?.clCoordinate,
                      let userLoc = vm.location.currentLocation else { return }
                let yardsToGreen = SatelliteMapBackground.metersBetween(userLoc, green) * 1.09361
                guard yardsToGreen <= 240 else { return }
                let tapToGreen = SatelliteMapBackground.metersBetween(coord, green) * 1.09361
                // An aim target only makes sense BETWEEN the player and the green (a layup
                // or a side of the green). Without this bound a stray tap while walking
                // planted a target hundreds of yards past the flag and the line chased it.
                guard tapToGreen <= max(yardsToGreen, 40) else { return }
                aimTarget = tapToGreen < 25 ? nil : coord
            },
            focusId:        mapFocusId,
            recenterToken:  recenterToken,
            flightRequest:  flightRequest,
            onFlightCompleted: { landing in handleFlightCompleted(landing) }
        )
        .ignoresSafeArea()
    }

    // Extracted from body — the ZStack tuple pushed the type-checker over
    // its budget once the ghost-race overlays landed.
    @ViewBuilder private var statusOverlays: some View {
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

        // Wind flow arrows — ambient direction cue over the map. Stays on even with the
        // dispersion overlay showing, since the dots being shifted doesn't itself convey
        // wind direction the way the flowing arrows do.
        if windEnabled, let we = windDotEffect {
            // Offset by the map heading so arrows read correctly on the rotated (heading-up) map.
            WindFlowOverlay(toBearingDegrees: we.fromDegrees + 180 - mapHeading)
                .allowsHitTesting(false)
                .zIndex(1)
        }
    }

    @ViewBuilder private var hudOverlays: some View {
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

            // Top bar — lowered well off the notch/island for breathing room
            topBar
                .padding(.top, 158)

            // Hole info strip
            holeInfoStrip
                .padding(.top, 2)
                .padding(.horizontal, 16)

            // Wind readout — tucked right under the par/yardage/HCP strip, centered.
            if windEnabled {
                windPill
                    .padding(.top, 3)
            }

            // Ghost match — live match status, or the offer when past rounds exist.
            if let ghost = ghostRound {
                GhostStrip(
                    ghost: ghost,
                    currentHoles: vm.activeRound?.holes ?? [],
                    currentHoleNumber: vm.currentHole?.holeNumber ?? (vm.currentHoleIndex + 1),
                    onEnd: {
                        withAnimation { ghostRound = nil }
                        GhostPersistence.clear()
                    }
                )
                .padding(.top, 3)
            } else if !ghostCandidates.isEmpty && !ghostOfferDismissed {
                GhostOfferChip(
                    bestScore: ghostCandidates[0].scoreSummary.totalScore,
                    onPick: { showGhostPicker = true },
                    onDismiss: { withAnimation { ghostOfferDismissed = true } }
                )
                .padding(.top, 3)
            }

            Spacer()
        }
        .ignoresSafeArea(edges: .bottom)

        // Left sidebar — pinned just above the OSM attribution badge
        leftSidebar
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 6)
            .padding(.top, topSafeArea + 120)
            .padding(.bottom, 250)
            .ignoresSafeArea(edges: .bottom)

        // Right sidebar
        rightSidebar
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
            .padding(.top, topSafeArea + 126)
            .padding(.bottom, 232)
            .ignoresSafeArea(edges: .bottom)

        // Slope ("plays-like") pill — bottom-right, same height as the left F/C/B pill
        VStack { Spacer(minLength: 0); slopePill }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 12)
            .padding(.top, topSafeArea + 120)
            .padding(.bottom, 250)
            .ignoresSafeArea(edges: .bottom)


        // Hazard count badges — top-left, below the (lowered) top bar
        if !hazardCounts.filter({ $0.value > 0 }).isEmpty {
            VStack {
                HStack(spacing: 5) {
                    hazardCountBadge
                    Spacer()
                }
                .padding(.top, topSafeArea + 174)
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
                    .padding(.bottom, 232)
            }
        }
        .ignoresSafeArea(edges: .bottom)

        // OSM attribution — required by the ODbL license whenever OSM geometry is shown.
        VStack {
            Spacer()
            HStack {
                OSMAttributionBadge()
                    .padding(.leading, 10)
                    .padding(.bottom, 224)   // above the bottom bar
                Spacer()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // Body split into layers + modifier chunks: as one expression the
    // type-checker timed out after the ghost-race merge.
    var body: some View {
        attachLifecycle(attachCovers(attachDialogs(attachCore(baseStack))))
    }

    private var baseStack: some View {
        ZStack(alignment: .top) {

            // Full-screen satellite map
            mapLayer

            statusOverlays

            hudOverlays

        }
    }

    private func attachCore<V: View>(_ v: V) -> some View {
        v
        // Stationary auto-prompt: you've been standing still without logging a shot here —
        // offer the shot tracker (never auto-inputs; dismissing does nothing).
        .overlay(alignment: .top) {
            if showStationaryPrompt {
                stationaryPromptBanner
                    .padding(.top, topSafeArea + 132)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            evaluateStationaryPrompt()
        }
        // Bottom bar
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationBarHidden(true)
        // Alerts
    }

    private func attachDialogs<V: View>(_ v: V) -> some View {
        v
        .confirmationDialog("Leave the course?", isPresented: $showLeaveDialog,
                            titleVisibility: .visible) {
            Button("Back to app — round stays active") {
                // The round is already persisted; a tap-to-return banner shows app-wide.
                dismiss()
            }
            Button("Finish or delete round…") { showFinishAlert = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can use the rest of the app and jump back into your round from the banner at the top.")
        }
        .alert("Finish Round?", isPresented: $showFinishAlert) {
            Button("Finish & Save") {
                Task {
                    await vm.finishRound()
                    WidgetBridge.clear()
                    if #available(iOS 16.2, *) { ActivityBridge.end() }
                    dismiss()
                }
            }
            Button("Delete Round", role: .destructive) {
                showDeleteRoundConfirm = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your round will be saved.")
        }
        .alert("Delete this round?", isPresented: $showDeleteRoundConfirm) {
            Button("Delete Round", role: .destructive) {
                Task {
                    await vm.discardRound()
                    WidgetBridge.clear()
                    if #available(iOS 16.2, *) { ActivityBridge.end() }
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
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
    }

    private func attachCovers<V: View>(_ v: V) -> some View {
        v
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
                    existingScore:  scoreEntryInitialScore(for: hole),
                    existingPutts:  scoreEntryInitialPutts(for: hole),
                    holeYardage:    scorecardYardage,
                    handicap:       currentCourseHole?.strokeIndex(for: session.userProfile?.gender),
                    prefillTeeClubName: teeClubName(for: hole),
                    prefillFirstPuttFeet: firstPuttFeet(for: hole)
                ) { s, p, f, g in
                    let idx = vm.currentHoleIndex
                    let holeNum = hole.holeNumber
                    let isLastHole = idx >= (vm.activeRound?.holes.count ?? 0) - 1
                    // Advance IMMEDIATELY and persist in the background — waiting on the
                    // network round-trip made switching holes feel sluggish.
                    if isLastHole {
                        showFinalScorecard = true
                    } else {
                        vm.advanceHole()
                    }
                    Task {
                        await vm.closeManualShotForHole(holeNum)
                        await vm.setScore(holeIndex: idx, score: s, putts: p, fairwayHit: f, gir: g)
                    }
                }
                .tcAppearance()
            }
        }
        .sheet(isPresented: $showScorecard) {
            if let round = vm.activeRound {
                NavigationStack {
                    ScorecardView(round: round, onEditShots: { holeNumber in
                        showScorecard = false
                        // Same-frame dismiss+present silently drops the second sheet —
                        // wait out the dismissal animation before opening the editor.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            editingShotsHole = holeNumber
                        }
                    })
                }
                .tcAppearance()
            }
        }
        .sheet(item: Binding(
            get: { editingShotsHole.map { EditingShotsHole(number: $0) } },
            set: { editingShotsHole = $0?.number }
        )) { editing in
            if let round = vm.activeRound,
               let hole = round.holes.first(where: { $0.holeNumber == editing.number }) {
                let line = vm.holeCenterline(holeNumber: hole.holeNumber)
                HoleShotsEditSheet(
                    holeNumber: hole.holeNumber, par: hole.par,
                    score: hole.score, shots: hole.trackedShots,
                    clubs: clubs,
                    teeCoordinate: line?.first,
                    greenCoordinate: line?.last,
                    onDelete: { shotId in
                        Task { await vm.deleteTrackedShot(shotId) }
                    },
                    onChangeClub: { shotId, club in
                        Task { await vm.updateTrackedShotClub(shotId, club: club) }
                    },
                    onAddShot: { club, after, start, end in
                        Task {
                            await vm.insertTrackedShot(club: club, start: start, end: end,
                                                       afterIndex: after,
                                                       holeNumber: hole.holeNumber)
                        }
                    }
                )
                .tcAppearance()
            }
        }
        // Final flow after hole 18: editable scorecard → post / save privately / delete → home.
        .fullScreenCover(isPresented: $showFinalScorecard) {
            FinalRoundReviewView(vm: vm, clubs: clubs) { action in
                Task {
                    switch action {
                    case .postPublic:   await vm.finishRound(shareToFeed: true)
                    case .savePrivate:  await vm.finishRound(shareToFeed: false)
                    case .delete:       await vm.discardRound()
                    }
                    WidgetBridge.clear()
                    if #available(iOS 16.2, *) { ActivityBridge.end() }
                    showFinalScorecard = false
                    dismiss()
                }
            }
            .tcAppearance()
        }
        // Shot tracker: "I'm hitting from HERE with CLUB" — the manual equivalent of NFC tags.
        .sheet(isPresented: $showShotLogSheet) {
            ShotLogSheet(clubs: clubs) { club, movedOrDropped in
                Task {
                    let ok = await vm.logManualShot(club: club, movedOrDropped: movedOrDropped)
                    if ok, let loc = vm.location.currentLocation {
                        loggedShotCoords.append(loc)
                    } else if !ok {
                        infoMessage = "No GPS fix yet — walk to your ball and try again."
                    }
                }
            }
            // Opens at (near) full height so the whole bag is visible without dragging.
            .presentationDetents([.fraction(0.92), .large])
            .tcAppearance()
        }
        .sheet(isPresented: $showDispersionPicker) {
            dispersionPickerSheet
                .presentationDetents([.medium, .large])
                .tcAppearance()
        }
        .sheet(isPresented: $showCaddie) {
            caddieSheet
                .presentationDetents([.medium, .large])
                .tcAppearance()
        }
        .sheet(isPresented: $showGhostPicker) {
            GhostPickerSheet(candidates: ghostCandidates) { picked in
                withAnimation { ghostRound = picked }
                if let rid = vm.activeRound?.id {
                    GhostPersistence.save(roundId: rid, ghostId: picked.id)
                }
            }
            .presentationDetents([.medium, .large])
            .tcAppearance()
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
    }

    private func attachLifecycle<V: View>(_ v: V) -> some View {
        v
        .task {
            // Load clubs for NFC tag lookup
            if let uid = session.currentUser?.id {
                clubs = (try? await session.backend.loadClubs(userId: uid)) ?? []
            }
            if let round = initialRound {
                await vm.resumeRound(round)
            } else if let course = initialCourse, let tee = initialTeeBox {
                await vm.startRoundEnriching(course: course, teeBox: tee, gender: session.userProfile?.gender ?? .male)
            }
            pushWidgetData()
            // Ghost match: past scored rounds on this course become raceable ghosts.
            if let uid = session.currentUser?.id, let active = vm.activeRound {
                let all = (try? await session.backend.loadCourseRounds(userId: uid)) ?? []
                ghostCandidates = GhostMatchScorer.candidates(
                    from: all, courseId: active.courseId, excluding: active.id
                )
                // Restore a ghost race that was live when the app last closed.
                if ghostRound == nil,
                   let gid = GhostPersistence.ghostId(forRound: active.id),
                   let restored = ghostCandidates.first(where: { $0.id == gid }) {
                    ghostRound = restored
                }
            }
        }
        .onAppear {
            registerWatchRoundControls()
            loadElevationForHole()
            OrientationManager.shared.lockPortrait()
            ActiveRoundBeacon.shared.courseViewVisible = true
        }
        .onDisappear {
            ActiveRoundBeacon.shared.courseViewVisible = false
            WatchConnectivityBridge.shared.unregisterRoundCommandHandler()
            OrientationManager.shared.unlockAllButUpsideDown()
        }
        .onChange(of: vm.activeRound?.id) { _ in
            pushWidgetData()
        }
        .onChange(of: vm.currentHoleIndex) { _ in
            recenterToken += 1
            userAimPointOverrides = [:]
            aimTarget = nil
            pinOverride = nil
            flagWaypoint = nil
            hazardCounts = [:]
            loggedShotCoords = []
            stationarySince = nil
            showRecenter = false
            pushWidgetData()
            loadElevationForHole()
        }
        .onChange(of: mapDistances.center) { _ in
            pushWidgetData()
            loadElevationForHole()   // geometry arrives async from Supabase after onAppear
        }
        .onChange(of: vm.activeRound?.scoreSummary.totalScore) { _ in
            pushWidgetData()
        }
        // Fixed-interval refresh: keeps lock-screen / Live Activity yardages current even
        // when nothing in the foreground view tree changes (or the app is backgrounded —
        // round-scoped background location keeps the process alive and the timer firing).
        .onReceive(widgetHeartbeat) { _ in
            pushWidgetData()
        }
        .onChange(of: gpsOn) { _ in
            recenterToken += 1
        }
        .task(id: nfcManager.lastScannedClubId) { handleNFCClubTap() }
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
            Button { showLeaveDialog = true } label: {
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
                VStack(alignment: .leading, spacing: 3) {
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
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .hudGlass(14)
                .frame(minWidth: 70, alignment: .leading)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mapDistances.center)
            }
        }
    }

    private func distanceRow(label: String, yards: Int, isHero: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
                .font(.system(size: isHero ? 9 : 8, weight: .black, design: .rounded))
                .foregroundColor(isHero ? .white : .white.opacity(0.5))
                .frame(width: 10, alignment: .leading)
            Text("\(yards)")
                .font(.system(size: isHero ? 31 : 13, weight: isHero ? .black : .semibold,
                              design: .rounded))
                .foregroundColor(isHero ? .white : .white.opacity(0.75))
                .contentTransition(.numericText())
                .shadow(color: .black.opacity(isHero ? 0.5 : 0.2), radius: isHero ? 5 : 2, y: 1)
            if isHero {
                Text("yd")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
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
                // Shot tracker (replaced the GPS on/off toggle — GPS is now always live and
                // the HUD updates continuously, so the toggle had no remaining purpose).
                railButton("figure.golf.circle.fill", isActive: showShotLogSheet) {
                    showShotLogSheet = true
                }
                // Reset waypoints/pin to the True Carry defaults from the current position.
                railButton("arrow.counterclockwise", isActive: false) {
                    resetWaypointsAndRecenter()
                }
                railButton("scope", isActive: !dispersionClubIds.isEmpty) {
                    showDispersionPicker = true
                }
                // Slope toggle — pulls each dispersion dot in (uphill) or out (downhill) by the
                // plays-like elevation change. Kept in the rail ALWAYS (dimmed until a dispersion
                // overlay is active) so the rail never resizes/shifts when you turn the overlay on.
                railButton("mountain.2.fill", isActive: slopeAdjustDots && !dispersionClubIds.isEmpty) {
                    slopeAdjustDots.toggle()
                    if slopeAdjustDots {
                        loadElevationForHole()   // ensure the grid is loaded for the shift
                    }
                }
                .disabled(dispersionClubIds.isEmpty)
                .opacity(dispersionClubIds.isEmpty ? 0.3 : 1)
                // Wind toggle — pulls live wind (WeatherKit) and shows the plays-like adjustment.
                railButton("wind", isActive: windEnabled) {
                    windEnabled.toggle()
                    if windEnabled { refreshWind(force: true) }
                }
                // Club suggestion (Pro/Unlimited) — best club to hold the green from your history.
                if session.entitlementVM.canAccessAdvancedInsights {
                    railButton("figure.golf", isActive: showCaddie) { openCaddie() }
                }
                railButton("camera.fill", isActive: false) { openCamera() }
                railButton("list.number", isActive: false) { showScorecard = true }
            }
            .padding(.vertical, 14)
            .frame(width: 56)
            .hudGlass(28)
            Spacer(minLength: 0)
        }
    }

    /// Dispersion club picker. Plain list — tap to toggle one or more clubs. A club only takes an
    /// identity color once *more than one* club is selected (so you can tell overlapping patterns
    /// apart); the fill matches that club's on-course dots. With a single club it stays neutral and
    /// the dots grade by green proximity / line instead.
    private var dispersionPickerSheet: some View {
        let multi = dispersionClubIds.count > 1
        return NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    Picker("Dot distance", selection: $dispersionMetric) {
                        ForEach(DispersionMetric.allCases, id: \.self) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Where the dots come from: range/sim captures, real-round shots, or both.
                    Picker("Shot source", selection: $dispersionSource) {
                        ForEach(DispersionShotSource.allCases, id: \.self) { src in
                            Text(src.rawValue).tag(src)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: dispersionSource) { _ in reloadDispersionShots() }

                    // Normal shots vs every shot: an aggressive median±band trim per club, so
                    // the overlay answers "what do I usually hit", not "what's ever happened".
                    Toggle(isOn: $dispersionExcludeOutliers) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hide outliers")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(TCTheme.textPrimary)
                            Text("Show your normal number — drop chunks & one-off bombs")
                                .font(.system(size: 11))
                                .foregroundColor(TCTheme.textMuted)
                        }
                    }
                    .tint(TCTheme.sage)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 6)

                    if clubs.isEmpty {
                        Text("Add clubs to your bag to overlay shot dispersion.")
                            .font(.system(size: 14))
                            .foregroundColor(TCTheme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.top, 50)
                    }
                    ForEach(clubs) { club in
                        let selected = dispersionClubIds.contains(club.id)
                        let color = TCDispersionColor.club(dispersionClubIds.firstIndex(of: club.id) ?? 0)
                        let showColor = selected && multi
                        Button { toggleDispersionClub(club) } label: {
                            HStack(spacing: 12) {
                                Text(club.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(showColor ? .white : TCTheme.textPrimary)
                                    .padding(.horizontal, showColor ? 10 : 0)
                                    .padding(.vertical, showColor ? 5 : 0)
                                    .background { if showColor { Capsule().fill(color) } }
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(selected ? (showColor ? color : TCTheme.sage) : TCTheme.textUltraMuted)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(TCTheme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? (showColor ? color.opacity(0.6) : TCTheme.sage.opacity(0.5)) : TCTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
            .background(TrueCarryBackground().ignoresSafeArea())
            .navigationTitle("Dispersion Overlay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !dispersionClubIds.isEmpty {
                        Button("Clear") {
                            dispersionClubIds.removeAll()
                            dispersionShotsByClub.removeAll()
                        }
                        .foregroundColor(.red)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showDispersionPicker = false }
                        .foregroundColor(TCTheme.sage)
                }
            }
        }
    }

    /// Right-side slope ("plays-like") pill — mirrors the left F/C/B pill but each
    /// number is slope-adjusted, with an arrow showing net elevation to the green.
    @ViewBuilder private var slopePill: some View {
        let s = slopeDistances
        if s.isAvailable {
            VStack(alignment: .trailing, spacing: 3) {
                if let v = s.verticalYards, v != 0 {
                    HStack(spacing: 2) {
                        Image(systemName: v > 0 ? "arrow.up.forward" : "arrow.down.forward")
                            .font(.system(size: 8, weight: .black))
                        Text("\(abs(v))y")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(v > 0 ? Color(red: 0.70, green: 0.95, blue: 0.24)
                                           : Color(red: 0.98, green: 0.72, blue: 0.42))
                }
                if let f = s.front  { slopeRow(label: "F", yards: f, isHero: false) }
                if let c = s.center { slopeRow(label: "C", yards: c, isHero: true) }
                if let b = s.back   { slopeRow(label: "B", yards: b, isHero: false) }
                Text("PLAYS")
                    .font(.system(size: 7, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.40))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .hudGlass(14)
            .frame(minWidth: 70, alignment: .trailing)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: s.center)
        }
    }

    /// Compact wind stat chip — live speed + the compass direction it's blowing FROM (e.g. "3 mph NW").
    /// Shown whenever wind mode is on; the flowing arrows / dot shift convey the effect visually.
    @ViewBuilder private var windPill: some View {
        if wind.isLoading && wind.reading == nil {
            HStack(spacing: 7) {
                ProgressView().scaleEffect(0.7).tint(.white)
                Text("Reading wind…")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.85))
            }
            .padding(.horizontal, 12).padding(.vertical, 7).hudGlass(14)
        } else if let r = wind.reading {
            HStack(spacing: 7) {
                Image(systemName: "wind")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.white.opacity(0.9))
                Text("\(Int(r.speedMph.rounded())) mph \(WindModel.cardinal(r.fromDegrees))")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.white)
            }
            .padding(.horizontal, 12).padding(.vertical, 7).hudGlass(14)
        } else if wind.errorText != nil {
            Button { refreshWind(force: true) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wind").font(.system(size: 11, weight: .bold))
                    Text("Wind unavailable — tap to retry")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 12).padding(.vertical, 7).hudGlass(14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Club suggestion sheet (#3)

    private var caddieSheet: some View {
        NavigationStack {
            ZStack {
                TrueCarryBackground().ignoresSafeArea()
                VStack(spacing: 16) {
                    if caddieLoading {
                        Spacer()
                        ProgressView("Reading your bag…")
                            .tint(TCTheme.sage)
                            .foregroundColor(TCTheme.textMuted)
                        Spacer()
                    } else if let s = caddieResult {
                        // Scrolls so the layered plan (odds + strategy + hazards + position)
                        // is never clipped at the medium detent.
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 14) {
                                caddieResultCard(s)
                                if let plan = caddiePlan {
                                    if !plan.strategy.isEmpty { caddieStrategyCard(plan) }
                                    if !plan.hazardNotes.isEmpty { caddieHazardCard(plan.hazardNotes) }
                                    if let note = plan.positionNote { caddiePositionCard(note) }
                                    if !plan.basis.isEmpty {
                                        Text(plan.basis)
                                            .font(.system(size: 11))
                                            .foregroundColor(TCTheme.textUltraMuted)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 30)
                                    }
                                }
                            }
                            .padding(.bottom, 24)
                        }
                    } else {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "flag.slash")
                                .font(.system(size: 30))
                                .foregroundColor(TCTheme.textMuted)
                            Text(caddieMessage ?? "No suggestion available.")
                                .font(.system(size: 14))
                                .foregroundColor(TCTheme.textMuted)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 28)
                        Spacer()
                    }
                }
                .padding(.top, 20)
            }
            .navigationTitle("Caddie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showCaddie = false }.foregroundColor(TCTheme.sage)
                }
            }
        }
    }

    /// Go-vs-layup, ranked by the golfer's OWN expected strokes from here.
    private func caddieStrategyCard(_ plan: CourseManagementEngine.Plan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("STRATEGY", systemImage: "map")
                .font(.system(size: 10, weight: .black))
                .tracking(1.0)
                .foregroundColor(TCTheme.textMuted)
            ForEach(Array(plan.strategy.enumerated()), id: \.offset) { i, opt in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: i == 0 ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(i == 0 ? TCTheme.sage : TCTheme.textUltraMuted)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(opt.title)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundColor(TCTheme.textPrimary)
                            Spacer()
                            Text(String(format: "%.1f strokes", opt.expectedStrokes))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(i == 0 ? TCTheme.sage : TCTheme.textMuted)
                        }
                        Text(opt.detail)
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Text(opt.title.hasPrefix("Go")
                                 ? "\(opt.successPercent)% on green"
                                 : "\(opt.successPercent)% on with next")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(TCTheme.gold)
                            if opt.hazardPercent > 4 {
                                Text("\(opt.hazardPercent)% hazard risk")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if let note = plan.strategyNote {
                Text(note)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(TCTheme.sage)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tcCard()
        .padding(.horizontal, TCTheme.hPad)
    }

    private func caddieHazardCard(_ notes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("TROUBLE", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .black))
                .tracking(1.0)
                .foregroundColor(.orange)
            ForEach(notes, id: \.self) { n in
                Text(n)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tcCard()
        .padding(.horizontal, TCTheme.hPad)
    }

    private func caddiePositionCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("YOUR POSITION", systemImage: "location.north.line.fill")
                .font(.system(size: 10, weight: .black))
                .tracking(1.0)
                .foregroundColor(TCTheme.gold)
            Text(note)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(TCTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tcCard()
        .padding(.horizontal, TCTheme.hPad)
    }

    private func caddieResultCard(_ s: CaddieEngine.Suggestion) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 3) {
                Text(s.isLayup ? "SMART ADVANCE" : "BEST GREEN ODDS")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.2)
                    .foregroundColor(TCTheme.textMuted)
                Text(s.clubName)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(TCTheme.textPrimary)
                Text("plays \(s.playingYards) yds")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(TCTheme.sage)
            }

            HStack(spacing: 12) {
                caddieStat("YOUR CARRY", "\(s.typicalYards)y")
                if s.isLayup {
                    caddieStat("LEAVES", "\(s.leavesYards)y")
                } else {
                    caddieStat("ON GREEN", "\(s.onGreenPercent)%")
                }
                caddieStat("ACTUAL", "\(s.baseYards)y")
            }

            if !s.isLayup && s.greenSamples > 0 {
                Text("\(s.greenHits) of \(s.greenSamples) tracked shots would have finished on this green.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !s.swingNote.isEmpty {
                Text(s.swingNote)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TCTheme.sage)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Adjustment chips
            if s.slopeDelta != 0 || s.windDelta != 0 {
                HStack(spacing: 8) {
                    if s.slopeDelta != 0 {
                        caddieChip("mountain.2.fill", "slope \(s.slopeDelta > 0 ? "+" : "")\(s.slopeDelta)")
                    }
                    if s.windDelta != 0 {
                        caddieChip("wind", "wind \(s.windDelta > 0 ? "+" : "")\(s.windDelta)")
                    }
                }
            }

            if !s.aimAdvice.isEmpty {
                Label("\(s.aimAdvice)\(s.windSummary.isEmpty ? "" : "  ·  \(s.windSummary)")",
                      systemImage: "scope")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TCTheme.gold)
            }

            if let t = s.tightest {
                caddieTightestRow(t)
            }

            Text(s.isLayup
                 ? "None of your clubs show green-holding results from this number — this leaves your best next shot."
                 : "Ranked by your real results at this distance, not just the closest average carry.")
                .font(.system(size: 11))
                .foregroundColor(TCTheme.textUltraMuted)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .tcCard()
        .padding(.horizontal, TCTheme.hPad)
    }

    /// Secondary suggestion layer: the most repeatable club at this yardage when it isn't the
    /// best-odds pick — steady distance, but the numbers say it hasn't been holding this green.
    private func caddieTightestRow(_ t: CaddieEngine.TightestPick) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("TIGHTEST GROUPING", systemImage: "target")
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.8)
                    .foregroundColor(TCTheme.textMuted)
                Spacer()
                Text(t.clubName)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(TCTheme.textPrimary)
            }
            Text(caddieTightestBlurb(t))
                .font(.system(size: 12))
                .foregroundColor(TCTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func caddieTightestBlurb(_ t: CaddieEngine.TightestPick) -> String {
        let base = "Your most repeatable club at this number — carries \(t.typicalYards)y within about ±\(t.spreadYards)y."
        if t.greenHits > 0 {
            return base + " \(t.greenHits) of \(t.greenSamples) tracked shots would have finished on the green."
        }
        if t.reached == 0 {
            return base + " But it hasn't shown the carry — none of its \(t.greenSamples) tracked shots reached this green."
        }
        if t.longMisses > t.shortMisses {
            return base + " But none finished on the green — its misses run past the back."
        }
        if t.shortMisses > t.longMisses {
            return base + " But none finished on the green — it usually comes up just short."
        }
        return base + " But none of its \(t.greenSamples) tracked shots would have finished on the green."
    }

    private func caddieStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(TCTheme.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func caddieChip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(TCTheme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(TCTheme.panel)
        .clipShape(Capsule())
    }

    private func slopeRow(label: String, yards: Int, isHero: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
                .font(.system(size: isHero ? 9 : 8, weight: .black, design: .rounded))
                .foregroundColor(isHero ? .white : .white.opacity(0.5))
                .frame(width: 10, alignment: .leading)
            Text("\(yards)")
                .font(.system(size: isHero ? 31 : 13, weight: isHero ? .black : .semibold,
                              design: .rounded))
                .foregroundColor(isHero ? .white : .white.opacity(0.75))
                .contentTransition(.numericText())
        }
    }

    /// Slope-adjusted F/C/B yardages + net elevation to the green center (yards;
    /// + uphill, − downhill).
    private struct SlopeReadout {
        var front: Int? = nil
        var center: Int? = nil
        var back: Int? = nil
        var verticalYards: Int? = nil
        var isAvailable: Bool { center != nil }
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
                Circle().fill(TCTheme.goldGradient).frame(width: 37, height: 37)
                Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1).frame(width: 37, height: 37)
                Text(userInitials)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(TCTheme.deepGreen)
            }

            // Score info — to-par + strokes side by side (no name/email)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(scoreToParString)
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundColor(scoreToParColor)
                Text("· \(vm.activeRound?.scoreSummary.totalScore ?? 0) strokes")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.70))
            }

            Spacer(minLength: 0)

            // Camera
            Button { openCamera() } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 41, height: 41)
                    .background(.white.opacity(0.12))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(HUDPressStyle())

            // Add Score — stacked gold button
            Button { showScoreEntry = true } label: {
                VStack(spacing: 2) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .bold))
                    Text("Add Score")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                }
                .foregroundColor(TCTheme.deepGreen)
                .frame(width: 74, height: 47)
                .background(TCTheme.goldGradient)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: TCTheme.gold.opacity(0.4), radius: 6, y: 2)
            }
            .buttonStyle(HUDPressStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 9)
        .padding(.bottom, 160)
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

/// Ambient wind arrows drifting across the map in the direction the wind blows. A handful of
/// chevrons per lane fade in/out as they cross, so it reads clearly without cluttering the view.
private struct WindFlowOverlay: View {
    let toBearingDegrees: Double   // compass bearing the wind travels TOWARD (0 = N = screen up)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let rad = toBearingDegrees * .pi / 180
                let ux = sin(rad), uy = -cos(rad)      // travel unit vector (screen coords, y down)
                let px = -uy, py = ux                   // perpendicular, for lane spacing
                let lanes = 6
                let diag = Double(hypot(size.width, size.height)) + 80
                let cx = Double(size.width) / 2, cy = Double(size.height) / 2
                let speed = 70.0                        // pts per second
                let laneGap = Double(size.width) / Double(max(1, lanes - 1)) * 0.92
                let arrowsPerLane = 3                   // 3 arrows per lane on screen at once

                for lane in 0..<lanes {
                    let perpOff = (Double(lane) - Double(lanes - 1) / 2) * laneGap
                    for k in 0..<arrowsPerLane {
                        let phase = (t * speed + Double(lane) * 55 + Double(k) * diag / Double(arrowsPerLane))
                            .truncatingRemainder(dividingBy: diag)
                        let along = phase - diag / 2
                        let x = cx + ux * along + px * perpOff
                        let y = cy + uy * along + py * perpOff
                        let edge = 1 - abs(along) / (diag / 2)          // fade near the extremes
                        let alpha = max(0, min(1, edge * 1.6)) * 0.5
                        drawArrow(context, at: CGPoint(x: x, y: y), rad: rad, alpha: alpha)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private func drawArrow(_ ctx: GraphicsContext, at p: CGPoint, rad: Double, alpha: Double) {
        guard alpha > 0.02 else { return }
        var sub = ctx
        sub.translateBy(x: p.x, y: p.y)
        sub.rotate(by: .radians(rad))   // chevron drawn pointing up (−y) → aligns to travel dir
        var head = Path()
        head.move(to: CGPoint(x: -7, y: 5))
        head.addLine(to: CGPoint(x: 0, y: -7))
        head.addLine(to: CGPoint(x: 7, y: 5))
        sub.stroke(head, with: .color(.white.opacity(alpha)),
                   style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        var tail = Path()
        tail.move(to: CGPoint(x: 0, y: -6))
        tail.addLine(to: CGPoint(x: 0, y: 9))
        sub.stroke(tail, with: .color(.white.opacity(alpha * 0.65)),
                   style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
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

// MARK: - Shot Log Sheet (manual shot tracker — the NFC-tag flow with manual input)

private struct ShotLogSheet: View {
    let clubs: [UserClub]
    /// (club, movedOrDropped) — club nil is not emitted; tapping a club logs immediately.
    let onLog: (UserClub, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var movedOrDropped = false

    private var activeClubs: [UserClub] { clubs.filter { $0.isActive } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Log Shot")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .padding(.top, 18)

            // The GPS position at the moment of logging IS the measurement — say so every time.
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(HUDStyle.live)
                Text("Log this at (or near) the spot you're hitting from — your GPS position is used to measure this shot.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Toggle(isOn: $movedOrDropped) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("I took a drop / moved my ball")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("The distance into this spot won't count toward club stats.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            .tint(HUDStyle.pin)

            Text("WHAT ARE YOU HITTING?")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 4)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(activeClubs) { club in
                        Button {
                            onLog(club, movedOrDropped)
                            dismiss()
                        } label: {
                            VStack(spacing: 3) {
                                Text(club.name)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text("\(club.expectedTotalYards) yd")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.07).ignoresSafeArea())
    }
}

// MARK: - Final Round Review (after hole 18: edit scores → post / private / delete)

enum FinalRoundAction { case postPublic, savePrivate, delete }

struct FinalRoundReviewView: View {
    @ObservedObject var vm: CourseRoundViewModel
    var clubs: [UserClub] = []
    let onAction: (FinalRoundAction) -> Void
    @State private var editingHoleIndex: Int?
    @State private var editingShotsHoleIndex: Int?
    @State private var confirmDelete = false

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                Text("Round Complete")
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundColor(TCTheme.textPrimary)
                    .padding(.top, 24)
                if let name = vm.activeRound?.courseName, !name.isEmpty {
                    // Full course name, wrapping as needed — never truncated to one row.
                    Text(name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(TCTheme.sage)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .padding(.top, 6)
                }
                Text("Tap any hole column to fix its score before saving.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(TCTheme.textMuted)
                    .padding(.top, 4)

                ScrollView(showsIndicators: false) {
                    if let round = vm.activeRound {
                        VStack(spacing: 14) {
                            let holes = Array(round.holes.enumerated())
                            nineTable(title: "FRONT", holes: Array(holes.prefix(9)))
                            if holes.count > 9 {
                                nineTable(title: "BACK", holes: Array(holes.dropFirst(9)))
                            }
                            totalsCard(round)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                    }
                }

                VStack(spacing: 10) {
                    TCPrimaryGoldButton(title: "Post Round", icon: "globe") {
                        onAction(.postPublic)
                    }
                    TCOutlineButton(title: "Save Privately", color: TCTheme.sage) {
                        onAction(.savePrivate)
                    }
                    Button("Delete Round") { confirmDelete = true }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.red.opacity(0.85))
                        .padding(.top, 2)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .alert("Delete this round?", isPresented: $confirmDelete) {
            Button("Delete Round", role: .destructive) { onAction(.delete) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(item: Binding(
            get: { editingShotsHoleIndex.map { EditingHole(index: $0) } },
            set: { editingShotsHoleIndex = $0?.index }
        )) { editing in
            if let round = vm.activeRound, editing.index < round.holes.count {
                let hole = round.holes[editing.index]
                let line = vm.holeCenterline(holeNumber: hole.holeNumber)
                HoleShotsEditSheet(
                    holeNumber: hole.holeNumber, par: hole.par,
                    score: hole.score, shots: hole.trackedShots,
                    clubs: clubs,
                    teeCoordinate: line?.first,
                    greenCoordinate: line?.last,
                    onDelete: { shotId in
                        Task { await vm.deleteTrackedShot(shotId) }
                    },
                    onChangeClub: { shotId, club in
                        Task { await vm.updateTrackedShotClub(shotId, club: club) }
                    },
                    onAddShot: { club, after, start, end in
                        Task {
                            await vm.insertTrackedShot(club: club, start: start, end: end,
                                                       afterIndex: after,
                                                       holeNumber: hole.holeNumber)
                        }
                    }
                )
                .tcAppearance()
            }
        }
        .sheet(item: Binding(
            get: { editingHoleIndex.map { EditingHole(index: $0) } },
            set: { editingHoleIndex = $0?.index }
        )) { editing in
            if let round = vm.activeRound, editing.index < round.holes.count {
                let hole = round.holes[editing.index]
                ScoreEntryView(
                    holeNumber:    hole.holeNumber,
                    par:           hole.par,
                    existingScore: hole.score,
                    existingPutts: hole.putts,
                    holeYardage:   nil,
                    handicap:      nil,
                    prefillTeeClubName: nil,
                    prefillFirstPuttFeet: nil
                ) { s, p, f, g in
                    let idx = editing.index
                    Task { await vm.setScore(holeIndex: idx, score: s, putts: p, fairwayHit: f, gir: g) }
                }
                .tcAppearance()
            }
        }
    }

    // MARK: Scorecard tables

    private struct HoleStats { var drops = 0; var fwBunkers = 0; var gsBunkers = 0 }

    /// Drops come from logged penalty/moved shots; bunker visits from sand-lie shots, split
    /// fairway vs greenside by distance to the green center (>45y = fairway bunker).
    private func stats(for hole: RoundHole) -> HoleStats {
        var st = HoleStats()
        st.drops = hole.trackedShots.filter { $0.result == .penalty }.count
        let sand = hole.trackedShots.filter { $0.lie == .sand }
        let green = vm.selectedCourse?.holes
            .first(where: { $0.number == hole.holeNumber })?.greenCenterCoordinate
        for b in sand {
            if let g = green {
                let d = CLLocation(latitude: b.startCoordinate.latitude,
                                   longitude: b.startCoordinate.longitude)
                    .distance(from: CLLocation(latitude: g.latitude, longitude: g.longitude)) * 1.09361
                if d > 45 { st.fwBunkers += 1 } else { st.gsBunkers += 1 }
            } else {
                st.gsBunkers += 1
            }
        }
        return st
    }

    private func nineTable(title: String, holes: [(offset: Int, element: RoundHole)]) -> some View {
        let allStats = holes.map { stats(for: $0.element) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(TCTheme.gold)
                .tracking(1.4)
            VStack(spacing: 0) {
                gridRow(label: "Hole", values: holes.map { "\($0.element.holeNumber)" },
                        total: nil, bold: true, tappable: holes.map(\.offset))
                divider
                gridRow(label: "Par", values: holes.map { "\($0.element.par)" },
                        total: "\(holes.reduce(0) { $0 + $1.element.par })")
                divider
                gridRow(label: "Score",
                        values: holes.map { $0.element.score.map(String.init) ?? "–" },
                        total: "\(holes.compactMap { $0.element.score }.reduce(0, +))",
                        bold: true, scores: holes.map { ($0.element.score, $0.element.par) },
                        tappable: holes.map(\.offset))
                divider
                gridRow(label: "Putts",
                        values: holes.map { $0.element.putts.map(String.init) ?? "–" },
                        total: "\(holes.compactMap { $0.element.putts }.reduce(0, +))")
                divider
                gridRow(label: "Drops", values: allStats.map { $0.drops == 0 ? "·" : "\($0.drops)" },
                        total: "\(allStats.reduce(0) { $0 + $1.drops })")
                divider
                gridRow(label: "FW Bkr", values: allStats.map { $0.fwBunkers == 0 ? "·" : "\($0.fwBunkers)" },
                        total: "\(allStats.reduce(0) { $0 + $1.fwBunkers })")
                divider
                gridRow(label: "GS Bkr", values: allStats.map { $0.gsBunkers == 0 ? "·" : "\($0.gsBunkers)" },
                        total: "\(allStats.reduce(0) { $0 + $1.gsBunkers })")
            }
            .padding(.vertical, 6)
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1))
        }
    }

    private var divider: some View {
        Rectangle().fill(TCTheme.border.opacity(0.6)).frame(height: 0.5)
    }

    private func gridRow(label: String,
                         values: [String],
                         total: String?,
                         bold: Bool = false,
                         scores: [(Int?, Int)]? = nil,
                         tappable: [Int]? = nil) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(TCTheme.textMuted)
                .frame(width: 46, alignment: .leading)
                .padding(.leading, 8)
            ForEach(values.indices, id: \.self) { i in
                // Greener = better, redder = worse — instant scan of where the round went wrong.
                let color: Color = {
                    if let scores, let s = scores[i].0 {
                        let diff = s - scores[i].1
                        if diff <= -2 { return Color(red: 0.10, green: 0.85, blue: 0.45) }
                        if diff == -1 { return Color(red: 0.32, green: 0.78, blue: 0.42) }
                        if diff == 0  { return TCTheme.textPrimary }
                        if diff == 1  { return Color(red: 0.95, green: 0.62, blue: 0.30) }
                        if diff == 2  { return Color(red: 0.93, green: 0.42, blue: 0.30) }
                        return Color(red: 0.90, green: 0.26, blue: 0.26)
                    }
                    return bold ? TCTheme.textPrimary : TCTheme.textSecondary
                }()
                let scoreDiff: Int? = {
                    guard let scores, let s = scores[i].0 else { return nil }
                    return s - scores[i].1
                }()
                Group {
                    if let tappable {
                        Button { editingHoleIndex = tappable[i] } label: {
                            Text(values[i])
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            // Fix the accidental double-logged shot without re-scoring.
                            Button {
                                editingShotsHoleIndex = tappable[i]
                            } label: {
                                Label("Edit logged shots", systemImage: "figure.golf")
                            }
                        }
                    } else {
                        Text(values[i]).frame(maxWidth: .infinity)
                    }
                }
                .font(.system(size: 12, weight: bold ? .heavy : .semibold, design: .rounded))
                .foregroundColor(color)
                .background(
                    // Tint non-par score cells so the color read survives small text.
                    (scoreDiff != nil && scoreDiff != 0)
                        ? RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(color.opacity(0.14))
                            .padding(.horizontal, 1)
                        : nil
                )
            }
            Text(total ?? "")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(TCTheme.gold)
                .frame(width: 34)
        }
        .padding(.vertical, 5)
    }

    private func totalsCard(_ round: CourseRound) -> some View {
        let s = round.scoreSummary
        let toPar = s.totalScore - s.totalPar
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("TOTAL")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(TCTheme.textMuted).tracking(1.2)
                Text("\(s.totalScore)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(TCTheme.textPrimary)
            }
            Spacer()
            Text(toPar == 0 ? "E" : (toPar > 0 ? "+\(toPar)" : "\(toPar)"))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(toPar <= 0 ? TCTheme.sage : .orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(TCTheme.border, lineWidth: 1))
    }

    private struct EditingHole: Identifiable {
        let index: Int
        var id: Int { index }
    }
}
