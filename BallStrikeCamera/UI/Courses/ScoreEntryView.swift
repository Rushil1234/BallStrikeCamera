import SwiftUI
import CoreLocation

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
    @FocusState private var puttFocused: Bool

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
        let s0 = existingScore ?? par
        _score = State(initialValue: s0)
        _putts = State(initialValue: min(existingPutts ?? 2, max(0, s0 - 1)))
        _teeClub = State(initialValue: Self.abbrev(for: prefillTeeClubName))
        _firstPuttFeet = State(initialValue: prefillFirstPuttFeet ?? 0)
    }

    // MARK: - Computed
    /// You always need at least one non-putt to reach the green, so putts < score.
    private var maxPutts: Int { max(0, score - 1) }
    private func clampPutts() { if putts > maxPutts { putts = maxPutts } }

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
            stepperCol("Score", score,
                       { if score > 1 { score -= 1 }; clampPutts() },
                       { score += 1 })
            stepperCol("Putts", putts,
                       { if putts > 0 { putts -= 1 } },
                       { if putts < maxPutts { putts += 1 } })
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
                        .focused($puttFocused)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { puttFocused = false }
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(ink)
                            }
                        }
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


// MARK: - Hole shots editor (fix the accidental double-tap before OR after submitting)

struct HoleShotsEditSheet: View {
    let holeNumber: Int
    let par: Int
    let score: Int?
    let shots: [TrackedShot]
    /// Bag for the club-change menu; empty hides club editing.
    var clubs: [UserClub] = []
    /// Hole geometry hints. Tee enables "add the forgotten tee shot"; green anchors the
    /// after-last-shot slot and the to-green yardages. Nil hides those pieces.
    var teeCoordinate: Coordinate? = nil
    var greenCoordinate: Coordinate? = nil
    let onDelete: (UUID) -> Void
    var onChangeClub: ((UUID, ShotClub?) -> Void)? = nil
    /// (club, afterIndex, start, end) — insert a forgotten shot. afterIndex 0 = before shot 1.
    var onAddShot: ((ShotClub?, Int, Coordinate, Coordinate?) -> Void)? = nil
    /// Snapshot-harness only: open the add-missed-shot form immediately.
    var startWithAddForm: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var showAddForm  = false
    @State private var addSlotIndex = 0
    @State private var addClubId: UUID?
    @State private var addFraction: Double = 0.5

    var body: some View {
        NavigationStack {
            ZStack {
                TrueCarryBackground().ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(captionText)
                            .font(.system(size: 12))
                            .foregroundColor(TCTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(shots) { shot in
                            shotRow(shot)
                        }
                        if shots.isEmpty {
                            Text("No logged shots on this hole.")
                                .font(.system(size: 13))
                                .foregroundColor(TCTheme.textUltraMuted)
                        }
                        if onAddShot != nil && !addSlots.isEmpty {
                            addShotSection
                        }
                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Hole \(holeNumber) Shots\(score.map { " · \($0)" } ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(TCTheme.sage)
                }
            }
            .onAppear {
                if startWithAddForm, !addSlots.isEmpty {
                    addSlotIndex = addSlots.first?.afterIndex ?? 0
                    addFraction  = addSlotIndex == 0 ? 0.05 : 0.5
                    showAddForm  = true
                }
            }
        }
    }

    private var captionText: String {
        var parts = ["Deleting a shot renumbers the rest and takes one stroke off the hole — totals update everywhere."]
        if onChangeClub != nil, !clubs.isEmpty {
            parts.append("Tap a club name to change it.")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Rows

    private func shotRow(_ shot: TrackedShot) -> some View {
        HStack(spacing: 12) {
            Text("\(shot.shotIndex)")
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundColor(TCTheme.gold)
                .frame(width: 26, height: 26)
                .background(Circle().fill(TCTheme.gold.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                if let onChangeClub, !clubs.isEmpty {
                    Menu {
                        ForEach(clubs) { c in
                            Button(c.name) { onChangeClub(shot.id, ShotClub(userClub: c)) }
                        }
                        Button("No club") { onChangeClub(shot.id, nil) }
                    } label: {
                        HStack(spacing: 5) {
                            Text(shot.club?.name ?? "Pick club")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(TCTheme.textPrimary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(TCTheme.sage)
                        }
                    }
                } else {
                    Text(shot.club?.name ?? "Shot")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                }
                // Putts never show a yardage — distances are to the green CENTER, and the
                // pin moves daily; a "20 yd putt" may have been a tap-in. The putt's dot
                // still matters: it marks where the shot before it finished.
                Text(shot.club?.category == .putter
                     ? "\(shot.lie.displayName) · putt"
                     : "\(shot.lie.displayName)\(shot.distanceYards > 0 ? " · \(Int(shot.distanceYards)) yd" : "")")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
            }
            Spacer()
            Button {
                onDelete(shot.id)
                if shots.count <= 1 { dismiss() }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TCTheme.danger)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(TCTheme.danger.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(TCTheme.border, lineWidth: 1))
    }

    // MARK: Add a missed shot

    /// A place the forgotten shot can slot into. The span (`from`→`to`) is where its origin
    /// can sit: before shot 1 it's tee→shot 1; between shots it's along the recorded segment
    /// the forgotten shot split in two; after the last it's last landing→green.
    private struct AddSlot: Identifiable {
        let afterIndex: Int
        let label: String
        let from: Coordinate
        let to: Coordinate
        var id: Int { afterIndex }
    }

    private var addSlots: [AddSlot] {
        var slots: [AddSlot] = []
        if let tee = teeCoordinate,
           let to = shots.first?.startCoordinate ?? greenCoordinate {
            slots.append(AddSlot(afterIndex: 0,
                                 label: shots.isEmpty ? "Tee shot" : "Before shot 1 — off the tee",
                                 from: tee, to: to))
        }
        if shots.count >= 2 {
            for i in 1..<shots.count {
                slots.append(AddSlot(afterIndex: i,
                                     label: "Between shot \(i) and \(i + 1)",
                                     from: shots[i - 1].startCoordinate,
                                     to:   shots[i - 1].endCoordinate))
            }
        }
        if let last = shots.last {
            slots.append(AddSlot(afterIndex: shots.count,
                                 label: "After shot \(shots.count)",
                                 from: last.endCoordinate,
                                 to:   greenCoordinate ?? last.endCoordinate))
        }
        return slots
    }

    private var currentSlot: AddSlot? {
        addSlots.first { $0.afterIndex == addSlotIndex } ?? addSlots.first
    }

    private var addShotSection: some View {
        Group {
            if showAddForm {
                addForm
            } else {
                Button {
                    addSlotIndex = addSlots.first?.afterIndex ?? 0
                    addFraction  = addSlotIndex == 0 ? 0.05 : 0.5
                    showAddForm  = true
                } label: {
                    Label("Add a missed shot", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(TCTheme.sage)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(TCTheme.sage.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(TCTheme.sage.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var addForm: some View {
        if let slot = currentSlot {
            let span = yards(slot.from, slot.to)
            let point = lerp(slot.from, slot.to, span > 3 ? addFraction : 0)
            VStack(alignment: .leading, spacing: 12) {
                Text("ADD A MISSED SHOT")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(TCTheme.textMuted)
                    .kerning(1.1)

                Menu {
                    ForEach(addSlots) { s in
                        Button(s.label) {
                            addSlotIndex = s.afterIndex
                            addFraction  = s.afterIndex == 0 ? 0.05 : 0.5
                        }
                    }
                } label: {
                    formRow(title: "Where", value: slot.label)
                }
                Menu {
                    ForEach(clubs) { c in
                        Button(c.name) { addClubId = c.id }
                    }
                    Button("No club") { addClubId = nil }
                } label: {
                    formRow(title: "Club", value: clubs.first { $0.id == addClubId }?.name ?? "None")
                }

                if span > 3 {
                    VStack(alignment: .leading, spacing: 4) {
                        Slider(value: $addFraction, in: 0...1)
                            .tint(TCTheme.sage)
                        HStack {
                            Text("\(Int(yards(slot.from, point))) yd past the spot before")
                            Spacer()
                            if let g = greenCoordinate {
                                Text("\(Int(yards(point, g))) yd to green")
                            }
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(TCTheme.textMuted)
                    }
                }

                HStack {
                    Button("Cancel") { showAddForm = false }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TCTheme.textMuted)
                    Spacer()
                    Button {
                        let end: Coordinate? = slot.afterIndex >= shots.count ? greenCoordinate : nil
                        let club = clubs.first { $0.id == addClubId }.map { ShotClub(userClub: $0) }
                        onAddShot?(club, slot.afterIndex, point, end)
                        showAddForm = false
                    } label: {
                        Text("Add Shot")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(TCTheme.sage))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(TCTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(TCTheme.sage.opacity(0.35), lineWidth: 1))
        }
    }

    private func formRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TCTheme.textMuted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(TCTheme.sage)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: Geo helpers

    private func yards(_ a: Coordinate, _ b: Coordinate) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) * 1.09361
    }

    private func lerp(_ a: Coordinate, _ b: Coordinate, _ t: Double) -> Coordinate {
        Coordinate(latitude:  a.latitude  + (b.latitude  - a.latitude)  * t,
                   longitude: a.longitude + (b.longitude - a.longitude) * t)
    }
}
