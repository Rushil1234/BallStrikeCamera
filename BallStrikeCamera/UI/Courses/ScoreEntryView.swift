import SwiftUI

/// Compact, non-scrolling score-entry popup. White card, transparent-green
/// buttons, dark-green text/icons. The initial score/putts come from the
/// predicted (smart) values passed in by the caller.
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

    // MARK: - Palette (white background, transparent-green buttons, dark-green text)

    private let ink   = Color(red: 0.10, green: 0.36, blue: 0.20)   // dark green — text/icons
    private let soft  = Color(red: 0.10, green: 0.36, blue: 0.20).opacity(0.12) // transparent green — button bg
    private let line  = Color.black.opacity(0.08)
    private let muted = Color(red: 0.46, green: 0.50, blue: 0.47)

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

    private var computedGIR: Bool { (score - putts) <= (par - 2) }
    private var scoreDelta: Int { score - par }
    private var deltaText: String { scoreDelta == 0 ? "E" : (scoreDelta > 0 ? "+\(scoreDelta)" : "\(scoreDelta)") }
    private var userName: String { session.userProfile?.displayName ?? "Player" }
    private var userInitials: String {
        let parts = userName.split(separator: " ")
        if parts.count >= 2 { return (parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(userName.prefix(2)).uppercased()
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(line).frame(height: 1)

            VStack(spacing: 14) {
                mainRow
                sectionLine
                subRow
                sectionLine
                tagsRow
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)   // white card + dark text even in dark mode
        .presentationDetents([.height(540)])
        .presentationDragIndicator(.visible)
    }

    private var sectionLine: some View { Rectangle().fill(line).frame(height: 1) }

    // MARK: - Header (player • to-par • Enter)

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(soft).frame(width: 38, height: 38)
                Text(userInitials).font(.system(size: 13, weight: .bold)).foregroundColor(ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(userName).font(.system(size: 15, weight: .semibold)).foregroundColor(.black)
                HStack(spacing: 6) {
                    Text("Hole \(holeNumber) · Par \(par)").font(.system(size: 12)).foregroundColor(muted)
                    Text(deltaText)
                        .font(.system(size: 11, weight: .bold)).foregroundColor(ink)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(soft).clipShape(Capsule())
                    if computedGIR {
                        Text("GIR").font(.system(size: 10, weight: .bold)).foregroundColor(ink)
                    }
                }
            }
            Spacer()
            Button(action: saveAndDismiss) {
                Text("Enter")
                    .font(.system(size: 15, weight: .bold)).foregroundColor(ink)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(soft).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    // MARK: - Main row: Score | Putts | Tee Shot

    private var mainRow: some View {
        HStack(alignment: .top, spacing: 14) {
            stepperCol(label: "Score", value: score, big: true,
                       minus: { if score > 1 { score -= 1 } }, plus: { score += 1 })
            stepperCol(label: "Putts", value: putts, big: true,
                       minus: { if putts > 0 { putts -= 1 } }, plus: { putts += 1 })
            VStack(spacing: 6) {
                colLabel("Tee Shot")
                teeShotPad
                misHitToggle
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stepperCol(label: String, value: Int, big: Bool,
                            minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            colLabel(label)
            roundBtn("plus", action: plus)
            Text("\(value)")
                .font(.system(size: big ? 30 : 20, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .contentTransition(.numericText())
                .frame(minWidth: 40)
            roundBtn("minus", action: minus)
        }
        .frame(maxWidth: .infinity)
    }

    private var teeShotPad: some View {
        VStack(spacing: 3) {
            dirBtn("arrow.up", "Long")
            HStack(spacing: 3) {
                dirBtn("arrow.left", "Left")
                hitBtn
                dirBtn("arrow.right", "Right")
            }
            dirBtn("arrow.down", "Short")
        }
    }

    private var misHitToggle: some View {
        Button { misHit.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: misHit ? "xmark.circle.fill" : "xmark.circle").font(.system(size: 10))
                Text("Mis-Hit").font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(misHit ? Color(red: 0.80, green: 0.25, blue: 0.25) : muted)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sub row: 1st Putt | Club

    private var subRow: some View {
        HStack(spacing: 14) {
            VStack(spacing: 8) {
                colLabel("1st Putt Distance")
                HStack(spacing: 10) {
                    roundBtn("minus") { if firstPuttFeet > 0 { firstPuttFeet -= 1 } }
                    Text(firstPuttFeet == 0 ? "—" : "\(firstPuttFeet)ft")
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(.black)
                        .frame(minWidth: 46).contentTransition(.numericText())
                    roundBtn("plus") { firstPuttFeet += 1 }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                colLabel("Tee Shot Club")
                HStack(spacing: 10) {
                    roundBtn("chevron.down") { cycleTeeClub(by: -1) }
                    Text(teeClub ?? "—")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(teeClub == nil ? muted : .black)
                        .frame(minWidth: 46)
                    roundBtn("chevron.up") { cycleTeeClub(by: +1) }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Tags: Bunkers | Penalties | Drinks

    private var tagsRow: some View {
        HStack(alignment: .top, spacing: 14) {
            tagGroup("Bunkers") {
                tagChip("Fairway", "Bunker", "tornado", $inFwBunker)
                tagChip("Green", "Side", "flag.fill", $inGreenSideBunker)
            }
            tagGroup("Penalties") {
                tagChip("Hazard", "/ Water", "drop.fill", $hazard)
                tagChip("Drop", "Shot", "arrow.down.to.line", $dropShot)
                tagChip("Out of", "Bounds", "xmark.octagon", $ob)
            }
            tagGroup("Drinks") {
                tagChip("On This", "Hole", "cup.and.saucer.fill", $onThisHole)
            }
        }
    }

    private func tagGroup<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 7) {
            colLabel(title)
            HStack(spacing: 8) { content() }
        }
    }

    private func tagChip(_ l1: String, _ l2: String, _ icon: String, _ on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(on.wrappedValue ? ink.opacity(0.22) : soft).frame(width: 34, height: 34)
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(ink)
                }
                Text(l1).font(.system(size: 8.5, weight: .semibold)).foregroundColor(muted)
                Text(l2).font(.system(size: 8.5, weight: .semibold)).foregroundColor(muted)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reusable buttons

    private func colLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundColor(muted)
    }

    private func roundBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundColor(ink)
                .frame(width: 32, height: 32).background(soft).clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func dirBtn(_ icon: String, _ dir: String) -> some View {
        let sel = teeShotDir == dir
        return Button { teeShotDir = dir } label: {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
                .foregroundColor(sel ? .white : ink)
                .frame(width: 30, height: 30)
                .background(sel ? AnyShapeStyle(ink) : AnyShapeStyle(soft))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var hitBtn: some View {
        let sel = teeShotDir == "HIT"
        return Button { teeShotDir = "HIT" } label: {
            Text("HIT").font(.system(size: 11, weight: .bold))
                .foregroundColor(sel ? .white : ink)
                .frame(width: 34, height: 30)
                .background(sel ? AnyShapeStyle(ink) : AnyShapeStyle(soft))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

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
}
