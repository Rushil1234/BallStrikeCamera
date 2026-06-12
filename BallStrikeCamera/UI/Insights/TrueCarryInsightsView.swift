import SwiftUI

struct TrueCarryInsightsView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var shots: [SavedShot] = []
    @State private var clubs: [UserClub]  = []
    @State private var selectedClub: String? = nil
    @State private var showProfile = false

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
            if shot.clubName == club { return true }
            guard let clubId = shot.clubId else { return false }
            return clubIds.contains(clubId)
        }
    }

    private var selectedShots: [SavedShot] {
        selectedClub.map { shotsFor($0) } ?? []
    }

    // MARK: - Stat helpers

    private func avg(_ vals: [Double]) -> Double? {
        let f = vals.filter { $0 > 0 }
        guard !f.isEmpty else { return nil }
        return f.reduce(0, +) / Double(f.count)
    }

    private func avgCarry(_ shots: [SavedShot]) -> Double {
        avg(shots.map { $0.metrics.carryYards }) ?? 0
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
                        if availableClubs.isEmpty {
                            emptyState
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
        .task {
            guard let uid = session.currentUser?.id else { return }
            async let s = try? await session.backend.loadShots(userId: uid)
            async let c = try? await session.backend.loadClubs(userId: uid)
            shots = await s ?? []
            clubs = await c ?? []
            if selectedClub == nil || !availableClubs.contains(selectedClub ?? "") {
                selectedClub = availableClubs.first
            }
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
                ForEach(availableClubs, id: \.self) { club in
                    clubChip(club)
                }
            }
            .padding(.horizontal, TCTheme.hPad)
        }
        .padding(.horizontal, -TCTheme.hPad)
    }

    private func clubChip(_ club: String) -> some View {
        let selected = selectedClub == club
        let count = shotsFor(club).count
        return Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) { selectedClub = club }
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
        metricsCard(s)
        carryTrendCard(s)
        spinCard(s)
        Spacer(minLength: 140)
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

    private func dispersionCard(_ shots: [SavedShot]) -> some View {
        let rangePoints = shots.compactMap { shot -> TCRangeFinderDispersion.ShotPoint? in
            guard shot.metrics.carryYards > 0 else { return nil }
            let hla = shot.metrics.hlaDirection.lowercased() == "left"
                ? -shot.metrics.hlaDegrees
                : shot.metrics.hlaDegrees
            return TCRangeFinderDispersion.ShotPoint(carry: shot.metrics.carryYards, hla: hla)
        }

        let hlaSpread: String = {
            let vals = shots.map { s -> Double in
                let d = s.metrics.hlaDegrees
                return s.metrics.hlaDirection.lowercased() == "left" ? -d : d
            }
            guard vals.count > 1 else { return "—" }
            return String(format: "%.1f°", (vals.max() ?? 0) - (vals.min() ?? 0))
        }()

        let onTarget: String = {
            guard !shots.isEmpty else { return "—" }
            let n = shots.filter { $0.metrics.hlaDegrees < 3.0 }.count
            return "\(Int(Double(n) / Double(shots.count) * 100))%"
        }()

        return VStack(alignment: .leading, spacing: 16) {
            cardHeader("Shot Dispersion", "Carry distance & lateral spread")

            TCRangeFinderDispersion(shots: rangePoints)
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 0) {
                inlineStat(onTarget,                           "ON TARGET")
                verticalDivider(height: 28)
                inlineStat(hlaSpread,                          "HLA SPREAD")
                verticalDivider(height: 28)
                inlineStat(shots.isEmpty ? "—" : "\(shots.count)", "SHOTS")
            }
        }
        .tcCard(padding: 16)
    }

    // MARK: - Main Metrics

    private func metricsCard(_ shots: [SavedShot]) -> some View {
        let carry  = avg(shots.map { $0.metrics.carryYards })
        let best   = shots.map { $0.metrics.carryYards }.filter { $0 > 0 }.max()
        let speed  = avg(shots.map { $0.metrics.ballSpeedMph })
        let launch = avg(shots.map { $0.metrics.vlaDegrees })
        return VStack(alignment: .leading, spacing: 16) {
            cardHeader("Key Metrics")
            HStack(spacing: 0) {
                statCol("AVG CARRY",  fmt(carry),               carry  == nil ? "" : "yds")
                verticalDivider(height: 40)
                statCol("BEST CARRY", fmt(best),                best   == nil ? "" : "yds")
                verticalDivider(height: 40)
                statCol("BALL SPEED", fmt(speed),               speed  == nil ? "" : "mph")
                verticalDivider(height: 40)
                statCol("LAUNCH",     fmt(launch, decimals: 1), launch == nil ? "" : "°")
            }
        }
        .tcCard(padding: 16)
    }

    // MARK: - Carry Trend

    private func carryTrendCard(_ shots: [SavedShot]) -> some View {
        let carries = Array(
            shots.sorted { $0.timestamp < $1.timestamp }
                .map { $0.metrics.carryYards }.filter { $0 > 0 }.suffix(10)
        )
        let avgC  = avg(carries)
        let bestC = carries.max()

        let changeStr: String = {
            guard carries.count >= 4 else { return "—" }
            let half   = carries.count / 2
            let early  = Array(carries.prefix(half)).reduce(0, +) / Double(half)
            let recent = Array(carries.suffix(half)).reduce(0, +) / Double(half)
            let diff   = Int(recent - early)
            return diff >= 0 ? "+\(diff) yds" : "\(diff) yds"
        }()

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
                TCTrendLine(values: carries, color: TCTheme.sage)
                    .frame(height: 56)
            }

            HStack(spacing: 0) {
                statCol("BEST",    bestC.map { "\(Int($0))" } ?? "—", bestC == nil ? "" : "yds")
                verticalDivider(height: 40)
                statCol("AVERAGE", avgC.map  { "\(Int($0))" } ?? "—", avgC  == nil ? "" : "yds")
                verticalDivider(height: 40)
                statCol("CHANGE",  changeStr, "")
            }
        }
        .tcCard(padding: 16)
    }

    // MARK: - Spin / Ball Data

    private func spinCard(_ shots: [SavedShot]) -> some View {
        let spin   = avg(shots.map { $0.metrics.backspinRpm })
        let smash  = avg(shots.map { $0.metrics.smashFactor })
        let cSpeed = avg(shots.map { $0.metrics.clubSpeedMph })
        let total  = avg(shots.map { $0.metrics.totalYards })
        return VStack(alignment: .leading, spacing: 16) {
            cardHeader("Ball Data")
            HStack(spacing: 0) {
                statCol("BACKSPIN",     fmt(spin),               spin   == nil ? "" : "rpm")
                verticalDivider(height: 40)
                statCol("SMASH FACTOR", fmt(smash, decimals: 2), "")
                verticalDivider(height: 40)
                statCol("CLUB SPEED",   fmt(cSpeed),             cSpeed == nil ? "" : "mph")
                verticalDivider(height: 40)
                statCol("TOTAL DIST",   fmt(total),              total  == nil ? "" : "yds")
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
