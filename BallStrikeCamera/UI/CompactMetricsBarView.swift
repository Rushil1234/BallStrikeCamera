import SwiftUI

struct CompactMetricsBarView: View {
    let metrics: ShotMetricsResult?

    init(metrics: ShotMetricsResult? = nil) {
        self.metrics = metrics
    }

    var body: some View {
        HStack(spacing: 0) {
            compactMetric(label: "Launch Angle", value: vlaText, unit: "°")
            divider
            compactMetric(label: "Direction", value: metrics?.ballLaunch.hlaDisplay ?? "--", unit: "")
            divider
            compactMetric(label: "Ball Speed", value: ballSpeedText, unit: "mph")
            divider
            compactMetric(label: "Club Speed", value: clubSpeedText, unit: "mph")
            divider
            compactMetric(label: "Smash", value: smashText, unit: "")
        }
        .padding(.vertical, 8)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var vlaText: String {
        if let v = metrics?.ballLaunch.vlaDegrees { return String(format: "%.1f", v) }
        return "--"
    }

    private var ballSpeedText: String {
        if let v = metrics?.ballLaunch.ballSpeedMph { return String(format: "%.0f", v) }
        return "--"
    }

    private var clubSpeedText: String {
        if let v = metrics?.club.clubSpeedMph { return String(format: "%.0f", v) }
        return "--"
    }

    private var smashText: String {
        if let v = metrics?.smashFactor { return String(format: "%.2f", v) }
        return "--"
    }

    private func compactMetric(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 30)
    }
}
