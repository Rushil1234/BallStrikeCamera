import SwiftUI

struct TrueCarryInsightsView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var shots: [SavedShot] = []
    @State private var clubs: [UserClub]  = []
    @State private var selectedClub: String? = nil
    @State private var showProfile = false

    // MARK: - Club list

    private var availableClubs: [String] {
        var names = Set<String>()
        clubs.forEach { names.insert($0.name) }
        shots.compactMap { $0.clubName }.filter { !$0.isEmpty }.forEach { names.insert($0) }
        return names.sorted { avgCarry(shotsFor($0)) > avgCarry(shotsFor($1)) }
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

    // MARK: - Dispersion dots

    private func dispersionDots(_ shots: [SavedShot]) -> [(x: CGFloat, y: CGFloat)] {
        let valid = shots.filter { $0.metrics.carryYards > 0 }
        guard !valid.isEmpty else { return [] }
        let carries    = valid.map { $0.metrics.carryYards }
        let avgC       = carries.reduce(0, +) / Double(carries.count)
        let carryRange = max((carries.max() ?? avgC) - (carries.min() ?? avgC), 1)
        let hlaValues  = valid.map { s -> Double in
            let d = s.metrics.hlaDegrees
            return s.metrics.hlaDirection.lowercased() == "left" ? -d : d
        }
        let maxAbsHLA = max(hlaValues.map { abs($0) }.max() ?? 1, 0.5)
        return zip(valid, hlaValues).map { shot, hla in
            let xOff = CGFloat(hla / (maxAbsHLA * 2.0)) * 0.18
            let yOff = CGFloat((shot.metrics.carryYards - avgC) / (carryRange * 0.6)) * 0.15
            return (x: min(max(0.5 + xOff, 0.15), 0.85),
                    y: min(max(0.5 - yOff, 0.20), 0.80))
        }
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
            TrueCarryBackground(pattern: .dimple)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    TCHeaderBar(initials: userInitials) {
                        TCProfileAvatarButton(initials: userInitials, devMode: session.entitlementVM.isDeveloperMode) { showProfile = true }
                    }
                    VStack(spacing: 0) {
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

    // MARK: - Separator

    private var sep: some View {
        Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
    }

    // MARK: - Club Picker

    private var clubPicker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("CLUB")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.40))
                    .tracking(1.5)

                Picker("", selection: $selectedClub) {
                    Text("Select a club").tag(Optional<String>.none)
                    ForEach(availableClubs, id: \.self) { club in
                        let count = shotsFor(club).count
                        Text(count > 0 ? "\(club)  ·  \(count) shots" : club)
                            .tag(Optional<String>.some(club))
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)

                Spacer()
            }
            .padding(.vertical, 14)

            sep
        }
    }

    // MARK: - Empty / Prompt

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.25))
            Text("No shots recorded yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.70))
            Text("Hit shots in a range session with a club selected to see your stats here.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.40))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var selectPrompt: some View {
        Text("Select a club above to see your stats.")
            .font(.system(size: 14))
            .foregroundColor(.white.opacity(0.40))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    // MARK: - Stats Content

    @ViewBuilder
    private var statsContent: some View {
        let s = selectedShots
        dispersionSection(s)
        sep
        metricsSection(s)
        sep
        carryTrendSection(s)
        sep
        spinSection(s)
        Spacer(minLength: 140)
    }

    // MARK: - Dispersion

    private func dispersionSection(_ shots: [SavedShot]) -> some View {
        let dots = dispersionDots(shots)

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
            VStack(alignment: .leading, spacing: 3) {
                Text("Shot Dispersion")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text("Plotted from horizontal launch angle and carry")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.40))
            }
            .padding(.top, 20)

            TCDispersionFairwayGraphic(dots: dots, showRings: true)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 0) {
                inlineStat(onTarget,                                          "ON TARGET")
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 28)
                inlineStat(hlaSpread,                                         "HLA SPREAD")
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 28)
                inlineStat(shots.isEmpty ? "—" : "\(shots.count)",            "SHOTS")
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Main Metrics

    private func metricsSection(_ shots: [SavedShot]) -> some View {
        let carry  = avg(shots.map { $0.metrics.carryYards })
        let best   = shots.map { $0.metrics.carryYards }.filter { $0 > 0 }.max()
        let speed  = avg(shots.map { $0.metrics.ballSpeedMph })
        let launch = avg(shots.map { $0.metrics.vlaDegrees })
        return HStack(spacing: 0) {
            statCol("AVG CARRY",  fmt(carry),               carry  == nil ? "" : "yds")
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 40)
            statCol("BEST CARRY", fmt(best),                best   == nil ? "" : "yds")
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 40)
            statCol("BALL SPEED", fmt(speed),               speed  == nil ? "" : "mph")
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 40)
            statCol("LAUNCH",     fmt(launch, decimals: 1), launch == nil ? "" : "°")
        }
        .padding(.vertical, 20)
    }

    // MARK: - Carry Trend

    private func carryTrendSection(_ shots: [SavedShot]) -> some View {
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
            HStack {
                Text("Carry Trend")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(carries.isEmpty ? "" : "Last \(carries.count) shots")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.40))
            }
            .padding(.top, 20)

            if carries.isEmpty {
                Text("Hit more shots to see your carry trend.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.40))
                    .padding(.vertical, 20)
            } else {
                TCTrendLine(values: carries, color: .white.opacity(0.70))
                    .frame(height: 56)
            }

            HStack(spacing: 0) {
                statCol("BEST",    bestC.map { "\(Int($0))" } ?? "—", bestC == nil ? "" : "yds")
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 40)
                statCol("AVERAGE", avgC.map  { "\(Int($0))" } ?? "—", avgC  == nil ? "" : "yds")
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 40)
                statCol("CHANGE",  changeStr, "")
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Spin / Ball Data

    private func spinSection(_ shots: [SavedShot]) -> some View {
        let spin   = avg(shots.map { $0.metrics.backspinRpm })
        let smash  = avg(shots.map { $0.metrics.smashFactor })
        let cSpeed = avg(shots.map { $0.metrics.clubSpeedMph })
        let total  = avg(shots.map { $0.metrics.totalYards })
        return HStack(spacing: 0) {
            statCol("BACKSPIN",     fmt(spin),               spin   == nil ? "" : "rpm")
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 40)
            statCol("SMASH FACTOR", fmt(smash, decimals: 2), "")
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 40)
            statCol("CLUB SPEED",   fmt(cSpeed),             cSpeed == nil ? "" : "mph")
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 40)
            statCol("TOTAL DIST",   fmt(total),              total  == nil ? "" : "yds")
        }
        .padding(.vertical, 20)
    }

    // MARK: - Reusable stat views

    private func statCol(_ label: String, _ value: String, _ unitStr: String) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                if !unitStr.isEmpty && value != "—" {
                    Text(unitStr)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.50))
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.40))
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func inlineStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.40))
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}
