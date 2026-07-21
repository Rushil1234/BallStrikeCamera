import SwiftUI

// MARK: - Rate + bookmark control

/// A compact bar for a course: the community rating, your own tap-to-set stars,
/// and a bookmark toggle. Loads its own state. Drop into any course context.
struct CourseSocialBar: View {
    let course: String
    let userId: UUID
    let backend: AppBackend

    @State private var summary: CourseRatingSummary = .empty
    @State private var bookmarked = false
    @State private var busy = false

    private var baseName: String { course.components(separatedBy: " ~ ").first ?? course }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rate this course")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted)
                Spacer()
                if let avg = summary.avgRating {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.system(size: 11)).foregroundColor(TCTheme.gold)
                        Text(String(format: "%.1f", avg))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(TCTheme.textPrimary)
                        Text("(\(summary.ratingCount))")
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textMuted)
                    }
                }
            }
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button { Task { await setRating(star) } } label: {
                        Image(systemName: (summary.myRating ?? 0) >= star ? "star.fill" : "star")
                            .font(.system(size: 24))
                            .foregroundColor((summary.myRating ?? 0) >= star ? TCTheme.gold : TCTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
                Spacer()
                Button { Task { await toggleBookmark() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                        Text(bookmarked ? "Saved" : "Save")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(bookmarked ? TCTheme.gold : TCTheme.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(TCTheme.panelRaised)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
        .padding(16)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
        .task { await load() }
    }

    private func load() async {
        summary = (try? await backend.courseRatingSummary(course: course)) ?? .empty
        let marks = (try? await backend.loadCourseBookmarks(userId: userId)) ?? []
        let key = baseName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        bookmarked = marks.contains { $0.baseName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == key }
    }

    private func setRating(_ r: Int) async {
        busy = true; defer { busy = false }
        try? await backend.rateCourse(userId: userId, course: course, rating: r, review: nil)
        summary = (try? await backend.courseRatingSummary(course: course)) ?? summary
    }

    private func toggleBookmark() async {
        busy = true; defer { busy = false }
        if bookmarked {
            try? await backend.removeCourseBookmark(userId: userId, course: course)
        } else {
            try? await backend.addCourseBookmark(userId: userId, course: course)
        }
        bookmarked.toggle()
    }
}

// MARK: - Saved courses list (Beli-style)

/// The user's bookmarked courses. Shown in the Locker and as a feed section.
struct SavedCoursesView: View {
    let userId: UUID
    let backend: AppBackend
    var embedded: Bool = false   // true when shown inline (no nav chrome)

    @Environment(\.dismiss) private var dismiss
    @State private var bookmarks: [CourseBookmark] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                ZStack {
                    TrueCarryBackground(pattern: .plain)
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Saved courses")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(TCTheme.textPrimary)
                                Spacer()
                                Button { dismiss() } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(TCTheme.textMuted)
                                        .frame(width: 32, height: 32)
                                        .background(TCTheme.panel).clipShape(Circle())
                                }
                            }
                            content
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, TCTheme.hPad)
                        .padding(.top, 8)
                    }
                }
                .navigationBarHidden(true)
            }
        }
        .task { await load() }
    }

    @ViewBuilder private var content: some View {
        if bookmarks.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bookmark").font(.system(size: 26)).foregroundColor(TCTheme.textUltraMuted)
                Text("No saved courses yet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                Text("Tap Save on a course to keep it here.")
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else {
            ForEach(bookmarks) { bm in
                HStack(spacing: 12) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 14))
                        .foregroundColor(TCTheme.gold)
                        .frame(width: 36, height: 36)
                        .background(TCTheme.gold.opacity(0.12))
                        .clipShape(Circle())
                    Text(bm.baseName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary)
                        .lineLimit(2)
                    Spacer()
                    Button { Task { await remove(bm) } } label: {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 16))
                            .foregroundColor(TCTheme.gold)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(TCTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
            }
        }
    }

    private func load() async {
        bookmarks = (try? await backend.loadCourseBookmarks(userId: userId)) ?? []
        loaded = true
    }

    private func remove(_ bm: CourseBookmark) async {
        try? await backend.removeCourseBookmark(userId: userId, course: bm.courseName)
        bookmarks.removeAll { $0.id == bm.id }
    }
}
