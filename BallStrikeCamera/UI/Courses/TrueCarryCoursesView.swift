import SwiftUI

struct TrueCarryCoursesView: View {
    @EnvironmentObject var session: AuthSessionStore
    @EnvironmentObject var camera: CameraController
    @State private var selectedCoursesTab = "My Courses"
    @State private var showCourseSearch  = false
    @State private var showCourseMode    = false
    @State private var showProfile       = false
    @State private var selectedCourse: GolfCourse?
    @State private var selectedTeeBox: TeeBox?
    @State private var rounds: [CourseRound] = []
    private let coursesTabs = ["My Courses", "Bucket List", "Discover"]

    // MARK: - Derived helpers

    private var userInitials: String {
        let name = session.userProfile?.displayName ?? session.currentUser?.name ?? "G"
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2, let f = parts[0].first, let l = parts[1].first {
            return "\(f)\(l)"
        }
        return String(name.prefix(2)).uppercased()
    }

    private var firstName: String {
        let name = session.userProfile?.displayName ?? session.currentUser?.name ?? "Golfer"
        return name.components(separatedBy: " ").first ?? name
    }

    private var uniqueCoursesCount: Int { Set(rounds.map { $0.courseId }).count }

    private var courseRankings: [(id: String, name: String, count: Int, seed: Int)] {
        var counts: [String: (name: String, count: Int)] = [:]
        for round in rounds {
            let existing = counts[round.courseId] ?? (name: round.courseName, count: 0)
            counts[round.courseId] = (name: existing.name, count: existing.count + 1)
        }
        return counts.sorted { $0.value.count > $1.value.count }
            .enumerated()
            .map { i, pair in (id: pair.key, name: pair.value.name, count: pair.value.count, seed: i % 4) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            TrueCarryBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TCHeaderBar(initials: userInitials) {
                        TCIconButton(icon: "magnifyingglass") { showCourseSearch = true }
                        TCProfileAvatarButton(initials: userInitials) { showProfile = true }
                    }
                    VStack(spacing: TCTheme.sectionGap) {
                        TCUnderlineTabs(tabs: coursesTabs, selected: $selectedCoursesTab)
                        journeyCard
                        courseRankingSection
                        discoverCard
                        Spacer(minLength: 140)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 8)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showCourseSearch) {
            if let uid = session.currentUser?.id {
                NavigationStack {
                    CourseSearchView(userId: uid) { course, tee in
                        selectedCourse = course
                        selectedTeeBox = tee
                        showCourseSearch = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showCourseMode = true
                        }
                    }
                }
                .preferredColorScheme(.dark)
            }
        }
        .fullScreenCover(isPresented: $showCourseMode) {
            if let uid   = session.currentUser?.id,
               let course = selectedCourse,
               let tee   = selectedTeeBox {
                CourseModeGPSHoleView(
                    userId: uid,
                    backend: session.backend,
                    initialCourse: course,
                    initialTeeBox: tee
                )
            }
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack { TrueCarryProfileView() }
                .preferredColorScheme(.dark)
        }
        .task {
            rounds = (try? await session.backend.loadCourseRounds(
                userId: session.currentUser?.id ?? UUID()
            )) ?? []
        }
    }

    // MARK: - Journey Card

    private var journeyCard: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(firstName)'s Journey")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Your complete golfing history in one place.")
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 0) {
                TCStatGroup(
                    icon: "flag.fill",
                    value: "\(uniqueCoursesCount)",
                    label: "Courses\nPlayed",
                    color: TCTheme.sage
                )
                TCStatGroup(
                    icon: "number",
                    value: "\(rounds.count)",
                    label: "Total\nRounds",
                    color: TCTheme.gold
                )
                TCStatGroup(
                    icon: "scope",
                    value: rounds.isEmpty ? "—" : "\(rounds.reduce(0) { $0 + $1.scoreSummary.totalPutts })",
                    label: "Total\nPutts",
                    color: TCTheme.cyan
                )
                TCStatGroup(
                    icon: "chart.bar",
                    value: "—",
                    label: "Current\nHandicap",
                    color: TCTheme.gold
                )
            }
        }
        .tcCard()
    }

    // MARK: - Course Ranking Section

    private var courseRankingSection: some View {
        VStack(spacing: 12) {
            HStack {
                TCSectionHeader(title: "My Course Ranking")
                Spacer()
                Button {
                    showCourseSearch = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add Course")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(TCTheme.gold)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            if courseRankings.isEmpty {
                Text("No courses played yet. Tap \"Add Course\" to log your first round.")
                    .font(.system(size: 13))
                    .foregroundColor(TCTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .tcCard()
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(courseRankings.prefix(5).enumerated()), id: \.element.id) { i, entry in
                        TCRankingRow(
                            rank: i + 1,
                            courseName: entry.name,
                            location: "—",
                            playedCount: entry.count,
                            rating: 0,
                            thumbnailSeed: entry.seed
                        )
                    }
                }
            }
        }
    }

    // MARK: - Discover Card

    private var discoverCard: some View {
        Button {
            showCourseSearch = true
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Discover")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(TCTheme.textMuted)
                        .tracking(1.4)
                    Text("Top Courses")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("Explore highly rated courses curated by golfers like you.")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted)
            }
            .tcCard()
        }
        .buttonStyle(.plain)
    }
}
