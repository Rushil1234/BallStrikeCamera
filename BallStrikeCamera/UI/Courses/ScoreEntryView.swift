import SwiftUI

struct ScoreEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: AuthSessionStore

    let holeNumber: Int
    let par: Int
    var existingScore: Int?
    var existingPutts: Int?
    var holeYardage: Int?
    var handicap: Int?
    let onSave: (Int, Int?, Bool?, Bool?) -> Void

    @State private var score: Int
    @State private var putts: Int
    @State private var teeShotDir: String = "HIT"
    @State private var misHit: Bool = false
    @State private var teeClub: String? = nil
    @State private var firstPuttFeet: Int = 0
    @State private var inFwBunker: Bool = false
    @State private var inGreenSideBunker: Bool = false
    @State private var hazard: Bool = false
    @State private var dropShot: Bool = false
    @State private var ob: Bool = false
    @State private var onThisHole: Bool = false

    private static let teeClubs = ["Dr", "3W", "5W", "Hyb", "4i", "5i", "6i", "7i", "8i", "9i", "PW", "GW"]

    // MARK: - Init

    init(holeNumber: Int, par: Int,
         existingScore: Int? = nil, existingPutts: Int? = nil,
         holeYardage: Int? = nil, handicap: Int? = nil,
         onSave: @escaping (Int, Int?, Bool?, Bool?) -> Void) {
        self.holeNumber    = holeNumber
        self.par           = par
        self.existingScore = existingScore
        self.existingPutts = existingPutts
        self.holeYardage   = holeYardage
        self.handicap      = handicap
        self.onSave        = onSave
        _score = State(initialValue: existingScore ?? par)
        _putts = State(initialValue: existingPutts ?? 2)
    }

    // MARK: - Computed

    // GIR: strokes before putting must be ≤ par − 2
    private var computedGIR: Bool { (score - putts) <= (par - 2) }
    private var scoreDelta: Int { score - par }

    private var scoreSummaryLabel: String {
        switch scoreDelta {
        case ..<(-1): return "Eagle"
        case -1:      return "Birdie"
        case 0:       return "Par"
        case 1:       return "Bogey"
        case 2:       return "Double"
        default:      return "+\(scoreDelta)"
        }
    }

    private var scoreSummaryColor: Color {
        if scoreDelta < 0  { return TCTheme.sage }
        if scoreDelta == 0 { return Color(red: 0.42, green: 0.72, blue: 0.98) }
        return TCTheme.gold
    }

    private var scoreDeltaText: String {
        scoreDelta == 0 ? "E" : (scoreDelta > 0 ? "+\(scoreDelta)" : "\(scoreDelta)")
    }

    private var userName: String { session.userProfile?.displayName ?? "Player" }

    private var userInitials: String {
        let parts = userName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].first ?? "P").uppercased()
                 + String(parts[1].first ?? "L").uppercased()
        }
        return String(userName.prefix(2)).uppercased()
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            TCTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                mapHeader
                Spacer(minLength: 0)
            }
            scoreSheet
        }
        .navigationBarHidden(true)
    }

    // MARK: - Map Header

    private var mapHeader: some View {
        ZStack(alignment: .top) {
            GeneratedFairwayView()
                .frame(height: 150)
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0.10), Color.black.opacity(0.60)],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            VStack(spacing: 10) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                VStack(spacing: 6) {
                    Text("Hole \(holeNumber)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.70))
                        .tracking(0.5)
                    HStack(spacing: 0) {
                        holeChip("Par \(par)")
                        if let y = holeYardage { holeChip("\(y) yds") }
                        if let h = handicap     { holeChip("HCP \(h)") }
                    }
                    .background(Color.black.opacity(0.35))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20).padding(.top, 16)
        }
    }

    private func holeChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.90))
            .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: - Score Sheet

    private var scoreSheet: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(TCTheme.borderMedium)
                .frame(width: 40, height: 4)
                .padding(.top, 10).padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    playerHeaderRow
                    rowDivider
                    mainStatsRow
                    rowDivider
                    teeShotColumn.padding(.vertical, 16)
                    rowDivider
                    subStatsRow
                    rowDivider
                    bunkersSection
                    rowDivider
                    penaltiesSection
                    saveFooter.padding(.top, 14)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 36)
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(TCTheme.panel)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(TCTheme.borderMedium, lineWidth: 1)
            }
        )
        .padding(.horizontal, 6)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Player Header Row

    private var playerHeaderRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(TCTheme.panelRaised)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(TCTheme.border, lineWidth: 1))
                Text(userInitials)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(userName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                HStack(spacing: 6) {
                    Text(scoreSummaryLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(scoreSummaryColor)
                    Text(scoreDeltaText)
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                    if computedGIR {
                        Text("GIR")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(TCTheme.sage)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(TCTheme.sage.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Button(action: saveAndDismiss) {
                Text("Save")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.gold)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 14)
    }

    // MARK: - Main Stats Row (Score | Putts | Tee Shot)

    private var mainStatsRow: some View {
        VStack(spacing: 16) {
            heroScore
            HStack(spacing: 12) {
                stepperCard(label: "Score", value: score, valueColor: scoreSummaryColor,
                            onMinus: { if score > 1 { score -= 1 } }, onPlus: { score += 1 })
                stepperCard(label: "Putts", value: putts, valueColor: TCTheme.textPrimary,
                            onMinus: { if putts > 0 { putts -= 1 } }, onPlus: { putts += 1 })
            }
        }
        .padding(.vertical, 18)
    }

    /// Big result-forward score readout — the focal point of the sheet.
    private var heroScore: some View {
        VStack(spacing: 8) {
            Text("\(score)")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundColor(scoreSummaryColor)
                .contentTransition(.numericText())
                .frame(minWidth: 72)
            HStack(spacing: 8) {
                Text(scoreSummaryLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(scoreSummaryColor)
                Text(scoreDeltaText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(TCTheme.textMuted)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(TCTheme.panelRaised)
                    .clipShape(Capsule())
                if computedGIR {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 10, weight: .bold))
                        Text("GIR").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(TCTheme.sage)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(TCTheme.sage.opacity(0.15)).clipShape(Capsule())
                }
            }
        }
    }

    private func stepperCard(label: String, value: Int, valueColor: Color,
                             onMinus: @escaping () -> Void, onPlus: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            colLabel(label)
            HStack(spacing: 14) {
                stepCircle("minus", action: onMinus)
                Text("\(value)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(valueColor)
                    .frame(minWidth: 30)
                    .contentTransition(.numericText())
                stepCircle("plus", action: onPlus)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(TCTheme.panelRaised.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
            .strokeBorder(TCTheme.border, lineWidth: 1))
    }

    private var teeShotColumn: some View {
        VStack(spacing: 6) {
            colLabel("Tee Shot")
            teeShotPad
            Button {
                withAnimation(.spring(response: 0.2)) { misHit.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: misHit ? "xmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 11))
                    Text("Mis-Hit")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundColor(misHit ? TCTheme.danger : TCTheme.textUltraMuted)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private var teeShotPad: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Color.clear.frame(width: 30, height: 30)
                dirButton("arrow.up", dir: "Long")
                Color.clear.frame(width: 30, height: 30)
            }
            HStack(spacing: 3) {
                dirButton("arrow.left", dir: "Left")
                hitCenterButton
                dirButton("arrow.right", dir: "Right")
            }
            HStack(spacing: 3) {
                Color.clear.frame(width: 30, height: 30)
                dirButton("arrow.down", dir: "Short")
                Color.clear.frame(width: 30, height: 30)
            }
        }
    }

    private func dirButton(_ icon: String, dir: String) -> some View {
        let sel = teeShotDir == dir
        return Button {
            withAnimation(.spring(response: 0.2)) { teeShotDir = dir }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(sel ? .white : TCTheme.textMuted)
                .frame(width: 30, height: 30)
                .background(sel ? AnyShapeStyle(TCTheme.goldGradient) : AnyShapeStyle(TCTheme.panelRaised))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(sel ? TCTheme.gold.opacity(0) : TCTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var hitCenterButton: some View {
        let sel = teeShotDir == "HIT"
        return Button {
            withAnimation(.spring(response: 0.2)) { teeShotDir = "HIT" }
        } label: {
            Text("HIT")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(sel ? .white : TCTheme.textMuted)
                .frame(width: 30, height: 30)
                .background(sel ? TCTheme.sage : TCTheme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(sel ? TCTheme.sage.opacity(0) : TCTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sub Stats Row (1st Putt | Club)

    private var subStatsRow: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(spacing: 6) {
                colLabel("1st Putt")
                HStack(spacing: 10) {
                    stepCircle("minus") { if firstPuttFeet > 0 { firstPuttFeet -= 1 } }
                    Text(firstPuttFeet == 0 ? "—" : "\(firstPuttFeet)ft")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(firstPuttFeet == 0 ? TCTheme.textUltraMuted : TCTheme.textPrimary)
                        .frame(minWidth: 42, alignment: .center)
                        .contentTransition(.numericText())
                    stepCircle("plus") { firstPuttFeet += 1 }
                }
            }
            .frame(maxWidth: .infinity)

            colDivider

            VStack(spacing: 4) {
                colLabel("Club")
                Button { cycleTeeClub(by: +1) } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TCTheme.textMuted)
                        .frame(width: 34, height: 26)
                }
                .buttonStyle(.plain)
                Text(teeClub ?? "—")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(teeClub == nil ? TCTheme.textUltraMuted : TCTheme.textPrimary)
                    .frame(minWidth: 42, alignment: .center)
                Button { cycleTeeClub(by: -1) } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TCTheme.textMuted)
                        .frame(width: 34, height: 26)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
    }

    // MARK: - Bunkers

    private var bunkersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Bunkers").padding(.top, 14)
            HStack(spacing: 8) {
                toggleChip("Fairway Bunker", icon: "sun.max.fill", isOn: $inFwBunker)
                toggleChip("Green Side", icon: "flag.fill", isOn: $inGreenSideBunker)
                Spacer()
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: - Penalties

    private var penaltiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Penalties").padding(.top, 14)
            HStack(spacing: 8) {
                toggleChip("Hazard", icon: "drop.fill", isOn: $hazard)
                toggleChip("Drop Shot", icon: "arrow.down.to.line", isOn: $dropShot)
                toggleChip("OB", icon: "xmark.circle.fill", isOn: $ob)
                toggleChip("On Hole", icon: "exclamationmark.circle.fill", isOn: $onThisHole)
            }
            .padding(.bottom, 14)
        }
    }

    private func toggleChip(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.2)) { isOn.wrappedValue.toggle() }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isOn.wrappedValue ? chipIconColor(label) : TCTheme.textMuted)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isOn.wrappedValue ? TCTheme.textPrimary : TCTheme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isOn.wrappedValue ? chipBg(label) : TCTheme.panelRaised)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                    .strokeBorder(isOn.wrappedValue ? chipBorder(label) : TCTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2), value: isOn.wrappedValue)
    }

    private func chipIconColor(_ label: String) -> Color {
        switch label {
        case "Hazard":        return Color(red: 0.3, green: 0.65, blue: 0.95)
        case "OB":            return TCTheme.danger
        case "Green Side":    return TCTheme.sage
        default:              return TCTheme.gold
        }
    }

    private func chipBg(_ label: String) -> Color {
        switch label {
        case "Hazard":        return Color(red: 0.15, green: 0.35, blue: 0.60).opacity(0.28)
        case "OB":            return TCTheme.danger.opacity(0.18)
        case "Green Side":    return TCTheme.sage.opacity(0.18)
        default:              return TCTheme.gold.opacity(0.15)
        }
    }

    private func chipBorder(_ label: String) -> Color {
        switch label {
        case "Hazard":        return Color(red: 0.3, green: 0.65, blue: 0.95).opacity(0.5)
        case "OB":            return TCTheme.danger.opacity(0.45)
        case "Green Side":    return TCTheme.sage.opacity(0.45)
        default:              return TCTheme.gold.opacity(0.45)
        }
    }

    // MARK: - Save Footer

    private var saveFooter: some View {
        HStack(spacing: 10) {
            Button("Cancel") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(TCTheme.textMuted)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(TCTheme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                        .strokeBorder(TCTheme.border, lineWidth: 1)
                )
            Button(action: saveAndDismiss) {
                Text("Save Score")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(TCTheme.deepGreen)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(TCTheme.goldGradient)
                    .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    private var rowDivider: some View {
        Rectangle().fill(TCTheme.border).frame(height: 1)
    }

    private var colDivider: some View {
        Rectangle().fill(TCTheme.border).frame(width: 1).padding(.vertical, 6)
    }

    private func colLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(TCTheme.textMuted)
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1)
                .fill(TCTheme.gold.opacity(0.7))
                .frame(width: 2, height: 11)
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.9)
                .foregroundColor(TCTheme.textMuted)
        }
    }

    private func stepCircle(_ iconName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(TCTheme.gold)
                .frame(width: 34, height: 34)
                .background(TCTheme.panelRaised)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(TCTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func cycleTeeClub(by delta: Int) {
        let clubs = ScoreEntryView.teeClubs
        if let current = teeClub, let idx = clubs.firstIndex(of: current) {
            teeClub = clubs[(idx + delta + clubs.count) % clubs.count]
        } else {
            teeClub = delta > 0 ? clubs.first : clubs.last
        }
    }

    private func saveAndDismiss() {
        let fw: Bool? = par >= 4 ? (teeShotDir == "HIT" && !inFwBunker && !hazard && !ob) : nil
        onSave(score, putts, fw, computedGIR)
        dismiss()
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n {
        case 11, 12, 13: suffix = "th"
        default:
            switch n % 10 {
            case 1:  suffix = "st"
            case 2:  suffix = "nd"
            case 3:  suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}
