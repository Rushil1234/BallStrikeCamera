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
    @State private var teeResult: String = "Fairway"
    @State private var fairwayHit: Bool?
    @State private var gir: Bool?
    @State private var mishit = false

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

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Top map area
                GeneratedFairwayView()
                    .frame(height: 220)
                    .ignoresSafeArea(edges: .top)
                    .overlay(
                        LinearGradient(
                            colors: [.clear, TCTheme.background.opacity(0.88)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Hole info overlay on map
                VStack(spacing: 6) {
                    holeSelectorPill
                    let yardStr = holeYardage.map { "\($0) yds  ·  " } ?? ""
                    let hcpStr  = handicap.map    { "HCP \($0)"       } ?? ""
                    let infoStr = yardStr + hcpStr
                    if !infoStr.isEmpty {
                        Text(infoStr)
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textMuted)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                    }
                }
                .padding(.top, 52)

                // Scrollable bottom sheet content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Drag handle
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(TCTheme.borderMedium)
                            .frame(width: 36, height: 4)
                            .padding(.top, 12)

                        // User row
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(TCTheme.panelRaised)
                                    .frame(width: 36, height: 36)
                                Circle()
                                    .strokeBorder(TCTheme.borderGold, lineWidth: 1.5)
                                    .frame(width: 36, height: 36)
                                Text(userInitials)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(TCTheme.gold)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(userName)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(TCTheme.textPrimary)
                                let diff = score - par
                                HStack(spacing: 0) {
                                    Text(scoreLabel(diff))
                                        .font(.system(size: 12))
                                        .foregroundColor(scoreLabelColor(diff))
                                    Text(diff == 0 ? " (E)" : diff > 0 ? " (+\(diff))" : " (\(diff))")
                                        .font(.system(size: 12))
                                        .foregroundColor(TCTheme.textMuted)
                                }
                            }

                            Spacer()

                            Button {
                                fairwayHit = teeResult == "Fairway"
                                onSave(score, putts, fairwayHit, gir)
                                dismiss()
                            } label: {
                                Text("Save Score")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(TCTheme.goldGradient)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        // Score stepper
                        VStack(spacing: 12) {
                            Text("SCORE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(TCTheme.gold)
                                .tracking(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 20) {
                                stepperButton(icon: "minus") { if score > 1 { score -= 1 } }
                                Text("\(score)")
                                    .font(.system(size: 44, weight: .black))
                                    .foregroundColor(TCTheme.textPrimary)
                                    .frame(minWidth: 60, alignment: .center)
                                stepperButton(icon: "plus") { score += 1 }
                            }
                            .frame(maxWidth: .infinity)

                            let diff = score - par
                            Text(scoreLabel(diff))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(scoreLabelColor(diff))
                        }
                        .tcCard()

                        // Putts stepper
                        VStack(spacing: 12) {
                            Text("PUTTS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(TCTheme.gold)
                                .tracking(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 20) {
                                stepperButton(icon: "minus") { if putts > 0 { putts -= 1 } }
                                Text("\(putts)")
                                    .font(.system(size: 44, weight: .black))
                                    .foregroundColor(TCTheme.cyan)
                                    .frame(minWidth: 60, alignment: .center)
                                stepperButton(icon: "plus") { putts += 1 }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .tcCard()

                        // Tee shot result
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TEE SHOT")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(TCTheme.gold)
                                .tracking(2)

                            let results = ["Left", "Short Left", "Fairway", "Short Right", "Right"]
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                                spacing: 8
                            ) {
                                ForEach(results, id: \.self) { r in
                                    Button { teeResult = r } label: {
                                        Text(r)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(teeResult == r ? .black : TCTheme.textMuted)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .frame(maxWidth: .infinity)
                                            .background(
                                                teeResult == r
                                                ? AnyShapeStyle(TCTheme.sageGradient)
                                                : AnyShapeStyle(TCTheme.panelRaised)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .tcCard()

                        // GIR
                        VStack(alignment: .leading, spacing: 12) {
                            Text("GREEN IN REGULATION")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(TCTheme.gold)
                                .tracking(2)

                            HStack(spacing: 10) {
                                girToggle("Yes",  selected: gir == true,  color: TCTheme.sage)   { gir = true  }
                                girToggle("No",   selected: gir == false, color: TCTheme.danger) { gir = false }
                                girToggle("N/A",  selected: gir == nil,   color: TCTheme.textMuted) { gir = nil }
                            }
                        }
                        .tcCard()

                        // Mishit toggle
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(TCTheme.gold)
                            Text("Did you mishit this shot?")
                                .font(.system(size: 13))
                                .foregroundColor(TCTheme.textSecondary)
                            Spacer()
                            Toggle("", isOn: $mishit)
                                .tint(TCTheme.gold)
                                .labelsHidden()
                        }
                        .tcCard()

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 190)
                }
            }
            .background(TCTheme.background.ignoresSafeArea())
            .navigationTitle("Hole \(holeNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(TCTheme.textMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        fairwayHit = teeResult == "Fairway"
                        onSave(score, putts, fairwayHit, gir)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(TCTheme.gold)
                }
            }
        }
    }

    // MARK: - Hole Selector Pill

    private var holeSelectorPill: some View {
        HStack(spacing: 10) {
            Text("← \(max(holeNumber - 1, 1))")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(TCTheme.textMuted)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.gold)
                Text(ordinal(holeNumber))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Text("Par \(par)")
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
            }

            Spacer()

            Text("\(holeNumber + 1) →")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(TCTheme.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.4))
        .background(TCTheme.panel.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(TCTheme.borderMedium, lineWidth: 1))
        .padding(.horizontal, 24)
        .shadow(color: .black.opacity(0.4), radius: 6)
    }

    // MARK: - Step Button

    private func stepperButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(TCTheme.textSecondary)
                .frame(width: 52, height: 52)
                .background(TCTheme.panelRaised)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(TCTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - GIR Toggle

    private func girToggle(_ label: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(selected ? .black : TCTheme.textMuted)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(selected ? color : TCTheme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(selected ? color : TCTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func scoreLabel(_ diff: Int) -> String {
        switch diff {
        case ..<(-1): return "Eagle"
        case -1:      return "Birdie"
        case 0:       return "Par"
        case 1:       return "Bogey"
        case 2:       return "Double"
        default:      return "+\(diff)"
        }
    }

    private func scoreLabelColor(_ diff: Int) -> Color {
        if diff < 0  { return TCTheme.sage }
        if diff == 0 { return TCTheme.cyan }
        return TCTheme.gold
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n {
        case 11, 12, 13: suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    private var userName: String {
        session.userProfile?.displayName ?? "Player"
    }

    private var userInitials: String {
        let name = userName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String((parts[0].first ?? "P")).uppercased()
                 + String((parts[1].first ?? "L")).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
