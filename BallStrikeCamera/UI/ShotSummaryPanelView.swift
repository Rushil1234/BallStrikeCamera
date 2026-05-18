import SwiftUI

struct ShotSummaryPanelView: View {
    let metrics: ShotMetricsResult?

    init(metrics: ShotMetricsResult? = nil) {
        self.metrics = metrics
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Total")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.green.opacity(0.8))
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(totalText)
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundColor(Color.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text("yd")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer(minLength: 8)

            HStack(spacing: 0) {
                summaryMetric(label: "Carry", value: carryText, unit: "yd")
                    .frame(maxWidth: .infinity, alignment: .leading)

                summaryMetric(label: "VLA", value: vlaText, unit: "°")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var totalText: String {
        if let yd = metrics?.distance.totalYards { return String(format: "%.0f", yd) }
        return "--"
    }

    private var carryText: String {
        if let yd = metrics?.distance.carryYards { return String(format: "%.0f", yd) }
        return "--"
    }

    private var vlaText: String {
        if let v = metrics?.ballLaunch.vlaDegrees { return String(format: "%.1f", v) }
        return "--"
    }

    private func summaryMetric(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(unit)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }
}
