import Foundation
import CoreLocation

// MARK: - Golf geometry synthesis
//
// Free-data courses (OpenStreetMap + GolfCourseAPI) frequently give us a reliable green-CENTER
// point per hole but no traced green polygon. The rangefinder tier only needs the center to show
// distance-to-green, but the round UI still wants a polygon + front/back. These helpers synthesize
// a plausible green from a single center point (oriented by the tee when we have one), so a hole
// becomes fully renderable without proprietary geometry.
//
// The projection math mirrors the manual-setup path in CourseRoundViewModel.saveManualHoleGeometry,
// extracted here so both the view model and the data aggregator share one implementation.

enum GolfGeometry {

    /// Initial bearing (degrees) from `a` to `b`.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }

    /// Project a coordinate `distanceMeters` along `bearingDegrees` from `start`.
    static func project(from start: CLLocationCoordinate2D,
                        bearingDegrees: Double,
                        distanceMeters: Double) -> CLLocationCoordinate2D {
        let radius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let angularDistance = distanceMeters / radius

        let lat2 = asin(sin(lat1) * cos(angularDistance)
                        + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angularDistance) * cos(lat1),
                                cos(angularDistance) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi,
                                      longitude: lon2 * 180 / .pi)
    }

    /// A synthesized green (front/back/polygon) around `center`. When `tee` is provided the green is
    /// oriented along the tee→green line; otherwise it falls back to a north-aligned shape.
    struct SynthesizedGreen {
        var front: Coordinate
        var back: Coordinate
        var polygon: PolygonRing
    }

    static func synthesizeGreen(center: Coordinate, tee: Coordinate?) -> SynthesizedGreen {
        let heading = tee.map { bearing(from: $0.clCoordinate, to: center.clCoordinate) } ?? 0
        let c = center.clCoordinate
        let front = project(from: c, bearingDegrees: heading + 180, distanceMeters: 12)
        let back  = project(from: c, bearingDegrees: heading,       distanceMeters: 12)
        let left  = project(from: c, bearingDegrees: heading - 90,  distanceMeters: 10)
        let right = project(from: c, bearingDegrees: heading + 90,  distanceMeters: 10)
        return SynthesizedGreen(
            front: Coordinate(front),
            back: Coordinate(back),
            polygon: PolygonRing(coordinates: [
                Coordinate(front), Coordinate(right), Coordinate(back), Coordinate(left), Coordinate(front)
            ])
        )
    }
}

extension GolfHole {

    /// True when the hole has a green-center point usable for distance-to-green (rangefinder tier),
    /// regardless of whether a traced green polygon exists.
    var hasGreenCenter: Bool { greenCenterCoordinate != nil }

    /// Fill in a green polygon + front/back synthesized from the green center when they are missing.
    /// No-op when a real green polygon already exists or there is no center to work from.
    mutating func fillSyntheticGreenIfNeeded() {
        guard let center = greenCenterCoordinate else { return }
        guard greenPolygon == nil || (greenPolygon?.coordinates.count ?? 0) < 3 else { return }
        let synth = GolfGeometry.synthesizeGreen(center: center, tee: teeCoordinate)
        if greenFrontCoordinate == nil { greenFrontCoordinate = synth.front }
        if greenBackCoordinate == nil { greenBackCoordinate = synth.back }
        greenPolygon = synth.polygon
        if pathCoordinates == nil || (pathCoordinates?.count ?? 0) < 2 {
            if let tee = teeCoordinate {
                pathCoordinates = [tee, center]
            }
        }
    }
}
