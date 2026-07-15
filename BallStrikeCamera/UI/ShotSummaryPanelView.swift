import SwiftUI

struct ShotSummaryPanelView: View {
    let metrics: ShotMetricsResult?
    let composite: PlatformImage?

    // In lefty this panel sits on the left; nudge its content inward so Carry/Total clear the corner.
    @AppStorage("tc_hitting_hand") private var hand = "R"
    private var isLefty: Bool { hand == "L" }

    init(metrics: ShotMetricsResult? = nil, composite: PlatformImage? = nil) {
        self.metrics = metrics
        self.composite = composite
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Carry (primary) and Total, same size and parallel — labels aligned on one row,
            // numbers aligned on the next.
            HStack(alignment: .top, spacing: 12) {
                metricColumn(label: "Carry", value: carryText,
                             valueColor: Color(red: 0.20, green: 0.48, blue: 0.20),
                             labelColor: Color(red: 0.20, green: 0.48, blue: 0.20).opacity(0.85))
                metricColumn(label: "Total", value: totalText,
                             valueColor: ShotResultView.ink,
                             labelColor: ShotResultView.ink.opacity(0.55))
            }

            // Lower area: composite of the last shot, fit to size (empty until the first shot).
            Group {
                if let composite {
                    Image(uiImage: composite)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .padding(.leading, isLefty ? 18 : 0)   // clear the screen corner in lefty
        .background(ShotResultView.panelBG)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ShotResultView.ink.opacity(0.10), lineWidth: 1)
        )
    }

    private var totalText: String {
        if let yd = metrics?.distance.totalYards { return String(format: "%.0f", yd) }
        return "--"
    }

    private var carryText: String {
        if let yd = metrics?.distance.carryYards { return String(format: "%.0f", yd) }
        return "--"
    }

    private func metricColumn(label: String, value: String, valueColor: Color, labelColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(labelColor)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundColor(valueColor)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text("yd")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ShotResultView.ink.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
