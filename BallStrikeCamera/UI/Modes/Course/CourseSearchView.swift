import SwiftUI
import CoreLocation

struct CourseSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var location = LocationService()
    @State private var query = ""
    @State private var courses: [GolfCourse] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedCourse: GolfCourse? = nil
    @State private var showTeeSelector = false

    let onSelect: (GolfCourse, TeeBox) -> Void

    private let provider: CourseProvider

    init(userId: UUID, onSelect: @escaping (GolfCourse, TeeBox) -> Void) {
        self.provider = CourseProviderFactory.make(userId: userId)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BallStrikeBackgroundView()
                VStack(spacing: 0) {
                    searchBar
                    if isSearching {
                        ProgressView()
                            .tint(BSTheme.electricCyan)
                            .padding(.top, 40)
                        Spacer()
                    } else if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 14))
                            .foregroundColor(BSTheme.dangerRed)
                            .padding(.top, 40)
                        Spacer()
                    } else {
                        courseList
                    }
                }
            }
            .navigationTitle("Find Course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(BSTheme.textMuted)
                }
            }
            .sheet(item: $selectedCourse) { course in
                TeeSelectorView(course: course) { tee in
                    onSelect(course, tee)
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            location.requestPermission()
            await search(query: "")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(BSTheme.textMuted)
                .font(.system(size: 15))
            TextField("Course name or city…", text: $query)
                .foregroundColor(.white)
                .font(.system(size: 15))
                .onSubmit { Task { await search(query: query) } }
            if !query.isEmpty {
                Button { query = ""; Task { await search(query: "") } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(BSTheme.textMuted)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(BSTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(BSTheme.border, lineWidth: 1))
        .padding(.horizontal, BSTheme.hPad)
        .padding(.vertical, 12)
    }

    private var courseList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(courses) { course in
                    CourseResultRow(course: course, userLocation: location.currentLocation)
                        .onTapGesture { selectedCourse = course }
                }
                if courses.isEmpty {
                    Text("No courses found.")
                        .font(.system(size: 14))
                        .foregroundColor(BSTheme.textMuted)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, BSTheme.hPad)
            .padding(.bottom, 32)
        }
    }

    private func search(query: String) async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            courses = try await provider.searchCourses(
                query: query,
                near: location.currentLocation
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Course Result Row

private struct CourseResultRow: View {
    let course: GolfCourse
    let userLocation: CLLocationCoordinate2D?

    private var distanceText: String? {
        guard let user = userLocation,
              let lat = course.latitude, let lon = course.longitude else { return nil }
        let dist = LocationService.distanceInYards(
            from: user,
            to: CLLocationCoordinate2D(latitude: lat, longitude: lon)
        )
        let miles = dist / 1760
        return String(format: "%.1f mi", miles)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BSTheme.fairwayGreen.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "flag.fill")
                    .font(.system(size: 18))
                    .foregroundColor(BSTheme.fairwayGreen)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(course.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSTheme.textPrimary)
                Text([course.city, course.state].filter { !$0.isEmpty }.joined(separator: ", "))
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let dist = distanceText {
                    Text(dist)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BSTheme.electricCyan)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(BSTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(BSTheme.border, lineWidth: 1))
    }
}

// MARK: - Tee Selector

private struct TeeSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    let course: GolfCourse
    let onSelect: (TeeBox) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                BallStrikeBackgroundView()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(course.teeBoxes) { tee in
                            TeeRow(tee: tee)
                                .onTapGesture { onSelect(tee); dismiss() }
                        }
                    }
                    .padding(.horizontal, BSTheme.hPad)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Select Tees")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(BSTheme.textMuted)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct TeeRow: View {
    let tee: TeeBox
    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(teeColor)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(tee.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(BSTheme.textPrimary)
                HStack(spacing: 10) {
                    Text("\(tee.totalYards) yd")
                        .font(.system(size: 12))
                        .foregroundColor(BSTheme.textMuted)
                    if let rating = tee.rating {
                        Text("Rating \(String(format: "%.1f", rating))")
                            .font(.system(size: 12))
                            .foregroundColor(BSTheme.textMuted)
                    }
                    if let slope = tee.slope {
                        Text("Slope \(slope)")
                            .font(.system(size: 12))
                            .foregroundColor(BSTheme.textMuted)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(BSTheme.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(BSTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(BSTheme.border, lineWidth: 1))
    }

    private var teeColor: Color {
        switch tee.color.lowercased() {
        case "black": return .black
        case "blue":  return .blue
        case "white": return .white
        case "red":   return .red
        case "gold", "yellow": return BSTheme.gold
        case "green": return BSTheme.fairwayGreen
        default:      return BSTheme.textMuted
        }
    }
}
