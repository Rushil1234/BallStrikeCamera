import SwiftUI
import CoreLocation
import Combine
import MapKit

struct CourseSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AuthSessionStore
    @StateObject private var location = LocationService()
    @State private var bookmarkedKeys: Set<String> = []
    @State private var query = ""
    @State private var nearbyCourses: [GolfCourse] = []
    @State private var searchResults: [GolfCourse] = []
    @State private var isLoadingNearby = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedCourse: GolfCourse?
    @State private var searchTask: Task<Void, Never>?
    @State private var resolvingCourseId: String?
    @State private var showMap = false
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)
    )

    let userId: UUID
    let onSelect: (GolfCourse, TeeBox) -> Void

    init(userId: UUID, onSelect: @escaping (GolfCourse, TeeBox) -> Void) {
        self.userId = userId
        self.onSelect = onSelect
    }

    var body: some View {
        ZStack {
            TrueCarryBackground()

            VStack(spacing: 0) {
                // Custom header
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(TCTheme.textMuted)
                            .frame(width: 32, height: 32)
                            .background(TCTheme.panelRaised)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    TrueCarryLogo(size: 20)
                    Spacer()
                    // location status dot
                    Circle()
                        .fill(locationStatusColor)
                        .frame(width: 8, height: 8)
                        .frame(width: 32, height: 32)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(TCTheme.textMuted)
                        .font(.system(size: 15))
                    TextField("Search courses…", text: $query)
                        .foregroundColor(.black)
                        .font(.system(size: 15))
                    if !query.isEmpty {
                        Button {
                            query = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(TCTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(TCTheme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(TCTheme.border, lineWidth: 1))
                .padding(.horizontal, TCTheme.hPad)
                .padding(.vertical, 10)

                // Location prompt if denied
                if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                    HStack(spacing: 10) {
                        Image(systemName: "location.slash.fill")
                            .font(.system(size: 14))
                            .foregroundColor(TCTheme.textMuted)
                        Text("Enable location to see nearby courses.")
                            .font(.system(size: 13))
                            .foregroundColor(TCTheme.textMuted)
                        Spacer()
                        Button("Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(TCTheme.gold)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.bottom, 8)
                }

                // List / map switch
                Picker("View", selection: $showMap) {
                    Text("List").tag(false)
                    Text("Map").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, TCTheme.hPad)
                .padding(.bottom, 8)

                // Content
                if showMap {
                    courseMap
                } else {
                    courseList
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(item: $selectedCourse) { course in
            TeeSelectorSheet(course: course) { tee in
                onSelect(course, tee)
                dismiss()
            }
            .tcAppearance()
        }
        .onChange(of: query) { newVal in
            searchTask?.cancel()
            if newVal.isEmpty {
                searchResults = []
                isSearching = false
                return
            }
            let trimmed = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3 else {
                searchResults = []
                isSearching = false
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard !Task.isCancelled else { return }
                await searchCourses(query: trimmed)
            }
        }
        .onChange(of: location.currentLocation?.latitude) { _ in
            guard location.currentLocation != nil, query.isEmpty, nearbyCourses.isEmpty else { return }
            Task { await loadNearby() }
        }
        .task {
            await refreshBookmarks()
            location.requestPermission()
            // Wait briefly for location to arrive after authorization
            for _ in 0..<10 {
                if location.currentLocation != nil { break }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            if location.currentLocation != nil {
                await loadNearby()
            }
        }
    }

    // MARK: - Bookmarks

    private func bookmarkKey(_ name: String) -> String {
        (name.components(separatedBy: " ~ ").first ?? name)
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshBookmarks() async {
        let marks = (try? await session.backend.loadCourseBookmarks(userId: userId)) ?? []
        bookmarkedKeys = Set(marks.map { bookmarkKey($0.courseName) })
    }

    private func toggleBookmark(_ course: GolfCourse) async {
        let key = bookmarkKey(course.name)
        if bookmarkedKeys.contains(key) {
            try? await session.backend.removeCourseBookmark(userId: userId, course: course.name)
            bookmarkedKeys.remove(key)
        } else {
            try? await session.backend.addCourseBookmark(userId: userId, course: course.name)
            bookmarkedKeys.insert(key)
        }
    }


    // MARK: - Content views

    private var courseList: some View {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Nearby section
                        if query.isEmpty {
                            if isLoadingNearby {
                                HStack {
                                    ProgressView()
                                        .tint(TCTheme.sage)
                                    Text("Finding nearby courses…")
                                        .font(.system(size: 13))
                                        .foregroundColor(TCTheme.textMuted)
                                }
                                .padding(.horizontal, TCTheme.hPad)
                                .padding(.vertical, 16)
                            } else if !nearbyCourses.isEmpty {
                                sectionHeader("NEARBY COURSES")
                                ForEach(nearbyCourses) { course in
                                    courseRow(course)
                                }
                            } else if location.authorizationStatus == .notDetermined {
                                locationPromptRow
                            }
                        }

                        // Search results section
                        if !query.isEmpty {
                            if isSearching {
                                HStack {
                                    ProgressView()
                                        .tint(TCTheme.gold)
                                    Text("Searching…")
                                        .font(.system(size: 13))
                                        .foregroundColor(TCTheme.textMuted)
                                }
                                .padding(.horizontal, TCTheme.hPad)
                                .padding(.vertical, 16)
                            } else {
                                sectionHeader("RESULTS")
                                if searchResults.isEmpty {
                                    Text("No courses found. Try a different search.")
                                        .font(.system(size: 14))
                                        .foregroundColor(TCTheme.textMuted)
                                        .padding(.horizontal, TCTheme.hPad)
                                        .padding(.vertical, 20)
                                } else {
                                    ForEach(searchResults) { course in
                                        courseRow(course)
                                    }
                                }
                            }
                        }

                        // Error
                        if let err = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(TCTheme.gold)
                                    .font(.system(size: 13))
                                Text(err)
                                    .font(.system(size: 13))
                                    .foregroundColor(TCTheme.textMuted)
                            }
                            .padding(.horizontal, TCTheme.hPad)
                            .padding(.vertical, 12)
                        }

                        Spacer(minLength: 60)
                    }
                }
    }

    private struct MapCourse: Identifiable {
        let id: String
        let course: GolfCourse
        let coord: CLLocationCoordinate2D
    }

    private var mapCourses: [MapCourse] {
        let list = query.isEmpty ? nearbyCourses : searchResults
        let raw = list.compactMap { c in
            c.coordinate.map { MapCourse(id: c.id, course: c, coord: $0) }
        }
        return Self.spreadColocated(raw)
    }

    /// Fan out pins that share (nearly) the same coordinate — e.g. multiple courses at one
    /// facility (Flanders Valley Blue/White + Red/Gold) — so they don't stack exactly on top of
    /// each other. Each colocated pin is nudged onto a small circle around the shared point.
    private static func spreadColocated(_ items: [MapCourse]) -> [MapCourse] {
        func key(_ c: CLLocationCoordinate2D) -> String {
            String(format: "%.4f,%.4f", c.latitude, c.longitude)   // ~11 m bucket
        }
        var groups: [String: [MapCourse]] = [:]
        for it in items { groups[key(it.coord), default: []].append(it) }

        return items.map { it in
            let group = groups[key(it.coord)] ?? [it]
            guard group.count > 1, let idx = group.firstIndex(where: { $0.id == it.id }) else { return it }
            let radiusM = 65.0
            let angle = (2 * Double.pi / Double(group.count)) * Double(idx)
            let dLat = (radiusM * cos(angle)) / 111_111.0
            let dLon = (radiusM * sin(angle)) / (111_111.0 * cos(it.coord.latitude * .pi / 180))
            let nudged = CLLocationCoordinate2D(latitude: it.coord.latitude + dLat,
                                                longitude: it.coord.longitude + dLon)
            return MapCourse(id: it.id, course: it.course, coord: nudged)
        }
    }

    private var courseMap: some View {
        Map(coordinateRegion: $mapRegion, showsUserLocation: true, annotationItems: mapCourses) { item in
            MapAnnotation(coordinate: item.coord) {
                Button {
                    Task { await selectCourse(item.course) }
                } label: {
                    VStack(spacing: 2) {
                        ZStack {
                            Circle()
                                .fill(TCTheme.gold)
                                .frame(width: 26, height: 26)
                                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                            if resolvingCourseId == item.course.id {
                                ProgressView().tint(.white).scaleEffect(0.6)
                            } else {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        Text(item.course.name)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                            .frame(maxWidth: 110)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, TCTheme.hPad)
        .padding(.bottom, 12)
        .onAppear { fitMapRegion() }
        .onChange(of: mapCourses.map(\.id)) { _ in fitMapRegion() }
    }

    private func fitMapRegion() {
        let coords = mapCourses.map(\.coord)
        guard !coords.isEmpty else {
            if let user = location.currentLocation {
                mapRegion = MKCoordinateRegion(
                    center: user,
                    span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35))
            }
            return
        }
        var minLat = coords[0].latitude, maxLat = coords[0].latitude
        var minLon = coords[0].longitude, maxLon = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        mapRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.05, (maxLat - minLat) * 1.5),
                                   longitudeDelta: max(0.05, (maxLon - minLon) * 1.5)))
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(TCTheme.textMuted)
            .tracking(1.5)
            .padding(.horizontal, TCTheme.hPad)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func courseRow(_ course: GolfCourse) -> some View {
        VStack(spacing: 0) {
            Button {
                Task { await selectCourse(course) }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(TCTheme.sage.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "flag.fill")
                            .font(.system(size: 16))
                            .foregroundColor(TCTheme.sage)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(course.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(TCTheme.textPrimary)
                            .lineLimit(2)
                        Text([course.city, course.state].filter { !$0.isEmpty }.joined(separator: ", "))
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textMuted)
                        HStack(spacing: 6) {
                            if course.hasFullHoleData || course.source == .merged {
                                courseBadge("GPS Map", TCTheme.gold)
                            } else if course.hasPartialHoleData || course.hasRealGeometry {
                                courseBadge("Partial Map", TCTheme.sage)
                            } else {
                                courseBadge("No GPS map yet", TCTheme.textMuted)
                            }
                            if course.teeBoxes.contains(where: { $0.totalYards > 0 }) {
                                courseBadge("\(course.teeBoxes.count) Tees", TCTheme.sage)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    // Bookmark toggle — save a course to play later without selecting it.
                    // Nested inside the row button; SwiftUI hit-tests the inner button first.
                    Button { Task { await toggleBookmark(course) } } label: {
                        Image(systemName: bookmarkedKeys.contains(bookmarkKey(course.name)) ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(bookmarkedKeys.contains(bookmarkKey(course.name)) ? TCTheme.gold : TCTheme.textUltraMuted)
                            .frame(width: 30, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .trailing, spacing: 3) {
                        if resolvingCourseId == course.id {
                            ProgressView()
                                .tint(TCTheme.gold)
                                .scaleEffect(0.75)
                        } else if let dist = distanceText(for: course) {
                            Text(dist)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(TCTheme.cyan)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(TCTheme.textUltraMuted)
                    }
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            Rectangle()
                .fill(TCTheme.border)
                .frame(height: 1)
                .padding(.leading, TCTheme.hPad + 58)
        }
    }

    private func courseBadge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var locationPromptRow: some View {
        Button {
            location.requestPermission()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(TCTheme.sage)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Location")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("See courses near you automatically.")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            .padding(.horizontal, TCTheme.hPad)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var locationStatusColor: Color {
        switch location.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return location.currentLocation != nil ? TCTheme.sage : TCTheme.gold
        case .denied, .restricted:
            return TCTheme.danger
        default:
            return TCTheme.textUltraMuted
        }
    }

    private func distanceText(for course: GolfCourse) -> String? {
        guard let user = location.currentLocation,
              let lat = course.latitude, let lon = course.longitude else { return nil }
        let miles = LocationService.distanceInYards(
            from: user,
            to: CLLocationCoordinate2D(latitude: lat, longitude: lon)
        ) / 1760.0
        return String(format: "%.1f mi", miles)
    }

    // MARK: - Data loading

    private func loadNearby() async {
        guard let userLoc = location.currentLocation else { return }
        isLoadingNearby = true
        errorMessage = nil
        defer { isLoadingNearby = false }
        // Use Supabase catalog so only real golf courses appear (MKLocalSearch lets
        // venues like Topgolf / Xgolf slip through as "golf courses").
        // Pull the RPC max (50): multi-course facilities (e.g. Flanders Valley's Blue/White AND
        // Red/Gold) sit adjacent in distance ranking, so a small limit clips the second course.
        // onlyGeometry: nearby shows just GPS-ready courses — unmapped ones surface only
        // when the player searches for them by name.
        // OUR database only: when it's unreachable, say so — never MapKit/OSM stand-ins.
        guard let catalog = await CourseCatalog.searchChecked(query: "", near: userLoc, limit: 50, onlyGeometry: true) else {
            errorMessage = "Couldn't reach the course database. Check your connection and try again."
            nearbyCourses = []
            return
        }
        nearbyCourses = catalog.sorted {
            (distanceMiles(course: $0, user: userLoc) ?? .infinity)
                < (distanceMiles(course: $1, user: userLoc) ?? .infinity)
        }
    }

    private func searchCourses(query: String) async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        // Our course catalog ONLY — 46k+ courses, so the user can find ANY course (geometry
        // loads on open for the ones we've mapped; others still appear, "map coming soon").
        // No MapKit/GolfCourseAPI fallbacks: if the database is down, that's an error.
        guard let catalog = await CourseCatalog.searchChecked(query: query, near: location.currentLocation) else {
            searchResults = []
            errorMessage = "Couldn't reach the course database. Check your connection and try again."
            return
        }
        searchResults = catalog
        if catalog.isEmpty {
            errorMessage = "No courses found. Try a shorter name."
        }
    }

    private func selectCourse(_ course: GolfCourse) async {
        resolvingCourseId = course.id
        defer { resolvingCourseId = nil }
        // MapKit stubs have synthetic non-UUID ids. Resolve them through the Supabase catalog
        // first to get a real UUID so geometry fetch works the same as when searching by name.
        let resolved = course.source == .mapKit
            ? await resolveToCatalogCourse(course)
            : course
        selectedCourse = await resolveCourseForSetup(resolved)
    }

    /// Looks the MapKit stub up in the Supabase course catalog by name + location so the
    /// selected course has a UUID that CourseCatalog.geometry can fetch directly from Storage.
    private func resolveToCatalogCourse(_ course: GolfCourse) async -> GolfCourse {
        let matches = await CourseCatalog.search(
            query: course.name,
            near: course.coordinate,
            limit: 5
        )
        // Only accept a match whose name overlaps, or that sits within ~1.2 miles of
        // the MapKit pin — an arbitrary first result can silently load the wrong course.
        let best = matches.first { namesOverlap($0.name, course.name) }
            ?? matches.first { m in
                guard let a = m.coordinate, let b = course.coordinate else { return false }
                return CLLocation(latitude: a.latitude, longitude: a.longitude)
                    .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) < 2_000
            }
        return best ?? course
    }

    private func resolveCourseForSetup(_ course: GolfCourse) async -> GolfCourse {
        if hasUsableTees(course) {
            return course
        }
        // Pull the licensed pro course (real named tees + verified geometry) from Supabase so the
        // tee picker shows Blue / White / Red etc. up front. enrich() falls back to a GolfCourseAPI
        // scorecard, then the original stub, when a course isn't in the pro dataset yet.
        let enriched = await CourseDataAggregator.shared.enrich(course)
        return hasUsableTees(enriched) ? enriched : course
    }

    private func hasUsableTees(_ course: GolfCourse) -> Bool {
        course.teeBoxes.contains { $0.totalYards > 0 }
    }

    private func bestCourseMatch(_ results: [GolfCourse], to course: GolfCourse) -> GolfCourse? {
        guard !results.isEmpty else { return nil }
        let target = course.coordinate
        return results.min { lhs, rhs in
            score(lhs, target: target, name: course.name) < score(rhs, target: target, name: course.name)
        }
    }

    private func score(_ candidate: GolfCourse,
                       target: CLLocationCoordinate2D?,
                       name: String) -> Double {
        var score = 0.0
        if !hasUsableTees(candidate) { score += 10_000 }
        if candidate.holes.isEmpty { score += 5_000 }
        if !namesOverlap(candidate.name, name) { score += 2_500 }
        if let target, let lat = candidate.latitude, let lon = candidate.longitude {
            score += LocationService.distanceInYards(
                from: target,
                to: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            )
        } else {
            score += 4_000
        }
        return score
    }

    private func namesOverlap(_ a: String, _ b: String) -> Bool {
        let ignored: Set<String> = ["the", "golf", "club", "course", "country", "links"]
        func tokens(_ value: String) -> Set<String> {
            Set(value.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !ignored.contains($0) })
        }
        return !tokens(a).isDisjoint(with: tokens(b))
    }

    private func mapKitCourse(from item: MKMapItem) -> GolfCourse? {
        guard let name = item.name else { return nil }
        let coord = item.placemark.coordinate
        let sid = "\(name)-\(Int(coord.latitude * 1000))-\(Int(coord.longitude * 1000))"
        let tees = [TeeBox(id: "\(sid)-gps", name: "Course GPS", color: "Gray", totalYards: 0)]
        return GolfCourse(
            id: sid,
            name: name,
            city: item.placemark.locality ?? "",
            state: item.placemark.administrativeArea ?? "",
            country: item.placemark.countryCode ?? "US",
            latitude: coord.latitude,
            longitude: coord.longitude,
            holes: [],
            teeBoxes: tees,
            source: .mapKit,
            cachedAt: Date()
        )
    }

    private func distanceMiles(course: GolfCourse, user: CLLocationCoordinate2D) -> Double? {
        guard let lat = course.latitude, let lon = course.longitude else { return nil }
        return LocationService.distanceInYards(
            from: user,
            to: CLLocationCoordinate2D(latitude: lat, longitude: lon)
        ) / 1760.0
    }
}

// MARK: - Tee Selector Sheet

private struct TeeSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AuthSessionStore
    let course: GolfCourse
    let onSelect: (TeeBox) -> Void
    @State private var showReportDialog = false
    @State private var reportResult: String?

    var body: some View {
        ZStack {
            TrueCarryBackground()
            VStack(spacing: 0) {
                // Cancel button row
                HStack {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(TCTheme.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(TCTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 14)
                .padding(.bottom, 10)

                // Title + course name
                VStack(alignment: .leading, spacing: 3) {
                    Text("Select Tees")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text(course.name)
                        .font(.system(size: 13))
                        .foregroundColor(TCTheme.textMuted)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TCTheme.hPad)
                .padding(.bottom, 12)

                Divider().opacity(0.4)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        if course.source == .mapKit || !course.teeBoxes.contains(where: { $0.totalYards > 0 }) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(TCTheme.gold)
                                Text("True Carry verifies tee, green, and route geometry before Course Mode opens.")
                                    .font(.system(size: 11))
                                    .foregroundColor(TCTheme.textMuted)
                            }
                            .padding(.bottom, 2)
                        }
                        // Always longest tee first, whatever order the source emitted;
                        // 0-yard (unknown distance) tees sink to the bottom.
                        ForEach(course.teeBoxes.sorted {
                            ($0.totalYards > 0 ? $0.totalYards : -1) > ($1.totalYards > 0 ? $1.totalYards : -1)
                        }) { tee in
                            teeRow(tee)
                        }
                        if course.teeBoxes.isEmpty {
                            Text("No tee boxes available.")
                                .font(.system(size: 14))
                                .foregroundColor(TCTheme.textMuted)
                                .padding(.top, 40)
                        }

                        // Bad tees / yardages / map? Files into the course_data_requests queue.
                        Button { showReportDialog = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.bubble")
                                    .font(.system(size: 12))
                                Text("Report a problem with this course")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(TCTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 18)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .confirmationDialog(
            "Report a course error",
            isPresented: $showReportDialog,
            titleVisibility: .visible
        ) {
            Button("Wrong or missing tees") { submitCourseIssue("Wrong or missing tees") }
            Button("Wrong yardage or par") { submitCourseIssue("Wrong yardage or par") }
            Button("Map / hole layout wrong") { submitCourseIssue("Map / hole layout wrong") }
            Button("Duplicate or wrong course") { submitCourseIssue("Duplicate or wrong course") }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Course report", isPresented: Binding(
            get: { reportResult != nil },
            set: { if !$0 { reportResult = nil } }
        )) {
            Button("OK", role: .cancel) { reportResult = nil }
        } message: {
            Text(reportResult ?? "")
        }
    }

    /// Files a course-data error report into the support queue.
    private func submitCourseIssue(_ issue: String) {
        guard let userId = session.currentUser?.id,
              let supabase = session.backend as? SupabaseBackendService else {
            reportResult = "Sign in with an online account to report course issues."
            return
        }
        Task {
            do {
                try await supabase.reportCourseIssue(courseId: course.id,
                                                     courseName: course.name,
                                                     issue: issue,
                                                     holeNumber: nil,
                                                     userId: userId)
                reportResult = "Thanks — we'll review \(course.name)."
            } catch {
                reportResult = "Couldn't send the report. Try again later."
            }
        }
    }

    private func teeRow(_ tee: TeeBox) -> some View {
        Button { onSelect(tee); dismiss() } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(teeColor(tee.color))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text(tee.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                    HStack(spacing: 10) {
                        let displayYards = course.displayYards(for: tee)
                        if displayYards > 0 {
                            Text("\(displayYards) yd")
                                .font(.system(size: 12))
                                .foregroundColor(TCTheme.textMuted)
                        } else {
                            Text("GPS estimate")
                                .font(.system(size: 12))
                                .foregroundColor(TCTheme.textMuted)
                        }
                        if let r = tee.rating {
                            Text("Rating \(String(format: "%.1f", r))")
                                .font(.system(size: 12))
                                .foregroundColor(TCTheme.textMuted)
                        }
                        if let s = tee.slope {
                            Text("Slope \(s)")
                                .font(.system(size: 12))
                                .foregroundColor(TCTheme.textMuted)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func teeColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "black":          return .black
        case "blue":           return .blue
        case "white":          return .white
        case "red":            return .red
        case "gold", "yellow": return TCTheme.gold
        case "green":          return TCTheme.sage
        case "silver", "gray", "grey":
            return Color(white: 0.68)
        default:               return TCTheme.textMuted
        }
    }
}
