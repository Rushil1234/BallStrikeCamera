import SwiftUI

struct PastSessionsView: View {
    @EnvironmentObject var session: AuthSessionStore

    @State private var selectedFilter: HistoryFilter = .all
    @State private var showSearch = false
    @State private var showProfile = false
    @State private var searchText = ""
    @State private var shots: [SavedShot] = []
    @State private var rangeSessions: [PracticeSession] = []
    @State private var simSessions: [SimSession] = []
    @State private var rounds: [CourseRound] = []
    @State private var isLoading = true
    @State private var didLoad = false
    @State private var loadError: String?
    @State private var itemToDelete: DeletionTarget?
    @State private var showClearHistory = false
    @State private var skeletonPulse = false
    // Multi-select delete
    @State private var isSelecting = false
    @State private var selectedItemIDs: Set<String> = []
    @State private var showDeleteSelected = false

    private var sessionsEmpty: Bool {
        rangeSessions.isEmpty && simSessions.isEmpty && rounds.isEmpty && shots.isEmpty
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let longDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: TCTheme.sectionGap) {
                    headerBar
                    titleBlock
                    if showSearch { searchField }
                    filterBar
                    summaryStrip
                    handicapCard   // always visible so Scores & Handicap is discoverable pre-rounds
                    coachSwingsSection   // lessons + analyzed swings from TrueCarry Coach
                    content
                    Spacer(minLength: 140)
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .refreshable { await loadData() }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !sessionsEmpty {
                    if isSelecting {
                        Button("Done") { exitSelection() }
                            .foregroundColor(TCTheme.sage)
                    } else {
                        Menu {
                            Button { startSelection() } label: { Label("Select", systemImage: "checkmark.circle") }
                            Button(role: .destructive) { showClearHistory = true } label: {
                                Label("Clear All History", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if isSelecting { selectionTopBar }
        }
        .confirmationDialog("Clear all history?", isPresented: $showClearHistory, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { Task { await clearAllHistory() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every saved session, round, and shot. This cannot be undone.")
        }
        .confirmationDialog("Delete \(selectedItemIDs.count) item\(selectedItemIDs.count == 1 ? "" : "s")?",
                            isPresented: $showDeleteSelected, titleVisibility: .visible) {
            Button("Delete \(selectedItemIDs.count) item\(selectedItemIDs.count == 1 ? "" : "s")", role: .destructive) {
                Task { await deleteSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected sessions and shots from your history and cannot be undone.")
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack { TrueCarryProfileView() }
                .tcAppearance()
        }
        .task(id: session.currentUser?.id) {
            // Seed instantly from the prewarmed cache so counts aren't 0 while loading.
            if !didLoad, !session.cachedShots.isEmpty {
                shots = session.cachedShots.filter { !$0.isBadShot && $0.metrics.carryYards > 0 }
            }
            await loadData()
        }
        // Reload when anything is deleted anywhere (e.g. inside a session detail screen).
        .onReceive(NotificationCenter.default.publisher(for: .tcDataChanged)) { _ in
            Task { await loadData() }
        }
        .alert(
            "Delete \(itemToDelete?.label ?? "item")?",
            isPresented: Binding(get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let target = itemToDelete {
                    Task { await performDelete(target) }
                }
                itemToDelete = nil
            }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        } message: {
            Text("This removes it from your history and cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 0) {
            // left: search + refresh
            HStack(spacing: 6) {
                TCIconButton(icon: showSearch ? "xmark" : "magnifyingglass") {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        showSearch.toggle()
                        if !showSearch { searchText = "" }
                    }
                }
                TCIconButton(icon: "arrow.clockwise") {
                    Task { await loadData() }
                }
            }
            .frame(width: 88, height: 44, alignment: .leading)

            TrueCarryLogo(size: 20)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

            // right: profile
            HStack(spacing: 6) {
                TCProfileAvatarButton(initials: userInitials,
                                      devMode: session.entitlementVM.isDeveloperMode) {
                    showProfile = true
                }
            }
            .frame(width: 88, height: 44, alignment: .trailing)
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// Shortcut into the handicap / scores page, with the current estimated index inline.
    private var handicapCard: some View {
        NavigationLink(destination: HandicapView(rounds: rounds)) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(TCTheme.sage.opacity(0.16)).frame(width: 44, height: 44)
                    Image(systemName: "figure.golf")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(TCTheme.sage)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Handicap & Scores")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text(rounds.isEmpty ? "Play a scored round to start tracking"
                                        : "Index from your last 20 rounds")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
                Spacer()
                Text(HandicapService.indexString(HandicapService.compute(from: rounds).index))
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(TCTheme.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            .tcCard()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, TCTheme.hPad)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History")
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundColor(TCTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(historySubtitle)
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, TCTheme.hPad)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(TCTheme.textMuted)
            TextField("Search clubs, courses, dates", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(TCTheme.textPrimary)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TCTheme.textUltraMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(TCTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, TCTheme.hPad)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HistoryFilter.allCases) { filter in
                    filterButton(filter)
                }
            }
            .padding(.horizontal, TCTheme.hPad)
        }
    }

    private func filterButton(_ filter: HistoryFilter) -> some View {
        let selected = selectedFilter == filter
        return Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                selectedFilter = filter
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: filter.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(filter.title)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(count(for: filter))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(selected ? TCTheme.onPrimary.opacity(0.75) : TCTheme.textUltraMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(selected ? TCTheme.onPrimary.opacity(0.14) : TCTheme.panelRaised)
                    )
            }
            .foregroundColor(selected ? TCTheme.onPrimary : TCTheme.textMuted)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(selected ? AnyShapeStyle(TCTheme.primaryFill) : AnyShapeStyle(TCTheme.panel))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(selected ? Color.clear : TCTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary

    private var summaryStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(TCTheme.gold)
                    .frame(width: 16, height: 2)
                    .clipShape(Capsule())
                Text("ALL TIME")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(TCTheme.textMuted)
                    .tracking(1.4)
                Spacer()
            }
            HStack(spacing: 0) {
                summaryItem("\(totalSessions)", "Sessions")
                verticalDivider
                summaryItem("\(shots.count)", "Shots")
                verticalDivider
                summaryItem(bestCarryString, "Best Carry", accent: true)
                verticalDivider
                summaryItem(avgBallSpeedString, "Avg Speed")
            }
        }
        .padding(16)
        .background(TCTheme.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, TCTheme.hPad)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(TCTheme.border)
            .frame(width: 1, height: 30)
    }

    private func summaryItem(_ value: String, _ label: String, accent: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                .foregroundColor(accent ? TCTheme.gold : TCTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.6)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let loadError, didLoad, hasAnyHistory {
                warningBanner(loadError)
            }

            if isLoading && !didLoad {
                loadingCard
            } else if !hasAnyHistory, let loadError {
                errorCard(loadError)
            } else if visibleItems.isEmpty {
                emptyState
            } else {
                timelineSection
            }
        }
        .padding(.horizontal, TCTheme.hPad)
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(TCTheme.panelRaised)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(TCTheme.panelRaised)
                            .frame(width: 140, height: 13)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(TCTheme.panelRaised.opacity(0.7))
                            .frame(width: 200, height: 10)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(TCTheme.panelRaised)
                        .frame(width: 44, height: 20)
                }
                .tcCard()
            }
        }
        .opacity(skeletonPulse ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: skeletonPulse)
        .onAppear { skeletonPulse = true }
    }

    private func warningBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(TCTheme.gold)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(TCTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(TCTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1)
        )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(TCTheme.gold)
                VStack(alignment: .leading, spacing: 4) {
                    Text("History could not load")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            Button {
                Task { await loadData() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .tcCard()
    }

    @ViewBuilder
    private var emptyState: some View {
        if normalizedSearch.isEmpty {
            GolfBallEmptyField(
                title: emptyStateTitle,
                message: emptyStateMessage
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(TCTheme.panelRaised)
                            .frame(width: 42, height: 42)
                        Image(systemName: emptyStateIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(TCTheme.textMuted)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(emptyStateTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(TCTheme.textPrimary)
                        Text(emptyStateMessage)
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
            }
            .tcCard()
        }
    }

    // MARK: Coach swings (lesson history + analyzed swing videos)

    @ViewBuilder
    private var coachSwingsSection: some View {
        let library = LessonLibrary.shared
        let recent = Array(library.swings.filter(\.analyzed).suffix(3).reversed())
        if !recent.isEmpty || !library.lessonSessions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("COACH")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(TCTheme.textMuted)
                        .tracking(1.4)
                        .fixedSize()
                    Rectangle().fill(TCTheme.border).frame(height: 1)
                    Text("\(library.completedLessonCount) lesson\(library.completedLessonCount == 1 ? "" : "s") · \(library.swings.filter(\.analyzed).count) swing\(library.swings.filter(\.analyzed).count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(TCTheme.textUltraMuted)
                        .fixedSize()
                }
                ForEach(recent) { swing in
                    NavigationLink { SwingReplayView(swing: swing) } label: {
                        SwingRowView(swing: swing)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TCTheme.hPad)
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(groupedItems, id: \.key) { group in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text(group.key.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(TCTheme.textMuted)
                            .tracking(1.4)
                            .fixedSize()
                        Rectangle()
                            .fill(TCTheme.border)
                            .frame(height: 1)
                        Text("\(group.items.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(TCTheme.textUltraMuted)
                    }
                    VStack(spacing: 12) {
                        ForEach(group.items) { item in
                            timelineCard(item)
                        }
                    }
                }
            }
        }
    }

    private var groupedItems: [(key: String, items: [HistoryTimelineItem])] {
        var order: [String] = []
        var buckets: [String: [HistoryTimelineItem]] = [:]
        for item in visibleItems {
            let key = monthKey(for: item.date)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.map { (key: $0, items: buckets[$0] ?? []) }
    }

    private func monthKey(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) || cal.isDateInYesterday(date) { return "This Week" }
        if let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()), date > weekAgo {
            return "This Week"
        }
        return Self.monthFormatter.string(from: date)
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    @ViewBuilder
    private func timelineCard(_ item: HistoryTimelineItem) -> some View {
        if isSelecting {
            Button { toggleSelection(item) } label: { selectableRow(item) }
                .buttonStyle(.plain)
        } else {
            switch item {
            case .range(let rangeSession):
                NavigationLink(destination: SessionDetailView(item: .range(rangeSession),
                                                              onSessionRemoved: removeSession,
                                                              onShotsChanged: updateSessionShots)) {
                    timelineRow(item)
                }
                .buttonStyle(.plain)
                .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    beginSelection(item)
                })
            case .sim(let simSession):
                NavigationLink(destination: SessionDetailView(item: .sim(simSession),
                                                              onSessionRemoved: removeSession,
                                                              onShotsChanged: updateSessionShots)) {
                    timelineRow(item)
                }
                .buttonStyle(.plain)
                .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    beginSelection(item)
                })
            case .course(let round):
                NavigationLink(destination: SessionDetailView(item: .course(round),
                                                              onSessionRemoved: removeSession,
                                                              onShotsChanged: updateSessionShots)) {
                    timelineRow(item)
                }
                .buttonStyle(.plain)
                .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    beginSelection(item)
                })
            case .shot(let shot):
                NavigationLink(destination: ShotDetailView(shot: shot)) {
                    timelineRow(item)
                }
                .buttonStyle(.plain)
                .highPriorityGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    beginSelection(item)
                })
            }
        }
    }

    /// A timeline card with a leading selection dot, shown while in multi-select mode.
    private func selectableRow(_ item: HistoryTimelineItem) -> some View {
        let selected = selectedItemIDs.contains(item.id)
        return HStack(spacing: 10) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(selected ? TCTheme.sage : TCTheme.textUltraMuted)
                .animation(.easeInOut(duration: 0.12), value: selected)
            timelineRow(item)
        }
        .contentShape(Rectangle())
    }

    /// Fixed top bar shown in multi-select mode. Lives at the top (the bottom is covered by the
    /// floating tab dock), stays visible while scrolling, and always shows Cancel + Delete.
    private var selectionTopBar: some View {
        let allIDs = Set(visibleItems.map(\.id))
        let allSelected = !allIDs.isEmpty && selectedItemIDs.isSuperset(of: allIDs)
        let count = selectedItemIDs.count
        return HStack(spacing: 12) {
            Button { exitSelection() } label: {
                Text("Cancel")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(TCTheme.textSecondary)
            }
            Spacer()
            Button {
                if allSelected { selectedItemIDs.subtract(allIDs) }
                else { selectedItemIDs.formUnion(allIDs) }
            } label: {
                Text(allSelected ? "Deselect All" : "Select All")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.sage)
            }
            Spacer()
            Button(role: .destructive) { showDeleteSelected = true } label: {
                Text(count > 0 ? "Delete (\(count))" : "Delete")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(count == 0 ? TCTheme.textUltraMuted : Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .disabled(count == 0)
        }
        .padding(.horizontal, TCTheme.hPad)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(TCTheme.border).frame(height: 1), alignment: .bottom)
    }

    private func startSelection() {
        selectedItemIDs.removeAll()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { isSelecting = true }
    }

    /// Long-press entry: enter multi-select mode with this item pre-selected.
    private func beginSelection(_ item: HistoryTimelineItem) {
        guard !isSelecting else { return }
        selectedItemIDs = [item.id]
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { isSelecting = true }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func exitSelection() {
        selectedItemIDs.removeAll()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { isSelecting = false }
    }

    private func toggleSelection(_ item: HistoryTimelineItem) {
        if selectedItemIDs.contains(item.id) { selectedItemIDs.remove(item.id) }
        else { selectedItemIDs.insert(item.id) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func deleteSelected() async {
        let targets = visibleItems
            .filter { selectedItemIDs.contains($0.id) }
            .map(\.deletionTarget)
        for target in targets { await performDelete(target) }
        exitSelection()
    }

    /// Drop a session from the timeline immediately when its detail view deletes it (e.g. after
    /// its last shot was removed), so the list reflects it without a manual refresh.
    private func removeSession(_ id: UUID) {
        rangeSessions.removeAll { $0.id == id }
        simSessions.removeAll { $0.id == id }
        rounds.removeAll { $0.id == id }
    }

    /// Update a session's shot list locally when its detail view deletes some (not all) shots, so
    /// the card's shot count matches without a manual refresh.
    private func updateSessionShots(_ id: UUID, _ remaining: [UUID]) {
        if let i = rangeSessions.firstIndex(where: { $0.id == id }) { rangeSessions[i].shotIds = remaining }
        if let i = simSessions.firstIndex(where: { $0.id == id })   { simSessions[i].shotIds = remaining }
        if let i = rounds.firstIndex(where: { $0.id == id })        { rounds[i].shotIds = remaining }
    }

    private func timelineRow(_ item: HistoryTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(item.accent.opacity(0.14))
                        .frame(width: 44, height: 44)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(item.accent.opacity(0.22), lineWidth: 1)
                        .frame(width: 44, height: 44)
                    Image(systemName: item.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(item.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .semibold))
                        Text(cardDate(item.date))
                            .font(.system(size: 11))
                    }
                    .foregroundColor(TCTheme.textUltraMuted)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.primaryValue)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundColor(TCTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text(item.primaryLabel.uppercased())
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(TCTheme.textMuted)
                        .tracking(0.6)
                        .lineLimit(1)
                }
                .frame(minWidth: 54, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TCTheme.textUltraMuted)
                    .padding(.top, 7)
            }

            if !item.detailStats.isEmpty {
                HStack(spacing: 0) {
                    ForEach(item.detailStats) { stat in
                        detailStat(stat)
                    }
                }
                .padding(.vertical, 9)
                .background(TCTheme.panelRaised.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .tcCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.subtitle)")
    }

    /// "2h ago" for the last week, "Jun 3, 1:24 PM" beyond that.
    private func cardDate(_ date: Date) -> String {
        if let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()), date > weekAgo {
            return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return Self.longDateFormatter.string(from: date)
    }

    private func detailStat(_ stat: HistoryStat) -> some View {
        VStack(spacing: 3) {
            Text(stat.value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(TCTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(stat.label.uppercased())
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.5)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func deleteMenu(for item: HistoryTimelineItem) -> some View {
        Button(role: .destructive) {
            itemToDelete = item.deletionTarget
        } label: {
            Label(item.deleteTitle, systemImage: "trash")
        }
    }

    // MARK: - Data

    private func loadData() async {
        guard let uid = session.currentUser?.id else {
            shots = []
            rangeSessions = []
            simSessions = []
            rounds = []
            loadError = session.isLoading ? nil : "Sign in to load your saved activity."
            isLoading = false
            didLoad = true
            return
        }

        isLoading = true
        loadError = nil

        let backend = session.backend
        var failures: [String] = []

        do {
            shots = try await backend.loadShots(userId: uid)
            shots = shots.filter { !$0.isBadShot && $0.metrics.carryYards > 0 }
        } catch {
            if Self.isCancellation(error) { return }   // superseded by a newer load — keep state
            shots = []
            failures.append("shots")
            print("[History] loadShots failed: \(error)")
        }

        do {
            rangeSessions = try await backend.loadRangeSessions(userId: uid)
        } catch {
            if Self.isCancellation(error) { return }
            rangeSessions = []
            failures.append("range sessions")
            print("[History] loadRangeSessions failed: \(error)")
        }

        do {
            simSessions = try await backend.loadSimSessions(userId: uid)
        } catch {
            if Self.isCancellation(error) { return }
            simSessions = []
            failures.append("sim sessions")
            print("[History] loadSimSessions failed: \(error)")
        }

        do {
            rounds = try await backend.loadCourseRounds(userId: uid)
        } catch {
            if Self.isCancellation(error) { return }
            rounds = []
            failures.append("rounds")
            print("[History] loadCourseRounds failed: \(error)")
        }

        loadError = failures.isEmpty ? nil : "Could not load \(failures.joined(separator: ", ")). Pull to refresh and try again."
        isLoading = false
        didLoad = true
    }

    /// A cancelled request (e.g. the load was superseded while auth/token state settled on launch,
    /// or the user navigated) is not a real failure — bail without clobbering the loaded data.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    private func performDelete(_ target: DeletionTarget) async {
        guard let uid = session.currentUser?.id else { return }
        let backend = session.backend

        do {
            switch target {
            case .rangeSession(let rangeSession):
                try await backend.deleteRangeSession(sessionId: rangeSession.id, userId: uid)
                rangeSessions.removeAll { $0.id == rangeSession.id }
            case .simSession(let simSession):
                try await backend.deleteSimSession(sessionId: simSession.id, userId: uid)
                simSessions.removeAll { $0.id == simSession.id }
            case .courseRound(let round):
                try await backend.deleteCourseRound(roundId: round.id, userId: uid)
                rounds.removeAll { $0.id == round.id }
            case .shot(let shot):
                let service = ShotPersistenceService(userId: uid, backend: backend)
                try await service.deleteShot(id: shot.id)
                shots.removeAll { $0.id == shot.id }
            }
        } catch {
            loadError = "Delete failed. \(error.localizedDescription)"
        }
    }

    private func clearAllHistory() async {
        guard let uid = session.currentUser?.id else { return }
        let backend = session.backend
        let service = ShotPersistenceService(userId: uid, backend: backend)
        for s in rangeSessions { try? await backend.deleteRangeSession(sessionId: s.id, userId: uid) }
        for s in simSessions  { try? await backend.deleteSimSession(sessionId: s.id, userId: uid) }
        for r in rounds       { try? await backend.deleteCourseRound(roundId: r.id, userId: uid) }
        for sh in shots       { try? await service.deleteShot(id: sh.id) }
        rangeSessions = []; simSessions = []; rounds = []; shots = []
    }

    // MARK: - Derived State

    private var totalSessions: Int {
        rangeSessions.count + simSessions.count + rounds.count
    }

    private var hasAnyHistory: Bool {
        totalSessions > 0 || !shots.isEmpty
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleItems: [HistoryTimelineItem] {
        let baseItems: [HistoryTimelineItem]
        switch selectedFilter {
        case .all:
            baseItems = rangeSessions.map(HistoryTimelineItem.range)
                + simSessions.map(HistoryTimelineItem.sim)
                + rounds.map(HistoryTimelineItem.course)
                + standaloneShots.map(HistoryTimelineItem.shot)
        case .range:
            baseItems = rangeSessions.map(HistoryTimelineItem.range)
        case .sim:
            baseItems = simSessions.map(HistoryTimelineItem.sim)
        case .course:
            baseItems = rounds.map(HistoryTimelineItem.course)
        case .shots:
            baseItems = shots.map(HistoryTimelineItem.shot)
        }

        let searched = normalizedSearch.isEmpty
            ? baseItems
            : baseItems.filter { $0.matches(normalizedSearch) }

        return searched.sorted { $0.date > $1.date }
    }

    private var standaloneShots: [SavedShot] {
        shots.filter { $0.sessionId == nil && $0.roundId == nil }
    }

    private func count(for filter: HistoryFilter) -> Int {
        switch filter {
        case .all: return rangeSessions.count + simSessions.count + rounds.count + standaloneShots.count
        case .range: return rangeSessions.count
        case .sim: return simSessions.count
        case .course: return rounds.count
        case .shots: return shots.count
        }
    }

    private var historySubtitle: String {
        guard let latest = (rangeSessions.map(\.startedAt) + simSessions.map(\.startedAt) + rounds.map(\.startedAt) + shots.map(\.timestamp)).max() else {
            return "Saved sessions and shots will land here."
        }
        return "Last activity \(Self.relativeFormatter.localizedString(for: latest, relativeTo: Date()))."
    }

    private var bestCarryString: String {
        let best = shots.map { $0.metrics.carryYards }.filter { $0 > 0 }.max()
        guard let best else { return "--" }
        return "\(Int(best.rounded())) yd"
    }

    private var avgBallSpeedString: String {
        let speeds = shots.map { $0.metrics.ballSpeedMph }.filter { $0 > 0 }
        guard !speeds.isEmpty else { return "--" }
        let avg = speeds.reduce(0, +) / Double(speeds.count)
        return "\(Int(avg.rounded())) mph"
    }

    private var emptyStateIcon: String {
        if !normalizedSearch.isEmpty { return "magnifyingglass" }
        return selectedFilter.icon
    }

    private var emptyStateTitle: String {
        if !normalizedSearch.isEmpty { return "No matches" }
        switch selectedFilter {
        case .all: return "No history yet"
        case .range: return "No range sessions"
        case .sim: return "No sim sessions"
        case .course: return "No course rounds"
        case .shots: return "No saved shots"
        }
    }

    private var emptyStateMessage: String {
        if !normalizedSearch.isEmpty {
            return "Try a different club, course, date, or metric."
        }
        switch selectedFilter {
        case .all:
            return "Finish a range session, sim session, course round, or save a shot to start building your timeline."
        case .range:
            return "Saved range sessions appear here after you end and save a session."
        case .sim:
            return "Sim sessions appear here after you save a simulator session."
        case .course:
            return "Course rounds appear here after you play and save a round."
        case .shots:
            return "Shots saved from review appear here and open into the full replay details."
        }
    }

    private var userInitials: String {
        let name = session.userProfile?.displayName ?? session.currentUser?.name ?? "Player"
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String((parts[0].first ?? "P")).uppercased()
                + String((parts[1].first ?? "L")).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Types

    private enum HistoryFilter: String, CaseIterable, Identifiable {
        case all
        case range
        case sim
        case course
        case shots

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .range: return "Range"
            case .sim: return "Sim"
            case .course: return "Course"
            case .shots: return "Shots"
            }
        }

        var sectionTitle: String {
            switch self {
            case .all: return "Recent Activity"
            case .range: return "Range Sessions"
            case .sim: return "Sim Sessions"
            case .course: return "Course Rounds"
            case .shots: return "Saved Shots"
            }
        }

        var icon: String {
            switch self {
            case .all: return "clock.arrow.circlepath"
            case .range: return "scope"
            case .sim: return "display"
            case .course: return "flag.fill"
            case .shots: return "circle.inset.filled"
            }
        }
    }

    private enum DeletionTarget: Identifiable {
        case rangeSession(PracticeSession)
        case simSession(SimSession)
        case courseRound(CourseRound)
        case shot(SavedShot)

        var id: String {
            switch self {
            case .rangeSession(let session): return "range-\(session.id.uuidString)"
            case .simSession(let session): return "sim-\(session.id.uuidString)"
            case .courseRound(let round): return "course-\(round.id.uuidString)"
            case .shot(let shot): return "shot-\(shot.id.uuidString)"
            }
        }

        var label: String {
            switch self {
            case .rangeSession: return "range session"
            case .simSession: return "sim session"
            case .courseRound: return "round"
            case .shot: return "shot"
            }
        }
    }

    private struct HistoryStat: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private enum HistoryTimelineItem: Identifiable {
        case range(PracticeSession)
        case sim(SimSession)
        case course(CourseRound)
        case shot(SavedShot)

        var id: String {
            switch self {
            case .range(let session): return "range-\(session.id.uuidString)"
            case .sim(let session): return "sim-\(session.id.uuidString)"
            case .course(let round): return "course-\(round.id.uuidString)"
            case .shot(let shot): return "shot-\(shot.id.uuidString)"
            }
        }

        var date: Date {
            switch self {
            case .range(let session): return session.endedAt ?? session.startedAt
            case .sim(let session): return session.endedAt ?? session.startedAt
            case .course(let round): return round.endedAt ?? round.startedAt
            case .shot(let shot): return shot.timestamp
            }
        }

        var icon: String {
            switch self {
            case .range: return "scope"
            case .sim: return "display"
            case .course: return "flag.fill"
            case .shot: return "circle.inset.filled"
            }
        }

        var accent: Color {
            switch self {
            case .range: return TCTheme.sage
            case .sim: return TCTheme.gold
            case .course: return TCTheme.sage
            case .shot: return TCTheme.silver
            }
        }

        var title: String {
            switch self {
            case .range(let session):
                return session.name.isEmpty ? "Range Session" : session.name
            case .sim(let session):
                return session.name.isEmpty ? "Sim Session" : session.name
            case .course(let round):
                return round.name.isEmpty ? round.courseName : round.name
            case .shot(let shot):
                return "\(shot.clubName ?? "Saved") Shot"
            }
        }

        var subtitle: String {
            switch self {
            case .range(let session):
                let club = session.selectedClubName ?? "All Clubs"
                return session.sessionDescription?.isEmpty == false ? "\(club) - \(session.sessionDescription!)" : club
            case .sim(let session):
                let source = session.usedOpenGolfSim ? "OpenGolfSim" : session.provider.rawValue
                return session.sessionDescription?.isEmpty == false ? "\(source) - \(session.sessionDescription!)" : source
            case .course(let round):
                return "\(round.courseName) - \(round.teeBoxName) tees"
            case .shot(let shot):
                var parts = [Self.sourceLabel(for: shot.source)]
                if let hole = shot.holeNumber { parts.append("Hole \(hole)") }
                if shot.isBadShot { parts.append("Marked bad") }
                return parts.joined(separator: " - ")
            }
        }

        var primaryValue: String {
            switch self {
            case .range(let session): return "\(session.shotIds.count)"
            case .sim(let session): return "\(session.shotIds.count)"
            case .course(let round): return Self.scoreText(round.scoreSummary)
            case .shot(let shot): return Self.yards(shot.metrics.carryYards)
            }
        }

        var primaryLabel: String {
            switch self {
            case .range, .sim: return "shots"
            case .course: return "score"
            case .shot: return "carry"
            }
        }

        var detailStats: [HistoryStat] {
            switch self {
            case .range(let session):
                return [
                    HistoryStat(label: "Avg Carry", value: Self.yards(session.summary.avgCarry)),
                    HistoryStat(label: "Best Carry", value: Self.yards(session.summary.bestCarry)),
                    HistoryStat(label: "Avg Speed", value: Self.speed(session.summary.avgBallSpeed))
                ]
            case .sim(let session):
                return [
                    HistoryStat(label: "Provider", value: session.provider.rawValue),
                    HistoryStat(label: "Output", value: session.outputLog.isEmpty ? "--" : "\(session.outputLog.count)"),
                    HistoryStat(label: "Duration", value: Self.duration(start: session.startedAt, end: session.endedAt))
                ]
            case .course(let round):
                return [
                    HistoryStat(label: "Fairways", value: "\(round.scoreSummary.fairwaysHit)"),
                    HistoryStat(label: "Putts", value: "\(round.scoreSummary.totalPutts)"),
                    HistoryStat(label: "Holes", value: "\(round.holes.count)")
                ]
            case .shot(let shot):
                return [
                    HistoryStat(label: "Total", value: Self.yards(shot.metrics.totalYards)),
                    HistoryStat(label: "Ball Speed", value: Self.speed(shot.metrics.ballSpeedMph)),
                    HistoryStat(label: "Mode", value: shot.mode.rawValue.capitalized)
                ]
            }
        }

        var deletionTarget: DeletionTarget {
            switch self {
            case .range(let session): return .rangeSession(session)
            case .sim(let session): return .simSession(session)
            case .course(let round): return .courseRound(round)
            case .shot(let shot): return .shot(shot)
            }
        }

        var deleteTitle: String {
            switch self {
            case .range: return "Delete Range Session"
            case .sim: return "Delete Sim Session"
            case .course: return "Delete Round"
            case .shot: return "Delete Shot"
            }
        }

        func matches(_ query: String) -> Bool {
            let haystack = [
                title,
                subtitle,
                primaryValue,
                primaryLabel,
                PastSessionsView.shortDateFormatter.string(from: date),
                PastSessionsView.longDateFormatter.string(from: date)
            ].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(query)
        }

        private static func yards(_ value: Double) -> String {
            guard value > 0 else { return "--" }
            return "\(Int(value.rounded())) yd"
        }

        private static func speed(_ value: Double) -> String {
            guard value > 0 else { return "--" }
            return "\(Int(value.rounded())) mph"
        }

        private static func scoreText(_ summary: RoundScoreSummary) -> String {
            guard summary.totalPar > 0 else { return "--" }
            let diff = summary.totalScore - summary.totalPar
            if diff == 0 { return "E" }
            return diff > 0 ? "+\(diff)" : "\(diff)"
        }

        private static func sourceLabel(for source: ShotSource) -> String {
            switch source {
            case .live: return "Live"
            case .simulated: return "Simulated"
            case .manual: return "Manual"
            }
        }

        private static func duration(start: Date, end: Date?) -> String {
            guard let end else { return "Active" }
            let minutes = max(1, Int(end.timeIntervalSince(start) / 60))
            if minutes < 60 { return "\(minutes)m" }
            let hours = minutes / 60
            let remaining = minutes % 60
            return remaining == 0 ? "\(hours)h" : "\(hours)h \(remaining)m"
        }
    }
}
