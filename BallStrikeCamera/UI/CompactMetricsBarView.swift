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
        .background(ShotResultView.panelBG)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ShotResultView.ink.opacity(0.10), lineWidth: 1)
        )
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
                .foregroundColor(ShotResultView.ink.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(ShotResultView.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ShotResultView.ink.opacity(0.55))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(ShotResultView.ink.opacity(0.12))
            .frame(width: 1, height: 30)
    }
}
