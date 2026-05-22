import SwiftUI
import CoreLocation
import Combine
import MapKit

struct CourseSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var location = LocationService()
    @State private var query = ""
    @State private var nearbyCourses: [GolfCourse] = []
    @State private var searchResults: [GolfCourse] = []
    @State private var isLoadingNearby = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedCourse: GolfCourse?
    @State private var searchTask: Task<Void, Never>?
    @State private var resolvingCourseId: String?

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
                    TrueCarryLogo(size: 16)
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
                        .foregroundColor(.white)
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

                // Content
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
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await searchCourses(query: trimmed)
            }
        }
        .onChange(of: location.currentLocation?.latitude) { _ in
            guard location.currentLocation != nil, query.isEmpty, nearbyCourses.isEmpty else { return }
            Task { await loadNearby() }
        }
        .task {
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
                            .lineLimit(1)
                        Text([course.city, course.state].filter { !$0.isEmpty }.joined(separator: ", "))
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textMuted)
                        HStack(spacing: 6) {
                            if !course.teeBoxes.isEmpty {
                                courseBadge("\(course.teeBoxes.count) Tees", TCTheme.gold)
                            }
                            if !course.holes.isEmpty {
                                courseBadge("Scorecard", TCTheme.sage)
                            }
                            if course.holes.contains(where: { $0.greenCenterCoordinate != nil }) {
                                courseBadge("GPS Map", TCTheme.gold)
                            } else {
                                courseBadge("Map Check", TCTheme.textMuted)
                            }
                        }
                    }
                    Spacer(minLength: 0)
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
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "golf course"
            request.region = MKCoordinateRegion(center: userLoc, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
            let response = try await MKLocalSearch(request: request).start()
            nearbyCourses = response.mapItems.compactMap { mapKitCourse(from: $0) }
                .sorted { (distanceMiles(course: $0, user: userLoc) ?? .infinity) < (distanceMiles(course: $1, user: userLoc) ?? .infinity) }
        } catch {
            errorMessage = "Couldn't load nearby courses."
            nearbyCourses = []
        }
    }

    private func searchCourses(query: String) async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            // MapKit first — it's location-aware and matches the familiar map-based experience.
            // GolfCourseAPI search is a global text lookup with no geographic ranking, so it's only
            // a fallback when MapKit finds nothing. Scorecard + pre-baked GPS geometry are still
            // resolved on selection (resolveCourseForSetup / CourseDataAggregator.enrich).
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query + " golf"
            let response = try await MKLocalSearch(request: request).start()
            let mapKitResults = response.mapItems.compactMap { mapKitCourse(from: $0) }
            if !mapKitResults.isEmpty {
                searchResults = mapKitResults
                return
            }

            let provider = CourseProviderFactory.make(userId: userId)
            let apiResults = try await provider.searchCourses(query: query, near: location.currentLocation)
            searchResults = apiResults
            if searchResults.isEmpty {
                errorMessage = "No courses found. Try a shorter name."
            }
        } catch {
            searchResults = []
            errorMessage = "Search unavailable. Check your connection."
        }
    }

    private func selectCourse(_ course: GolfCourse) async {
        resolvingCourseId = course.id
        defer { resolvingCourseId = nil }
        selectedCourse = await resolveCourseForSetup(course)
    }

    private func resolveCourseForSetup(_ course: GolfCourse) async -> GolfCourse {
        if hasUsableTees(course) {
            return course
        }
        guard GolfCourseAPIConfig.isConfigured else { return course }
        do {
            let provider = GolfCourseAPIProvider(userId: userId)
            let results = try await provider.searchCourses(query: course.name, near: course.coordinate)
            guard let best = bestCourseMatch(results, to: course) else { return course }
            if best.holes.isEmpty {
                return (try? await provider.loadCourseDetails(courseId: best.id)) ?? best
            }
            return best
        } catch {
            #if DEBUG
            print("[CourseSearch] API tee resolve failed: \(error.localizedDescription)")
            #endif
            return course
        }
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
    let course: GolfCourse
    let onSelect: (TeeBox) -> Void

    var body: some View {
        ZStack {
            TrueCarryBackground()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .font(.system(size: 15))
                            .foregroundColor(TCTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    VStack(spacing: 2) {
                        Text("Select Tees")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(TCTheme.textPrimary)
                        Text(course.name)
                            .font(.system(size: 11))
                            .foregroundColor(TCTheme.textMuted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Color.clear.frame(width: 60)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 14)
                .padding(.bottom, 10)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        if course.source == .mapKit || !course.teeBoxes.contains(where: { $0.totalYards > 0 }) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(TCTheme.gold)
                                Text("True Carry verifies tee, green, and route geometry before Course Mode opens.")
                                    .font(.system(size: 11))
                                    .foregroundColor(TCTheme.textMuted)
                            }
                            .padding(.horizontal, TCTheme.hPad)
                            .padding(.bottom, 4)
                        }
                        ForEach(course.teeBoxes) { tee in
                            teeRow(tee)
                        }
                        if course.teeBoxes.isEmpty {
                            Text("No tee boxes available.")
                                .font(.system(size: 14))
                                .foregroundColor(TCTheme.textMuted)
                                .padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
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
                        if tee.totalYards > 0 {
                            Text("\(tee.totalYards) yd")
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
