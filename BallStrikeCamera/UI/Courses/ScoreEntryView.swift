import SwiftUI

/// Compact white score-entry popup. Transparent-green buttons, dark-green
/// text/icons. Score/Putts seed from the predicted values; the tee club and
/// first-putt distance seed from the hole's NFC taps when available.
struct ScoreEntryView: View {
    @Environment(\.dismiss) private var dismiss

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
    @State private var teeClub: String?
    @State private var firstPuttFeet: Int
    // Tap counters (0…3, tap again at 3 to clear).
    @State private var fwBunker = 0
    @State private var greenBunker = 0
    @State private var hazard = 0
    @State private var dropShot = 0
    @State private var ob = 0

    private static let teeClubs = ["Dr", "3W", "5W", "Hyb", "4i", "5i", "6i", "7i", "8i", "9i", "PW", "GW"]

    // MARK: - Palette
    private let ink   = Color(red: 0.10, green: 0.36, blue: 0.20)               // dark green
    private let soft  = Color(red: 0.10, green: 0.36, blue: 0.20).opacity(0.12) // transparent green
    private let line  = Color.black.opacity(0.08)
    private let muted = Color(red: 0.46, green: 0.50, blue: 0.47)

    // MARK: - Init
    init(holeNumber: Int, par: Int,
         existingScore: Int? = nil, existingPutts: Int? = nil,
         holeYardage: Int? = nil, handicap: Int? = nil,
         prefillTeeClubName: String? = nil, prefillFirstPuttFeet: Int? = nil,
         onSave: @escaping (Int, Int?, Bool?, Bool?) -> Void) {
        self.holeNumber = holeNumber
        self.par = par
        self.existingScore = existingScore
        self.existingPutts = existingPutts
        self.holeYardage = holeYardage
        self.handicap = handicap
        self.onSave = onSave
        _score = State(initialValue: existingScore ?? par)
        _putts = State(initialValue: existingPutts ?? 2)
        _teeClub = State(initialValue: Self.abbrev(for: prefillTeeClubName))
        _firstPuttFeet = State(initialValue: prefillFirstPuttFeet ?? 0)
    }

    // MARK: - Computed
    private var computedGIR: Bool { (score - putts) <= (par - 2) }
    private var scoreDelta: Int { score - par }
    private var deltaText: String { scoreDelta == 0 ? "E" : (scoreDelta > 0 ? "+\(scoreDelta)" : "\(scoreDelta)") }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(line).frame(height: 1)

            VStack(spacing: 16) {
                mainRow
                sectionLine
                subRow
                sectionLine
                tagsRow
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .presentationDetents([.fraction(0.68)])
        .presentationDragIndicator(.visible)
    }

    private var sectionLine: some View { Rectangle().fill(line).frame(height: 1) }

    // MARK: - Header (big Hole · Par · to-par + Enter)
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hole \(holeNumber) · Par \(par)")
                    .font(.system(size: 22, weight: .bold)).foregroundColor(.black)
                HStack(spacing: 8) {
                    Text(deltaText).font(.system(size: 18, weight: .heavy)).foregroundColor(ink)
                    if computedGIR {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 12, weight: .bold))
                            Text("GIR").font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(ink)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(soft).clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Button(action: saveAndDismiss) {
                Text("Enter")
                    .font(.system(size: 17, weight: .bold)).foregroundColor(ink)
                    .padding(.horizontal, 22).padding(.vertical, 11)
                    .background(soft).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
    }

    // MARK: - Score | Putts | Tee Shot
    private var mainRow: some View {
        HStack(alignment: .top, spacing: 16) {
            stepperCol("Score", score, { if score > 1 { score -= 1 } }, { score += 1 })
            stepperCol("Putts", putts, { if putts > 0 { putts -= 1 } }, { putts += 1 })
            VStack(spacing: 8) {
                colLabel("Tee Shot")
                teeShotPad
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stepperCol(_ label: String, _ value: Int,
                            _ minus: @escaping () -> Void, _ plus: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            colLabel(label)
            roundBtn("plus", 40, action: plus)
            Text("\(value)")
                .font(.system(size: 40, weight: .bold, design: .rounded)).foregroundColor(.black)
                .contentTransition(.numericText()).frame(minWidth: 46)
            roundBtn("minus", 40, action: minus)
        }
        .frame(maxWidth: .infinity)
    }

    private var teeShotPad: some View {
        VStack(spacing: 4) {
            dirBtn("arrow.up", "Long")
            HStack(spacing: 4) {
                dirBtn("arrow.left", "Left")
                hitBtn
                dirBtn("arrow.right", "Right")
            }
            dirBtn("arrow.down", "Short")
        }
    }

    // MARK: - Tee Shot Club | 1st Putt Distance (swapped)
    private var subRow: some View {
        HStack(spacing: 16) {
            VStack(spacing: 10) {
                colLabel("Tee Shot Club")
                HStack(spacing: 12) {
                    roundBtn("chevron.down", 38) { cycleTeeClub(by: -1) }
                    Text(teeClub ?? "—")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(teeClub == nil ? muted : .black).frame(minWidth: 50)
                    roundBtn("chevron.up", 38) { cycleTeeClub(by: +1) }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                colLabel("1st Putt Distance")
                HStack(spacing: 6) {
                    TextField("0", value: $firstPuttFeet, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 66, height: 40)
                        .background(soft)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("ft").font(.system(size: 14, weight: .semibold)).foregroundColor(muted)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Bunkers | Penalties (counters)
    private var tagsRow: some View {
        HStack(alignment: .top, spacing: 18) {
            tagGroup("Bunkers") {
                tagChip("Fairway", "Bunker", "tornado", $fwBunker)
                tagChip("Green", "Side", "flag.fill", $greenBunker)
            }
            tagGroup("Penalties") {
                tagChip("Hazard", "/ Water", "drop.fill", $hazard)
                tagChip("Drop", "Shot", "arrow.down.to.line", $dropShot)
                tagChip("Out of", "Bounds", "xmark.octagon", $ob)
            }
        }
    }

    private func tagGroup<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 8) {
            colLabel(title)
            HStack(spacing: 12) { content() }
        }
        .frame(maxWidth: .infinity)
    }

    private func tagChip(_ l1: String, _ l2: String, _ icon: String, _ count: Binding<Int>) -> some View {
        let on = count.wrappedValue > 0
        return Button { count.wrappedValue = (count.wrappedValue + 1) % 4 } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(on ? ink : soft).frame(width: 48, height: 48)
                    Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                        .foregroundColor(on ? .white : ink)
                }
                .overlay(alignment: .topTrailing) {
                    if on {
                        Text("\(count.wrappedValue)")
                            .font(.system(size: 11, weight: .heavy)).foregroundColor(ink)
                            .frame(width: 19, height: 19)
                            .background(Color.white).clipShape(Circle())
                            .overlay(Circle().stroke(ink, lineWidth: 1.5))
                            .offset(x: 5, y: -5)
                    }
                }
                Text(l1).font(.system(size: 10, weight: .semibold)).foregroundColor(muted)
                Text(l2).font(.system(size: 10, weight: .semibold)).foregroundColor(muted)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2), value: count.wrappedValue)
    }

    // MARK: - Reusable
    private func colLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundColor(muted)
    }

    private func roundBtn(_ icon: String, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size * 0.42, weight: .bold)).foregroundColor(ink)
                .frame(width: size, height: size).background(soft).clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func dirBtn(_ icon: String, _ dir: String) -> some View {
        let sel = teeShotDir == dir
        return Button { teeShotDir = dir } label: {
            Image(systemName: icon).font(.system(size: 14, weight: .bold))
                .foregroundColor(sel ? .white : ink).frame(width: 40, height: 40)
                .background(sel ? AnyShapeStyle(ink) : AnyShapeStyle(soft))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var hitBtn: some View {
        let sel = teeShotDir == "HIT"
        return Button { teeShotDir = "HIT" } label: {
            Text("HIT").font(.system(size: 13, weight: .bold))
                .foregroundColor(sel ? .white : ink).frame(width: 44, height: 40)
                .background(sel ? AnyShapeStyle(ink) : AnyShapeStyle(soft))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions / helpers
    private func cycleTeeClub(by delta: Int) {
        let clubs = ScoreEntryView.teeClubs
        if let current = teeClub, let idx = clubs.firstIndex(of: current) {
            teeClub = clubs[(idx + delta + clubs.count) % clubs.count]
        } else {
            teeClub = delta > 0 ? clubs.first : clubs.last
        }
    }

    private func saveAndDismiss() {
        let fw: Bool? = par >= 4 ? (teeShotDir == "HIT" && fwBunker == 0 && hazard == 0 && ob == 0) : nil
        onSave(score, putts, fw, computedGIR)
        dismiss()
    }

    /// Maps a full club name (from an NFC tap) to the tee-club abbreviations.
    static func abbrev(for name: String?) -> String? {
        guard let n = name?.lowercased() else { return nil }
        if n.contains("driver") { return "Dr" }
        if n.contains("hybrid") { return "Hyb" }
        if n.contains("pitch")  { return "PW" }
        if n.contains("gap")    { return "GW" }
        if n.contains("sand") || n.contains("lob") { return "GW" }
        if n.contains("3") && n.contains("wood") { return "3W" }
        if n.contains("5") && n.contains("wood") { return "5W" }
        for d in 4...9 where n.contains("\(d) iron") || n.contains("\(d)i") { return "\(d)i" }
        if n.contains("wood") { return "3W" }
        return nil
    }
}
