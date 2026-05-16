import SwiftUI

struct HoleView: View {
    let hole: RoundHole
    let golfHole: GolfHole?
    let teeBox: TeeBox?
    let location: LocationService
    let onScoreSet: (Int, Int?, Bool?, Bool?) -> Void

    @State private var score: Int
    @State private var putts: Int = 2
    @State private var fairwayHit: Bool? = nil
    @State private var gir: Bool? = nil
    @State private var hasScored: Bool

    init(hole: RoundHole, golfHole: GolfHole?, teeBox: TeeBox?,
         location: LocationService,
         onScoreSet: @escaping (Int, Int?, Bool?, Bool?) -> Void) {
        self.hole = hole
        self.golfHole = golfHole
        self.teeBox = teeBox
        self.location = location
        self.onScoreSet = onScoreSet
        _score = State(initialValue: hole.score ?? hole.par)
        _hasScored = State(initialValue: hole.score != nil)
    }

    var body: some View {
        VStack(spacing: 16) {
            holeHeader
            if hole.par > 3 { fairwaySection }
            girSection
            scoreSection
            puttsSection
            saveButton
        }
        .premiumCard()
    }

    // MARK: - Sub-views

    private var holeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hole \(hole.holeNumber)")
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(BSTheme.textPrimary)
                HStack(spacing: 10) {
                    Text("Par \(hole.par)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(BSTheme.fairwayGreen)
                    if let yards = yardage {
                        Text("\(yards) yd")
                            .font(.system(size: 14))
                            .foregroundColor(BSTheme.textMuted)
                    }
                    if let hcp = golfHole?.handicap {
                        Text("Hcp \(hcp)")
                            .font(.system(size: 14))
                            .foregroundColor(BSTheme.textMuted)
                    }
                }
            }
            Spacer()
            distanceWidget
        }
    }

    @ViewBuilder
    private var distanceWidget: some View {
        if let loc = location.currentLocation, let gh = golfHole, let mid = gh.greenCenterCoordinate {
            let dist = LocationService.distanceInYards(
                from: loc,
                to: .init(latitude: mid.latitude, longitude: mid.longitude)
            )
            VStack(spacing: 2) {
                Text("\(Int(dist.rounded()))")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(BSTheme.electricCyan)
                Text("yd to pin")
                    .font(.system(size: 11))
                    .foregroundColor(BSTheme.textMuted)
            }
        }
    }

    private var fairwaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fairway Hit")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSTheme.textMuted)
            HStack(spacing: 10) {
                toggleChip("Yes",   value: true,  binding: $fairwayHit, color: BSTheme.fairwayGreen)
                toggleChip("No",    value: false, binding: $fairwayHit, color: BSTheme.dangerRed)
                toggleChip("N/A",   value: nil,   binding: $fairwayHit, color: BSTheme.textMuted)
            }
        }
    }

    private var girSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Green in Regulation")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSTheme.textMuted)
            HStack(spacing: 10) {
                toggleChip("Yes",  value: true,  binding: $gir, color: BSTheme.fairwayGreen)
                toggleChip("No",   value: false, binding: $gir, color: BSTheme.dangerRed)
                toggleChip("N/A",  value: nil,   binding: $gir, color: BSTheme.textMuted)
            }
        }
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Score")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSTheme.textMuted)
            HStack(spacing: 8) {
                ForEach(scoreRange, id: \.self) { s in
                    Button { score = s } label: {
                        VStack(spacing: 2) {
                            Text("\(s)")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(score == s ? .black : BSTheme.textPrimary)
                            Text(scoreName(s))
                                .font(.system(size: 9))
                                .foregroundColor(score == s ? .black.opacity(0.6) : BSTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(score == s ? scoreColor(s) : BSTheme.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var puttsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Putts")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSTheme.textMuted)
            HStack(spacing: 10) {
                ForEach(0...4, id: \.self) { p in
                    Button { putts = p } label: {
                        Text("\(p)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(putts == p ? .black : BSTheme.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(putts == p ? BSTheme.electricCyan : BSTheme.panel)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var saveButton: some View {
        PremiumActionButton(
            title: hasScored ? "Update Score" : "Save Score",
            icon: "checkmark.circle.fill",
            style: .gradient(BSTheme.courseGradient),
            action: {
                hasScored = true
                onScoreSet(score, putts, fairwayHit, gir)
            }
        )
    }

    // MARK: - Helpers

    private var yardage: Int? {
        guard let gh = golfHole, let tee = teeBox else { return nil }
        return gh.teeYardsByTeeBox[tee.id]
    }

    private var scoreRange: [Int] {
        let base = hole.par
        return Array(max(1, base - 2)...(base + 4))
    }

    private func scoreName(_ s: Int) -> String {
        let diff = s - hole.par
        switch diff {
        case ..<(-1): return "Eagle+"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "D-Bogey"
        default: return "+\(diff)"
        }
    }

    private func scoreColor(_ s: Int) -> Color {
        let diff = s - hole.par
        if diff < 0  { return BSTheme.fairwayGreen }
        if diff == 0 { return BSTheme.electricCyan }
        if diff == 1 { return BSTheme.gold }
        return BSTheme.dangerRed
    }

    private func toggleChip(_ label: String, value: Bool?, binding: Binding<Bool?>, color: Color) -> some View {
        Button {
            binding.wrappedValue = value
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(binding.wrappedValue == value ? .black : BSTheme.textMuted)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(binding.wrappedValue == value ? color : BSTheme.panel)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
