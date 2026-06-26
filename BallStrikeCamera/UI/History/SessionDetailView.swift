import SwiftUI

// MARK: - Session type wrapper (Identifiable for sheet/NavigationLink use)

enum SessionItem: Identifiable {
    case range(PracticeSession)
    case sim(SimSession)
    case course(CourseRound)

    var id: UUID {
        switch self {
        case .range(let s):  return s.id
        case .sim(let s):    return s.id
        case .course(let r): return r.id
        }
    }

    var shotIds: [UUID] {
        switch self {
        case .range(let s):  return s.shotIds
        case .sim(let s):    return s.shotIds
        case .course(let r): return r.shotIds
        }
    }

    var displayName: String {
        switch self {
        case .range(let s):  return s.name.isEmpty ? "Range Session" : s.name
        case .sim(let s):    return s.name.isEmpty ? "Sim Session" : s.name
        case .course(let r): return r.name.isEmpty ? r.courseName : r.name
        }
    }

    var icon: String {
        switch self {
        case .range:  return "scope"
        case .sim:    return "display"
        case .course: return "flag.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .range:  return TCTheme.sage
        case .sim:    return TCTheme.gold
        case .course: return TCTheme.sage
        }
    }

    var startedAt: Date {
        switch self {
        case .range(let s):  return s.startedAt
        case .sim(let s):    return s.startedAt
        case .course(let r): return r.startedAt
        }
    }

    var subtitle: String {
        switch self {
        case .range(let s):  return s.selectedClubName.map { "Club: \($0)" } ?? "All Clubs"
        case .sim(let s):    return s.provider.rawValue + (s.usedOpenGolfSim ? " · OGS" : "")
        case .course(let r): return "\(r.courseName) · \(r.teeBoxName) Tees"
        }
    }
}

// MARK: - SessionDetailView

struct SessionDetailView: View {
    @EnvironmentObject var session: AuthSessionStore
    let item: SessionItem

    @State private var shots: [SavedShot] = []
    @State private var isLoading = true
    // Shot deletion / multi-select
    @State private var isSelecting = false
    @State private var selectedShotIDs: Set<UUID> = []
    @State private var showDeleteSelected = false
    @State private var shotToDelete: SavedShot?
    @State private var deleteError: String?

    /// Range/sim sessions render the per-shot list; course rounds use the shot map instead.
    private var showsShotsList: Bool {
        if case .course = item { return false }
        return true
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            Group {
                if isLoading {
                    ProgressView()
                        .tint(TCTheme.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: TCTheme.sectionGap) {
                            headerCard
                            if case .range(let rs) = item { rangeStatsCard(rs) }
                            if case .course(let r)  = item { courseStatsCard(r) }
                            if case .course(let r)  = item {
                                let hasMap = !r.nfcShots.isEmpty || shots.contains { $0.shotLatitude != nil }
                                if hasMap { roundShotLogSection(r, shots: shots) }
                            }
                            if case .course = item { EmptyView() } else { shotsSection }
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, TCTheme.hPad)
                        .padding(.top, 12)
                    }
                }
            }
        }
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if showsShotsList && !shots.isEmpty {
                    if isSelecting {
                        Button("Done") { exitSelection() }.foregroundColor(TCTheme.sage)
                    } else {
                        Button { startSelection() } label: { Image(systemName: "checkmark.circle") }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionActionBar }
        }
        .confirmationDialog("Delete this shot?",
                            isPresented: Binding(get: { shotToDelete != nil }, set: { if !$0 { shotToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete shot", role: .destructive) {
                if let s = shotToDelete { Task { await deleteShots([s.id]) } }
                shotToDelete = nil
            }
            Button("Cancel", role: .cancel) { shotToDelete = nil }
        } message: {
            Text("This removes the shot from your history and cannot be undone.")
        }
        .confirmationDialog("Delete \(selectedShotIDs.count) shot\(selectedShotIDs.count == 1 ? "" : "s")?",
                            isPresented: $showDeleteSelected, titleVisibility: .visible) {
            Button("Delete \(selectedShotIDs.count) shot\(selectedShotIDs.count == 1 ? "" : "s")", role: .destructive) {
                Task { await deleteShots(Array(selectedShotIDs)) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected shots from your history and cannot be undone.")
        }
        .alert("Couldn't delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .task { await loadShots() }
    }

    // MARK: Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(item.accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(item.accentColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(item.shotIds.count)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("SHOTS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .tracking(1)
                }
            }
            TCDivider()
            Text(Self.dateFormatter.string(from: item.startedAt))
                .font(.system(size: 12))
                .foregroundColor(TCTheme.textMuted)
        }
        .tcCard()
    }

    // MARK: Range Stats

    private func rangeStatsCard(_ rs: PracticeSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(title: "Session Stats")
            HStack(spacing: 0) {
                statItem("Avg Carry", rs.summary.avgCarry > 0 ? "\(Int(rs.summary.avgCarry)) yd" : "—")
                statItem("Best Carry", rs.summary.bestCarry > 0 ? "\(Int(rs.summary.bestCarry)) yd" : "—")
                statItem("Avg Ball Spd", rs.summary.avgBallSpeed > 0 ? "\(Int(rs.summary.avgBallSpeed)) mph" : "—")
            }
        }
        .tcCard()
    }

    // MARK: Course Stats

    private func courseStatsCard(_ r: CourseRound) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(title: "Round Summary")
            HStack(spacing: 0) {
                let diff = r.scoreSummary.totalScore - r.scoreSummary.totalPar
                statItem("Score", r.scoreSummary.totalPar == 0 ? "—" : (diff == 0 ? "E" : diff > 0 ? "+\(diff)" : "\(diff)"))
                statItem("Fairways", "\(r.scoreSummary.fairwaysHit)")
                statItem("Putts", "\(r.scoreSummary.totalPutts)")
            }
            let scoredHoles = r.holes.filter { $0.score != nil || $0.putts != nil }
            if !scoredHoles.isEmpty {
                TCDivider()
                holeScorecardTable(r.holes)
            }
        }
        .tcCard()
    }

    private func holeScorecardTable(_ holes: [RoundHole]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("HOLE").frame(width: 44, alignment: .leading)
                Text("PAR").frame(width: 40, alignment: .center)
                Text("SCORE").frame(width: 56, alignment: .center)
                Text("PUTTS").frame(width: 48, alignment: .center)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(TCTheme.textMuted)
            .tracking(0.5)
            .padding(.vertical, 5)

            TCDivider()

            ForEach(Array(holes.enumerated()), id: \.element.id) { idx, hole in
                HStack(spacing: 0) {
                    Text("\(hole.holeNumber)")
                        .frame(width: 44, alignment: .leading)
                    Text("\(hole.par)")
                        .frame(width: 40, alignment: .center)
                    if let score = hole.score {
                        let diff = score - hole.par
                        Text("\(score)")
                            .foregroundColor(scoreToParColor(diff))
                            .frame(width: 56, alignment: .center)
                    } else {
                        Text("—").frame(width: 56, alignment: .center)
                            .foregroundColor(TCTheme.textMuted)
                    }
                    Text(hole.putts.map { "\($0)" } ?? "—")
                        .frame(width: 48, alignment: .center)
                        .foregroundColor(hole.putts != nil ? TCTheme.textPrimary : TCTheme.textMuted)
                }
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textPrimary)
                .padding(.vertical, 6)

                if idx < holes.count - 1 {
                    Divider().padding(.leading, 44).opacity(0.3)
                }
            }
        }
    }

    private func scoreToParColor(_ diff: Int) -> Color {
        if diff <= -2 { return .yellow }
        if diff == -1 { return .red }
        if diff == 0  { return TCTheme.textPrimary }
        if diff == 1  { return Color(white: 0.65) }
        return Color(white: 0.5)
    }

    // MARK: Round Shot Map

    private func roundShotLogSection(_ r: CourseRound, shots: [SavedShot]) -> some View {
        let holeCount  = Set(r.nfcShots.map { $0.holeNumber }).count
        let linkedCount = r.nfcShots.filter { $0.linkedShotId != nil }.count
        let subtitle = linkedCount > 0
            ? "\(r.nfcShots.count) taps · \(holeCount) hole\(holeCount == 1 ? "" : "s") · \(linkedCount) with video"
            : "\(r.nfcShots.count) taps · \(holeCount) hole\(holeCount == 1 ? "" : "s")"
        return VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(title: "Shot Map · \(subtitle)")
            RoundShotLogView(round: r, linkedShots: shots)
        }
    }

    // MARK: Shots List

    private var shotsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TCSectionHeader(title: "Shots")
            if shots.isEmpty {
                Text("No shots recorded.")
                    .font(.system(size: 14))
                    .foregroundColor(TCTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(shots.enumerated()), id: \.element.id) { idx, shot in
                        if isSelecting {
                            Button { toggleSelection(shot) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedShotIDs.contains(shot.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundColor(selectedShotIDs.contains(shot.id) ? TCTheme.sage : TCTheme.textUltraMuted)
                                    shotRow(shot, number: idx + 1)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(destination: ShotDetailView(shot: shot)) {
                                shotRow(shot, number: idx + 1)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) { shotToDelete = shot } label: {
                                    Label("Delete Shot", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Bottom bar shown while selecting shots: select-all + delete count.
    private var selectionActionBar: some View {
        let allIDs = Set(shots.map(\.id))
        let allSelected = !allIDs.isEmpty && selectedShotIDs.isSuperset(of: allIDs)
        return HStack(spacing: 14) {
            Button {
                if allSelected { selectedShotIDs.subtract(allIDs) }
                else { selectedShotIDs.formUnion(allIDs) }
            } label: {
                Text(allSelected ? "Deselect All" : "Select All")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.sage)
            }
            Spacer()
            Text("\(selectedShotIDs.count) selected")
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textMuted)
            Button(role: .destructive) { showDeleteSelected = true } label: {
                Text("Delete")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(selectedShotIDs.isEmpty ? TCTheme.textUltraMuted : Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .disabled(selectedShotIDs.isEmpty)
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(TCTheme.border).frame(height: 1), alignment: .top)
    }

    private func startSelection() {
        selectedShotIDs.removeAll()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { isSelecting = true }
    }

    private func exitSelection() {
        selectedShotIDs.removeAll()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { isSelecting = false }
    }

    private func toggleSelection(_ shot: SavedShot) {
        if selectedShotIDs.contains(shot.id) { selectedShotIDs.remove(shot.id) }
        else { selectedShotIDs.insert(shot.id) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func deleteShots(_ ids: [UUID]) async {
        guard let uid = session.currentUser?.id, !ids.isEmpty else { return }
        let service = ShotPersistenceService(userId: uid, backend: session.backend)
        for id in ids {
            do {
                try await service.deleteShot(id: id)
                shots.removeAll { $0.id == id }
            } catch {
                deleteError = "Delete failed. \(error.localizedDescription)"
            }
        }
        if isSelecting { exitSelection() }
    }

    private func shotRow(_ shot: SavedShot, number: Int) -> some View {
        HStack(spacing: 12) {
            Text("#\(number)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(TCTheme.textMuted)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(shot.clubName ?? "Unknown")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                Text(shot.source == .simulated ? "Simulated" : "Live")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
            }

            Spacer()

            HStack(spacing: 16) {
                if shot.metrics.carryYards > 0 {
                    metricPair("\(Int(shot.metrics.carryYards))", "yd", "carry")
                }
                if shot.metrics.ballSpeedMph > 0 {
                    metricPair("\(Int(shot.metrics.ballSpeedMph))", "mph", "ball spd")
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(TCTheme.textUltraMuted)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(TCTheme.border, lineWidth: 1))
    }

    // MARK: Helpers

    private func statItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.5)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricPair(_ value: String, _ unit: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(TCTheme.textPrimary)
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundColor(TCTheme.textMuted)
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(TCTheme.textMuted)
        }
    }

    private func loadShots() async {
        guard let uid = session.currentUser?.id else { isLoading = false; return }
        let ids = item.shotIds
        let all = (try? await session.backend.loadShots(userId: uid)) ?? []
        let ordered = ids.compactMap { id in all.first(where: { $0.id == id }) }
        shots = ordered
        isLoading = false
    }
}
