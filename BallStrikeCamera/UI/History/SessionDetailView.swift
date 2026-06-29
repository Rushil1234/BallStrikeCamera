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
    @Environment(\.dismiss) private var dismiss
    let item: SessionItem
    /// Called when the session itself is removed (e.g. its last shot was deleted) so the history
    /// list can drop it without a manual refresh.
    var onSessionRemoved: ((UUID) -> Void)? = nil
    /// Called after some (not all) shots are deleted, with the remaining shot ids, so the history
    /// list can update the session's shot count without a manual refresh.
    var onShotsChanged: ((UUID, [UUID]) -> Void)? = nil

    @State private var shots: [SavedShot] = []
    @State private var isLoading = true
    // Shot deletion / multi-select
    @State private var isSelecting = false
    @State private var selectedShotIDs: Set<UUID> = []
    @State private var showDeleteSelected = false
    @State private var deleteError: String?
    // Attestation
    @State private var showAttestSheet = false
    @State private var friends: [FriendProfile] = []
    @State private var attestMessage: String?
    @State private var roundAttestation: SentAttestation?

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
                            if case .course = item { attestSection }
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
            if showsShotsList && !shots.isEmpty && isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { exitSelection() }.foregroundColor(TCTheme.textSecondary)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(allShotsSelected ? "Deselect All" : "Select All") { toggleSelectAllShots() }
                        .foregroundColor(TCTheme.sage)
                    Button("Delete (\(selectedShotIDs.count))", role: .destructive) { showDeleteSelected = true }
                        .disabled(selectedShotIDs.isEmpty)
                }
            }
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
        .sheet(isPresented: $showAttestSheet) { attestPickerSheet.tcAppearance() }
        .alert("Attestation", isPresented: Binding(get: { attestMessage != nil }, set: { if !$0 { attestMessage = nil } })) {
            Button("OK", role: .cancel) { attestMessage = nil }
        } message: {
            Text(attestMessage ?? "")
        }
        .task { await loadShots() }
        .task { await loadAttestationStatus() }
    }

    // MARK: Attestation

    /// Shows the request button until a request exists, then its live status.
    @ViewBuilder private var attestSection: some View {
        if let a = roundAttestation {
            attestStatusCard(a)
        } else {
            attestButton
        }
    }

    private func attestStatusCard(_ a: SentAttestation) -> some View {
        let icon: String
        let tint: Color
        let title: String
        let detail: String
        switch a.status {
        case "attested":
            icon = "checkmark.seal.fill"; tint = TCTheme.sage
            title = "Verified"
            detail = a.attesterName.isEmpty ? "A friend verified this round." : "Verified by \(a.attesterName)."
        case "declined":
            icon = "xmark.seal.fill"; tint = TCTheme.dangerRed
            title = "Attestation declined"
            detail = "The friend you asked declined this request."
        default:
            icon = "clock.fill"; tint = TCTheme.gold
            title = "Attestation pending"
            detail = "Waiting for your friend to verify this round."
        }
        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
            }
            Spacer()
            if a.status == "declined" {
                Button("Ask again") { showAttestSheet = true }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TCTheme.sage)
                    .buttonStyle(.plain)
            }
        }
        .tcCard()
    }

    private func loadAttestationStatus() async {
        guard case .course(let round) = item, let me = session.currentUser else { return }
        let sent = (try? await session.backend.loadSentAttestations(userId: me.id)) ?? []
        roundAttestation = sent.first { $0.roundId == round.id }
    }

    private var attestButton: some View {
        Button { showAttestSheet = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(TCTheme.sage)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Request Attestation")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text("Ask a friend to verify this round")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            .tcCard()
        }
        .buttonStyle(.plain)
    }

    private var attestPickerSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    if friends.isEmpty {
                        Text("Add friends to request a round attestation.")
                            .font(.system(size: 14))
                            .foregroundColor(TCTheme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.top, 50)
                    }
                    ForEach(friends) { friend in
                        Button { Task { await sendAttestation(to: friend) } } label: {
                            HStack(spacing: 12) {
                                AvatarCircle(name: friend.displayName, size: 38)
                                Text(friend.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(TCTheme.textPrimary)
                                Spacer()
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(TCTheme.sage)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(TCTheme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(TCTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.vertical, 12)
            }
            .background(TrueCarryBackground().ignoresSafeArea())
            .navigationTitle("Request Attestation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showAttestSheet = false }.foregroundColor(TCTheme.sage)
                }
            }
        }
        .task { friends = (try? await session.backend.loadFriends()) ?? [] }
    }

    private func sendAttestation(to friend: FriendProfile) async {
        guard case .course(let round) = item, let me = session.currentUser else { return }
        let name = session.userProfile?.displayName ?? me.name
        showAttestSheet = false
        do {
            try await session.backend.requestRoundAttestation(round: round, requesterId: me.id,
                                                              requesterName: name, attesterId: friend.userId)
            attestMessage = "Attestation request sent to \(friend.displayName)."
            await loadAttestationStatus()
        } catch {
            attestMessage = "Couldn't send the request. \(error.localizedDescription)"
        }
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
                    // Live count of the actually-present shots so it updates after deletions
                    // (item.shotIds is the session's original recorded list and never changes).
                    Text("\(isLoading ? item.shotIds.count : shots.count)")
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
                            .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                                beginSelection(shot)
                            })
                        }
                    }
                }
            }
        }
    }

    private var allShotsSelected: Bool {
        !shots.isEmpty && selectedShotIDs.isSuperset(of: Set(shots.map(\.id)))
    }

    private func toggleSelectAllShots() {
        let allIDs = Set(shots.map(\.id))
        if allShotsSelected { selectedShotIDs.subtract(allIDs) }
        else { selectedShotIDs.formUnion(allIDs) }
    }

    /// Long-press entry: enter multi-select with this shot pre-selected.
    private func beginSelection(_ shot: SavedShot) {
        guard !isSelecting else { return }
        selectedShotIDs = [shot.id]
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { isSelecting = true }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
        // An empty session is useless — delete it and return to the history list. Otherwise
        // persist the trimmed shot list so the session's count is correct everywhere.
        if shots.isEmpty { await deleteOwningSession(uid: uid) }
        else { await persistRemainingShots(uid: uid) }
    }

    /// Save the session with its remaining shot ids so the history list shows the right count
    /// (and it survives a reload), and notify the list to update immediately.
    private func persistRemainingShots(uid: UUID) async {
        let remaining = shots.map(\.id)
        do {
            switch item {
            case .range(var s):  s.shotIds = remaining; try await session.backend.saveRangeSession(s)
            case .sim(var s):    s.shotIds = remaining; try await session.backend.saveSimSession(s)
            case .course(var r): r.shotIds = remaining; try await session.backend.saveRound(r)
            }
            onShotsChanged?(item.id, remaining)
        } catch {
            deleteError = "Couldn't update the session. \(error.localizedDescription)"
        }
    }

    private func deleteOwningSession(uid: UUID) async {
        do {
            switch item {
            case .range(let s):  try await session.backend.deleteRangeSession(sessionId: s.id, userId: uid)
            case .sim(let s):    try await session.backend.deleteSimSession(sessionId: s.id, userId: uid)
            case .course(let r): try await session.backend.deleteCourseRound(roundId: r.id, userId: uid)
            }
            onSessionRemoved?(item.id)
            dismiss()
        } catch {
            deleteError = "Couldn't remove the empty session. \(error.localizedDescription)"
        }
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
