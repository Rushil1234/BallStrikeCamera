import SwiftUI

/// Which distance figure a shot's dispersion dot plots at: where it first landed, or where it
/// finally came to rest (including roll).
private enum DispersionMetric: String, CaseIterable {
    case carry = "Carry", total = "Total"
}

struct TrueCarryInsightsView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var shots: [SavedShot] = []
    @State private var clubs: [UserClub]  = []
    /// Verified on-course shots (score+putts entered and every full swing logged) — real
    /// start→end GPS distances with lateral deviation, folded into the Total view.
    @State private var roundShots: [VerifiedRoundShot] = []
    @State private var selectedClub: String? = nil
    /// ALL mode: every club on one top-tracer-style chart, each with its own color + cluster.
    @State private var allMode = false
    @State private var showProfile = false
    @State private var dispersionMetric: DispersionMetric = .carry

    // MARK: - Club list

    private var availableClubs: [String] {
        // Primary: use the user's bag in their configured sort order exactly.
        let bagClubs = clubs.sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
        if !bagClubs.isEmpty { return bagClubs }
        // Fallback: clubs inferred from shot history (no bag configured yet).
        var seen = Set<String>()
        return shots.compactMap { $0.clubName }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func shotsFor(_ club: String) -> [SavedShot] {
        let clubIds = Set(clubs.filter { $0.name == club }.map(\.id))
        return shots.filter { shot in
            guard !shot.isBadShot, shot.metrics.carryYards > 0 else { return false }
            if shot.clubName == club { return true }
            guard let clubId = shot.clubId else { return false }
            return clubIds.contains(clubId)
        }
    }

    private var selectedShots: [SavedShot] {
        selectedClub.map { shotsFor($0) } ?? []
    }

    private func roundShotsFor(_ club: String) -> [VerifiedRoundShot] {
        let clubIds = Set(clubs.filter { $0.name == club }.map(\.id))
        return roundShots.filter { rs in
            if rs.clubName == club { return true }
            guard let id = rs.clubId else { return false }
            return clubIds.contains(id)
        }
    }

    private var selectedRoundShots: [VerifiedRoundShot] {
        selectedClub.map { roundShotsFor($0) } ?? []
    }

    // MARK: - Stat helpers

    private func avg(_ vals: [Double]) -> Double? {
        let f = vals.filter { $0 > 0 }
        guard !f.isEmpty else { return nil }
        return f.reduce(0, +) / Double(f.count)
    }

    private func median(_ vals: [Double]) -> Double? {
        let f = vals.filter { $0 > 0 }.sorted()
        guard !f.isEmpty else { return nil }
        let mid = f.count / 2
        return f.count.isMultiple(of: 2) ? (f[mid - 1] + f[mid]) / 2 : f[mid]
    }

    private func avgCarry(_ shots: [SavedShot]) -> Double {
        avg(shots.map { $0.metrics.carryYards }) ?? 0
    }

    /// Average of whichever distance the Carry/Total toggle selects; total
    /// falls back to carry for shots recorded before rollout existed.
    private func avgDistance(_ shots: [SavedShot]) -> Double {
        switch dispersionMetric {
        case .carry: return avgCarry(shots)
        case .total: return avg(shots.map { $0.metrics.totalYards > 0 ? $0.metrics.totalYards : $0.metrics.carryYards }) ?? 0
        }
    }

    private func fmt(_ val: Double?, decimals: Int = 0) -> String {
        guard let v = val else { return "—" }
        return decimals > 0 ? String(format: "%.\(decimals)f", v) : "\(Int(v))"
    }


    // MARK: - Body

    private var userInitials: String {
        let name = session.userProfile?.displayName ?? session.currentUser?.name ?? "G"
        let parts = name.components(separatedBy: " ")
        if parts.count >= 2, let f = parts[0].first, let l = parts[1].first { return "\(f)\(l)" }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        ZStack {
            TrueCarryBackground(pattern: .plain)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TCHeaderBar(initials: userInitials) {
                        TCProfileAvatarButton(initials: userInitials, devMode: session.entitlementVM.isDeveloperMode) { showProfile = true }
                    }
                    VStack(spacing: TCTheme.sectionGap) {
                        pageTitleSection
                        clubPicker
                        if !gappingRows.isEmpty { gappingSection }
                        if availableClubs.isEmpty {
                            emptyState
                        } else if allMode {
                            allClubsContent
                        } else if selectedClub != nil {
                            statsContent
                        } else {
                            selectPrompt
                        }
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 8)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showProfile) {
            NavigationStack { TrueCarryProfileView() }
                .tcAppearance()
        }
        .onAppear {
            // Seed instantly from the prewarmed cache so the page never flashes empty.
            if shots.isEmpty {
                shots = session.cachedShots.filter { !$0.isBadShot && $0.metrics.carryYards > 0 }
                clubs = session.cachedClubs
                if selectedClub == nil { selectedClub = availableClubs.first }
            }
            Task { await reloadData() }
        }
        // Deletions elsewhere (history, session detail) must recompute every stat here.
        .onReceive(NotificationCenter.default.publisher(for: .tcDataChanged)) { _ in
            Task { await reloadData() }
        }
    }

    private func reloadData() async {
        guard let uid = session.currentUser?.id else { return }
        async let s = try? await session.backend.loadShots(userId: uid)
        async let c = try? await session.backend.loadClubs(userId: uid)
        async let r = try? await session.backend.loadCourseRounds(userId: uid)
        shots = (await s ?? []).filter { !$0.isBadShot && $0.metrics.carryYards > 0 }
        clubs = await c ?? []
        let rounds = await r ?? []
        roundShots = rounds.flatMap { round in
            RoundShotVerifier.verifiedShots(
                round: round,
                course: OSMGolfService.shared.loadCached(courseId: round.courseId)
            )
        }
        if selectedClub == nil || !availableClubs.contains(selectedClub ?? "") {
            selectedClub = availableClubs.first
        }
    }

    // MARK: - Page Title

    private var pageTitleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Insights")
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundColor(TCTheme.textPrimary)
            Text("Your numbers, club by club.")
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Club Picker

    private var clubPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                allChip
                ForEach(availableClubs, id: \.self) { club in
                    clubChip(club)
                }
            }
            .padding(.horizontal, TCTheme.hPad)
        }
        .padding(.horizontal, -TCTheme.hPad)
    }

    /// Top-tracer view of the whole bag at once.
    private var allChip: some View {
        Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) { allMode = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("ALL")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(allMode ? TCTheme.onPrimary : TCTheme.textMuted)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(allMode ? AnyShapeStyle(TCTheme.primaryFill) : AnyShapeStyle(TCTheme.panel))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(allMode ? Color.clear : TCTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func clubChip(_ club: String) -> some View {
        let selected = !allMode && selectedClub == club
        let count = shotsFor(club).count
        return Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                allMode = false
                selectedClub = club
            }
        } label: {
            HStack(spacing: 7) {
                Text(club)
                    .font(.system(size: 13, weight: .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(selected ? TCTheme.onPrimary.opacity(0.75) : TCTheme.textUltraMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(selected ? TCTheme.onPrimary.opacity(0.14) : TCTheme.panelRaised)
                        )
                }
            }
            .foregroundColor(selected ? TCTheme.onPrimary : TCTheme.textMuted)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(selected ? AnyShapeStyle(TCTheme.primaryFill) : AnyShapeStyle(TCTheme.panel))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(selected ? Color.clear : TCTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bag gapping

    private struct ClubGap: Identifiable {
        var id: String { club }
        let club: String
        let avgCarry: Double
        let shots: Int
        let gapToNext: Double?   // yards down to the next-shorter club
    }

    /// Clubs with enough data (3+ shots), longest first, with the carry gap to
    /// the next club down. Needs two qualifying clubs to be meaningful.
    private var gappingRows: [ClubGap] {
        let entries: [(club: String, carry: Double, count: Int)] = availableClubs.compactMap { club in
            let s = shotsFor(club)
            guard s.count >= 3 else { return nil }
            let carry = avgDistance(s)
            guard carry > 0 else { return nil }
            return (club, carry, s.count)
        }
        guard entries.count >= 2 else { return [] }
        let sorted = entries.sorted { $0.carry > $1.carry }
        return sorted.enumerated().map { i, e in
            ClubGap(club: e.club, avgCarry: e.carry, shots: e.count,
                    gapToNext: i + 1 < sorted.count ? e.carry - sorted[i + 1].carry : nil)
        }
    }

    private func gapNote(_ gap: Double) -> (text: String, color: Color)? {
        if gap > 25 { return ("\(Int(gap.rounded()))y — big gap", TCTheme.gold) }
        if gap < 8 { return ("\(Int(gap.rounded()))y — overlap", TCTheme.cyan) }
        return nil
    }

    private var gappingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BAG GAPPING")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted)
                    .tracking(1.5)
                TCInfoMark(title: "Bag gapping",
                           text: "Clubs sorted by average distance. Two clubs within a few yards are doing the same job; a gap bigger than ~15 yards is a distance you can't hit. Only clubs with 3+ measured shots are shown.")
                Spacer()
                Text(dispersionMetric == .carry ? "avg carry · 3+ shots" : "avg total · 3+ shots")
                    .font(.system(size: 10))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
            let maxCarry = gappingRows.first?.avgCarry ?? 1
            ForEach(gappingRows) { row in
                VStack(spacing: 4) {
                    HStack(spacing: 10) {
                        Text(row.club)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(TCTheme.textPrimary)
                            .frame(width: 84, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(TCTheme.panelRaised)
                                Capsule()
                                    .fill(TCTheme.gold.opacity(0.8))
                                    .frame(width: max(8, geo.size.width * CGFloat(row.avgCarry / maxCarry)))
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int(row.avgCarry.rounded()))y")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(TCTheme.textPrimary)
                            .frame(width: 48, alignment: .trailing)
                    }
                    if let gap = row.gapToNext, let note = gapNote(gap) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8, weight: .bold))
                            Text(note.text)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(note.color)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .tcCard(padding: 14)
    }

    // MARK: - Empty / Prompt

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bag")
                .font(.system(size: 32))
                .foregroundColor(TCTheme.textUltraMuted)
            Text("No clubs in your bag yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(TCTheme.textPrimary)
            Text("Add clubs from Profile to view your shot insights here.")
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .tcCard(padding: 16)
    }

    private var selectPrompt: some View {
        Text("Select a club above to see your stats.")
            .font(.system(size: 14))
            .foregroundColor(TCTheme.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .tcCard(padding: 16)
    }

    // MARK: - Stats Content

    @ViewBuilder
    private var statsContent: some View {
        let s = selectedShots
        dispersionCard(s)
        singleClubKeyCard
        metricsCard(s)
        carryTrendCard(s)
        spinCard(s)
        advancedCard(s)
        Spacer(minLength: 140)
    }

    // MARK: - ALL mode (top-tracer: every club, colored clusters)

    /// One series per club with any plottable shots — camera shots always, verified
    /// on-course shots folded in when the Total toggle is active.
    private var allClubSeries: [TCRangeFinderDispersion.ClubSeries] {
        availableClubs.enumerated().compactMap { index, club in
            var pts = shotsFor(club).compactMap { rangePoint(for: $0) }
            if dispersionMetric == .total {
                pts += roundShotsFor(club).map {
                    TCRangeFinderDispersion.ShotPoint(carry: $0.distanceYards, lateral: $0.lateralYards)
                }
            }
            guard !pts.isEmpty else { return nil }
            return TCRangeFinderDispersion.ClubSeries(
                id: club, name: club,
                color: TCDispersionColor.club(index),
                points: pts
            )
        }
    }

    @ViewBuilder
    private var allClubsContent: some View {
        let series = allClubSeries
        if series.isEmpty {
            Text("Hit some shots to see your whole bag plotted here.")
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .tcCard(padding: 16)
        } else {
            allClubsCard(series)
            allClubsKeyCard(series)
        }
        Spacer(minLength: 140)
    }

    private func allClubsCard(_ series: [TCRangeFinderDispersion.ClubSeries]) -> some View {
        let allPoints = series.flatMap(\.points)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                cardHeader("Whole Bag", "Every club's \(dispersionMetric.rawValue.lowercased()) cluster at once")
                Spacer(minLength: 8)
                dispersionMetricPicker
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            TCRangeFinderDispersion(shots: allPoints, clubSeries: series)
                .frame(maxWidth: .infinity)
                .frame(height: 460)

            HStack(spacing: 0) {
                inlineStat("\(series.count)", "CLUBS")
                verticalDivider(height: 28)
                inlineStat("\(allPoints.count)", "SHOTS")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, -TCTheme.hPad)
    }

    /// Legend: which color is which club, plus what the rings mean.
    private func allClubsKeyCard(_ series: [TCRangeFinderDispersion.ClubSeries]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("Key", "Colors & clusters")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(series) { club in
                    HStack(spacing: 6) {
                        Circle().fill(club.color).frame(width: 10, height: 10)
                        Text(club.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(TCTheme.textPrimary)
                            .lineLimit(1)
                        Text("\(club.points.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(TCTheme.textUltraMuted)
                    }
                }
            }
            TCDivider()
            keyRow(swatch: AnyView(
                Circle().strokeBorder(TCTheme.textMuted, lineWidth: 1.6).frame(width: 12, height: 12)
            ), text: "Ring = that club's typical grouping (2σ of its shots)")
            keyRow(swatch: AnyView(
                RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.14, green: 0.30, blue: 0.12)).frame(width: 12, height: 12)
            ), text: "Green stripe = fairway width (±20 yd of your target line)")
        }
        .tcCard(padding: 14)
    }

    /// Single-club key: what the dot colors mean (graded by how far offline the shot landed).
    private var singleClubKeyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHeader("Key", "Dot colors = distance offline")
            keyRow(swatch: AnyView(Circle().fill(TCDispersionColor.byLateral(0)).frame(width: 12, height: 12)),
                   text: "Dark green — dead straight (within 5 yd of center)")
            keyRow(swatch: AnyView(Circle().fill(TCDispersionColor.byLateral(8)).frame(width: 12, height: 12)),
                   text: "Light green — close (5–12 yd offline)")
            keyRow(swatch: AnyView(Circle().fill(TCDispersionColor.byLateral(18)).frame(width: 12, height: 12)),
                   text: "Yellow — drifting (12–25 yd offline)")
            keyRow(swatch: AnyView(Circle().fill(TCDispersionColor.byLateral(30)).frame(width: 12, height: 12)),
                   text: "Red — offline by 25+ yd")
            TCDivider()
            keyRow(swatch: AnyView(
                Circle().strokeBorder(TCTheme.textMuted, lineWidth: 1.6).frame(width: 12, height: 12)
            ), text: "White ring = your typical grouping (2σ)")
            keyRow(swatch: AnyView(
                RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.14, green: 0.30, blue: 0.12)).frame(width: 12, height: 12)
            ), text: "Green stripe = fairway width (±20 yd of your target line)")
            keyRow(swatch: AnyView(
                Circle().fill(TCDispersionColor.byLateral(0)).frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
            ), text: "Bigger dot = several shots landed on the same spot")
        }
        .tcCard(padding: 14)
    }

    private func keyRow(swatch: AnyView, text: String) -> some View {
        HStack(spacing: 10) {
            swatch.frame(width: 14)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(TCTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Advanced (Pro)

    private func stdDev(_ vals: [Double]) -> Double? {
        let f = vals.filter { $0 > 0 }
        guard f.count > 1, let m = avg(f) else { return nil }
        let variance = f.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(f.count)
        return variance.squareRoot()
    }

    @ViewBuilder
    private func advancedCard(_ shots: [SavedShot]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader("Advanced", "Consistency & efficiency")
            if !session.entitlementVM.canAccessAdvancedInsights {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill").foregroundColor(TCTheme.gold)
                    Text("Upgrade to Pro to unlock consistency, dispersion spread, and gapping.")
                        .font(.system(size: 13)).foregroundColor(TCTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let carrySD = stdDev(shots.map { $0.metrics.carryYards })
                let speedSD = stdDev(shots.map { $0.metrics.ballSpeedMph })
                let smashAvg = avg(shots.map { $0.metrics.smashFactor })
                let carriesSorted = shots.map { $0.metrics.carryYards }.filter { $0 > 0 }.sorted()
                let spread = (carriesSorted.last ?? 0) - (carriesSorted.first ?? 0)
                let cv: Double? = {
                    guard let sd = carrySD, let m = avg(shots.map { $0.metrics.carryYards }), m > 0 else { return nil }
                    return sd / m * 100
                }()
                VStack(spacing: 0) {
                    advRow("Carry consistency (± std dev)", carrySD.map { "± \(fmt($0, decimals: 1)) yd" } ?? "—")
                    advDivider
                    advRow("Carry spread (long − short)", spread > 0 ? "\(fmt(spread)) yd" : "—")
                    advDivider
                    advRow("Consistency score", cv.map { String(format: "%.0f%%", max(0, 100 - $0 * 4)) } ?? "—")
                    advDivider
                    advRow("Ball-speed consistency", speedSD.map { "± \(fmt($0, decimals: 1)) mph" } ?? "—")
                    advDivider
                    advRow("Avg smash factor", smashAvg.map { fmt($0, decimals: 2) } ?? "—")
                    advDivider
                    advRow("Shots analyzed", "\(shots.count)")
                }
            }
        }
        .padding(16)
        .tcCard()
    }

    private func advRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundColor(TCTheme.textMuted)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundColor(TCTheme.textPrimary)
        }
        .padding(.vertical, 11)
    }

    private var advDivider: some View {
        Rectangle().fill(TCTheme.border).frame(height: 1)
    }

    /// Toggles whether dispersion dots plot at carry (first landing) or total (after roll).
    private var dispersionMetricPicker: some View {
        HStack(spacing: 2) {
            ForEach(DispersionMetric.allCases, id: \.self) { metric in
                Button {
                    dispersionMetric = metric
                } label: {
                    Text(metric.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(dispersionMetric == metric ? TCTheme.background : TCTheme.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(dispersionMetric == metric ? TCTheme.gold : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(TCTheme.panelRaised))
        .fixedSize()
    }

    /// Card header with the small Marker Gold tick (the brand title treatment).
    private func cardHeader(_ title: String, _ subtitle: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(TCTheme.gold)
                .frame(width: 3, height: 14)
                .clipShape(Capsule())
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Dispersion

    /// Converts a camera shot to a plotted dispersion point (lateral from HLA + curve; the
    /// same physics ShotResultView animates). Shared by the single-club and ALL charts.
    private func rangePoint(for shot: SavedShot) -> TCRangeFinderDispersion.ShotPoint? {
        let carry = shot.metrics.carryYards
        guard carry > 0 else { return nil }
        let total = shot.metrics.totalYards > 0 ? shot.metrics.totalYards : carry

        // Signed HLA component
        let signedHLA = shot.metrics.hlaDirection.lowercased() == "left"
            ? -shot.metrics.hlaDegrees : shot.metrics.hlaDegrees
        let hlaRad = signedHLA * .pi / 180.0

        // Curve from spin axis (preferred) or sidespin — identical to ShotResultView
        let spinAxis = shot.metrics.spinAxisDegrees   // already signed
        let sidespin = shot.metrics.sidespinRpm       // already signed
        let curveStrength: Double
        if abs(spinAxis) > 0.5 {
            curveStrength = (spinAxis > 0 ? 1.0 : -1.0) * min(abs(spinAxis) / 16.0, 1.0)
        } else if abs(sidespin) > 30 {
            curveStrength = (sidespin > 0 ? 1.0 : -1.0) * min(abs(sidespin) / 1100.0, 1.0)
        } else {
            curveStrength = 0
        }
        let curveMagnitude = abs(curveStrength) * max(total * 0.10, 8.0)
        let curveSign: Double = curveStrength >= 0 ? 1.0 : -1.0

        // Lateral landing at the carry point (p = carry / total)
        let carryFrac = carry / total
        let lateral = tan(hlaRad) * total * carryFrac
                    + curveSign * curveMagnitude * pow(carryFrac, 1.6)

        let plotted = dispersionMetric == .carry ? carry : total
        return TCRangeFinderDispersion.ShotPoint(carry: plotted, lateral: lateral)
    }

    private func dispersionCard(_ shots: [SavedShot]) -> some View {
        var rangePoints = shots.compactMap { rangePoint(for: $0) }
        // Verified on-course shots are total-distance points (GPS start → end, roll included),
        // so they join the chart in Total view — with the real measured lateral miss.
        let courseShots = selectedRoundShots
        if dispersionMetric == .total {
            rangePoints += courseShots.map {
                TCRangeFinderDispersion.ShotPoint(carry: $0.distanceYards, lateral: $0.lateralYards)
            }
        }
        let dispersion = TCRangeFinderDispersion(shots: rangePoints)

        let avgDispStr: String = {
            guard let d = dispersion.avgDispersionYds else { return "—" }
            return String(format: "%.0f yds", d)
        }()

        let onTarget: String = {
            guard !shots.isEmpty else { return "—" }
            let n = shots.filter { $0.metrics.hlaDegrees < 5.0 }.count
            return "\(Int(Double(n) / Double(shots.count) * 100))%"
        }()

        // Manually build the card so the chart can bleed to the card edges (no horizontal padding)
        return VStack(alignment: .leading, spacing: 0) {
            // Header — padded
            HStack(alignment: .top) {
                cardHeader("Shot Dispersion", "\(dispersionMetric.rawValue) distance & lateral spread")
                Spacer(minLength: 8)
                dispersionMetricPicker
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Chart — full card width, no horizontal padding
            dispersion
                .frame(maxWidth: .infinity)
                .frame(height: 420)

            // Stats — padded
            HStack(spacing: 0) {
                inlineStat(avgDispStr,                             "AVG DISPERSION")
                verticalDivider(height: 28)
                inlineStat(onTarget,                               "ON TARGET (<5°)")
                verticalDivider(height: 28)
                inlineStat(rangePoints.isEmpty ? "—" : "\(rangePoints.count)", "SHOTS")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if dispersionMetric == .total && !courseShots.isEmpty {
                Text("Includes \(courseShots.count) verified on-course shot\(courseShots.count == 1 ? "" : "s") (GPS distance + lateral miss).")
                    .font(.system(size: 10))
                    .foregroundColor(TCTheme.textUltraMuted)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                .strokeBorder(TCTheme.border, lineWidth: 1)
        )
        // Break out of the parent's horizontal padding so the card fills edge-to-edge
        .padding(.horizontal, -TCTheme.hPad)
    }

    // MARK: - Main Metrics

    private func metricsCard(_ shots: [SavedShot]) -> some View {
        let carry  = avg(shots.map { $0.metrics.carryYards })
        let best   = shots.map { $0.metrics.carryYards }.filter { $0 > 0 }.max()
        let speed  = avg(shots.map { $0.metrics.ballSpeedMph }.filter { $0 > 0 })
        let launch = avg(shots.map { $0.metrics.vlaDegrees }.filter { $0 > 0 })
        return VStack(alignment: .leading, spacing: 16) {
            cardHeader("Key Metrics")
            HStack(spacing: 0) {
                statCol("AVG CARRY",     fmt(carry),               carry  == nil ? "" : "yds")
                verticalDivider(height: 40)
                statCol("BEST CARRY",    fmt(best),                best   == nil ? "" : "yds")
                verticalDivider(height: 40)
                statCol("AVG BALL SPD",  fmt(speed),               speed  == nil ? "" : "mph")
                verticalDivider(height: 40)
                statCol("AVG VLA",       fmt(launch, decimals: 1), launch == nil ? "" : "°")
            }
        }
        .tcCard(padding: 16)
    }

    // MARK: - Carry Trend

    private func carryTrendCard(_ shots: [SavedShot]) -> some View {
        let sorted  = shots.sorted { $0.timestamp < $1.timestamp }
        let carries = Array(sorted.map { $0.metrics.carryYards }.filter { $0 > 0 }.suffix(10))
        let avgC    = avg(carries)
        let bestC   = carries.max()
        let avgSpd  = avg(sorted.suffix(10).map { $0.metrics.ballSpeedMph }.filter { $0 > 0 })

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                cardHeader("Carry Trend")
                Text(carries.isEmpty ? "" : "Last \(carries.count) shots")
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
                    .fixedSize()
            }

            if carries.isEmpty {
                Text("Hit more shots to see your carry trend.")
                    .font(.system(size: 13))
                    .foregroundColor(TCTheme.textMuted)
                    .padding(.vertical, 8)
            } else {
                TCTrendLine(values: carries, color: TCTheme.sage, axisUnit: "yd")
                    .frame(height: 84)
            }

            HStack(spacing: 0) {
                statCol("BEST CARRY", bestC.map { "\(Int($0))" } ?? "—", bestC == nil ? "" : "yds")
                verticalDivider(height: 40)
                statCol("AVG CARRY",  avgC.map  { "\(Int($0))" } ?? "—", avgC  == nil ? "" : "yds")
                verticalDivider(height: 40)
                statCol("AVG BALL SPD", avgSpd.map { "\(Int($0))" } ?? "—", avgSpd == nil ? "" : "mph")
            }
        }
        .tcCard(padding: 16)
    }

    // MARK: - Spin / Ball Data

    private func spinCard(_ shots: [SavedShot]) -> some View {
        let spin      = avg(shots.map { $0.metrics.backspinRpm }.filter { $0 > 0 })
        let smash     = avg(shots.map { $0.metrics.smashFactor }.filter { $0 > 0 })
        let cSpeed    = avg(shots.map { $0.metrics.clubSpeedMph }.filter { $0 > 0 })
        let medCarry  = median(shots.map { $0.metrics.carryYards })
        return VStack(alignment: .leading, spacing: 16) {
            cardHeader("Ball Data")
            HStack(spacing: 0) {
                statCol("AVG BACKSPIN",    fmt(spin),               spin     == nil ? "" : "rpm")
                verticalDivider(height: 40)
                statCol("AVG SMASH",       fmt(smash, decimals: 2), "")
                verticalDivider(height: 40)
                statCol("AVG CLUB SPD",    fmt(cSpeed),             cSpeed   == nil ? "" : "mph")
                verticalDivider(height: 40)
                statCol("MEDIAN CARRY",    fmt(medCarry),           medCarry == nil ? "" : "yds")
            }
        }
        .tcCard(padding: 16)
    }

    // MARK: - Reusable stat views

    private func statCol(_ label: String, _ value: String, _ unitStr: String) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundColor(TCTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unitStr.isEmpty && value != "—" {
                    Text(unitStr)
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func inlineStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(TCTheme.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(TCTheme.textMuted)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func verticalDivider(height: CGFloat) -> some View {
        Rectangle()
            .fill(TCTheme.borderMedium)
            .frame(width: 1, height: height)
    }
}
