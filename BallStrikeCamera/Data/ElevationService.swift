import Foundation
import CoreLocation

/// Provides continuous elevation for slope-adjusted distance without hammering a
/// network API. On each hole we fetch ONE coarse elevation grid covering the
/// hole's bounding box (Open-Meteo Elevation API — free, no key, batched), cache
/// it, then bilinearly interpolate elevation anywhere inside it. As the player
/// walks, slope distance recomputes locally from the cached grid — no per-update
/// API calls.
@MainActor
final class ElevationService: ObservableObject {

    // Grid state (lats/lons sorted ascending; elev[latIndex][lonIndex] in meters).
    private var gridLats: [Double] = []
    private var gridLons: [Double] = []
    private var gridElev: [[Double]] = []

    /// Bumped whenever a new grid loads, so SwiftUI views recompute slope.
    @Published private(set) var revision = 0
    private(set) var isLoaded = false
    private var loadedKey: String?

    /// Yards per meter (matches the rest of the app's CL-distance → yards conversion).
    static let yardsPerMeter = 1.0936133

    // MARK: - Load

    /// Fetch+cache a grid covering the bbox of `coords` (tee, green, edges…) plus a
    /// margin so the player standing behind the tee is still inside the grid.
    /// `resolution` is the grid side length (resolution² points in one request).
    func loadGrid(around coords: [CLLocationCoordinate2D], resolution: Int = 6) async {
        let valid = coords.filter { CLLocationCoordinate2DIsValid($0) && !($0.latitude == 0 && $0.longitude == 0) }
        guard !valid.isEmpty else { return }

        var minLat = valid.map(\.latitude).min()!,  maxLat = valid.map(\.latitude).max()!
        var minLon = valid.map(\.longitude).min()!, maxLon = valid.map(\.longitude).max()!
        let mLat = max((maxLat - minLat) * 0.25, 0.0015)   // ~150m minimum margin
        let mLon = max((maxLon - minLon) * 0.25, 0.0015)
        minLat -= mLat; maxLat += mLat; minLon -= mLon; maxLon += mLon

        let key = String(format: "%.4f,%.4f,%.4f,%.4f", minLat, minLon, maxLat, maxLon)
        if key == loadedKey && isLoaded { return }   // already have a grid for this hole

        let n = max(2, resolution)
        let lats = (0..<n).map { minLat + (maxLat - minLat) * Double($0) / Double(n - 1) }
        let lons = (0..<n).map { minLon + (maxLon - minLon) * Double($0) / Double(n - 1) }

        var latList: [Double] = [], lonList: [Double] = []
        latList.reserveCapacity(n * n); lonList.reserveCapacity(n * n)
        for la in lats { for lo in lons { latList.append(la); lonList.append(lo) } }

        guard let elevs = await Self.fetchElevations(lats: latList, lons: lonList),
              elevs.count == n * n else { return }

        var grid = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n { for j in 0..<n { grid[i][j] = elevs[i * n + j] } }

        gridLats = lats; gridLons = lons; gridElev = grid
        isLoaded = true; loadedKey = key
        revision &+= 1
    }

    // MARK: - Interpolate

    /// Bilinearly interpolated elevation (meters) at a coordinate; nil if no grid.
    /// Coordinates outside the grid are clamped to the edge.
    func elevation(at c: CLLocationCoordinate2D) -> Double? {
        guard isLoaded, gridLats.count >= 2, gridLons.count >= 2 else { return nil }
        let la = min(max(c.latitude,  gridLats.first!), gridLats.last!)
        let lo = min(max(c.longitude, gridLons.first!), gridLons.last!)
        let (i0, i1, ti) = Self.bracket(gridLats, la)
        let (j0, j1, tj) = Self.bracket(gridLons, lo)
        let e00 = gridElev[i0][j0], e01 = gridElev[i0][j1]
        let e10 = gridElev[i1][j0], e11 = gridElev[i1][j1]
        let top = e00 + (e01 - e00) * tj   // interpolate along lon at lat i0
        let bot = e10 + (e11 - e10) * tj   // interpolate along lon at lat i1
        return top + (bot - top) * ti      // interpolate between the two lats
    }

    /// Returns the lower index, upper index, and fraction t∈[0,1] bracketing `v`.
    static func bracket(_ arr: [Double], _ v: Double) -> (Int, Int, Double) {
        let last = arr.count - 1
        if v <= arr.first! { return (0, min(1, last), 0) }
        if v >= arr.last!  { return (max(0, last - 1), last, 1) }
        for k in 0..<last where v >= arr[k] && v <= arr[k + 1] {
            let span = arr[k + 1] - arr[k]
            return (k, k + 1, span == 0 ? 0 : (v - arr[k]) / span)
        }
        return (max(0, last - 1), last, 1)
    }

    // MARK: - Network

    private static func fetchElevations(lats: [Double], lons: [Double]) async -> [Double]? {
        let latStr = lats.map { String(format: "%.5f", $0) }.joined(separator: ",")
        let lonStr = lons.map { String(format: "%.5f", $0) }.joined(separator: ",")
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/elevation")!
        comps.queryItems = [
            URLQueryItem(name: "latitude",  value: latStr),
            URLQueryItem(name: "longitude", value: lonStr),
        ]
        guard let url = comps.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct Response: Decodable { let elevation: [Double] }
            return try JSONDecoder().decode(Response.self, from: data).elevation
        } catch {
            return nil
        }
    }
}
