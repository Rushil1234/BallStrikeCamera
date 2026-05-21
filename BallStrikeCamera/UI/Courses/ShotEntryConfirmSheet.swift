import SwiftUI
import CoreLocation

/// Modal that confirms a placed shot: pick a club, show measured distance, set result.
/// Called after the user taps to place a shot endpoint on the map.
struct ShotEntryConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss

    let startCoord: Coordinate
    let endCoord:   Coordinate
    let preselectedLie: ShotLie
    let preselectedClub: ShotClub?

    let onSave:   (ShotClub?, ShotLie, ShotResult) -> Void
    let onCancel: () -> Void

    @State private var club: ShotClub?
    @State private var lie: ShotLie
    @State private var result: ShotResult = .inPlay

    init(startCoord: Coordinate,
         endCoord: Coordinate,
         preselectedLie: ShotLie,
         preselectedClub: ShotClub? = nil,
         onSave: @escaping (ShotClub?, ShotLie, ShotResult) -> Void,
         onCancel: @escaping () -> Void) {
        self.startCoord = startCoord
        self.endCoord = endCoord
        self.preselectedLie = preselectedLie
        self.preselectedClub = preselectedClub
        self.onSave = onSave
        self.onCancel = onCancel
        _lie = State(initialValue: preselectedLie)
        _club = State(initialValue: preselectedClub)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TCTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        distancePill
                        sectionHeader("CLUB")
                        clubGrid
                        sectionHeader("LIE")
                        lieGrid
                        sectionHeader("RESULT")
                        resultGrid
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, TCTheme.hPad)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Track Shot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel(); dismiss() }
                        .foregroundColor(TCTheme.textMuted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { onSave(club, lie, result); dismiss() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(TCTheme.gold)
                }
            }
        }
    }

    // MARK: - Pieces

    private var measuredYards: Int {
        let a = CLLocation(latitude: startCoord.latitude,  longitude: startCoord.longitude)
        let b = CLLocation(latitude: endCoord.latitude,    longitude: endCoord.longitude)
        return Int((a.distance(from: b) * 1.09361).rounded())
    }

    private var distancePill: some View {
        HStack(spacing: 14) {
            Image(systemName: "ruler")
                .foregroundColor(TCTheme.gold)
            Text("\(measuredYards) yd")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(TCTheme.textPrimary)
            Spacer()
            Text("Measured")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(TCTheme.textMuted)
                .tracking(1.0)
        }
        .tcCard(padding: 14)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(TCTheme.gold)
            .tracking(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var clubGrid: some View {
        let cats = ShotClub.ClubCategory.allCases
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
            ForEach(cats, id: \.self) { c in
                Button {
                    club = ShotClub(clubId: nil, name: c.displayName, category: c)
                } label: {
                    Text(c.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(club?.category == c ? .black : TCTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(club?.category == c ? AnyShapeStyle(TCTheme.sageGradient)
                                                       : AnyShapeStyle(TCTheme.panelRaised))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var lieGrid: some View {
        let lies: [ShotLie] = [.tee, .fairway, .rough, .sand, .recovery, .green]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
            ForEach(lies, id: \.self) { l in
                Button { lie = l } label: {
                    Text(l.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(lie == l ? .black : TCTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(lie == l ? TCTheme.cyan : TCTheme.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var resultGrid: some View {
        let results: [ShotResult] = [.inPlay, .fairwayHit, .missedLeft, .missedRight,
                                     .short, .long, .greenInReg, .penalty, .mishit, .holed]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
            ForEach(results, id: \.self) { r in
                Button { result = r } label: {
                    Text(r.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(result == r ? .black : TCTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(result == r ? TCTheme.gold : TCTheme.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
