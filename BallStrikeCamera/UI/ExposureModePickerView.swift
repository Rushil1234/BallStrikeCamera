import SwiftUI

struct ExposureModePickerView: View {
    let selectedShutter: ShutterPreset
    let onShutterSelected: (ShutterPreset) -> Void
    /// Live lighting fit per preset (from the sensor's own metering) + the fastest clean
    /// choice. A red badge means this light can't support that shutter (grain or streaks);
    /// the dot ring marks the recommendation. Buttons behave exactly as before.
    var fitness: [ShutterPreset: ShutterFitness] = [:]
    var recommended: ShutterPreset? = nil

    private func badgeColor(_ preset: ShutterPreset) -> Color? {
        switch fitness[preset] {
        case .good:      return Color(red: 0.30, green: 0.85, blue: 0.45)
        case .grainy:    return Color(red: 0.95, green: 0.78, blue: 0.25)
        case .tooDark, .tooBright:
                         return Color(red: 0.95, green: 0.35, blue: 0.30)
        case nil:        return nil
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ShutterPreset.allCases) { preset in
                Button {
                    onShutterSelected(preset)
                } label: {
                    Image(systemName: preset.symbol)
                        .font(.system(size: preset.iconSize, weight: .bold))
                        .foregroundColor(selectedShutter == preset ? .white : LaunchMonitorTheme.textSecondary)
                        .frame(width: 42, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: selectedShutter == preset
                                            ? [LaunchMonitorTheme.accentSky, LaunchMonitorTheme.accentFairway]
                                            : [LaunchMonitorTheme.panelRaisedTop, LaunchMonitorTheme.panelRaisedBottom],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(selectedShutter == preset ? Color.white.opacity(0.22) : LaunchMonitorTheme.outline, lineWidth: 1)
                        )
                        .overlay(alignment: .topTrailing) {
                            if let color = badgeColor(preset) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 7, height: 7)
                                    .overlay(
                                        Circle().stroke(
                                            recommended == preset ? Color.white : Color.black.opacity(0.5),
                                            lineWidth: recommended == preset ? 1.5 : 1
                                        )
                                    )
                                    .padding(4)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.label + (recommended == preset ? ", recommended" : ""))
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LaunchMonitorTheme.outline, lineWidth: 1)
        )
    }
}
