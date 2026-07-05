import SwiftUI

struct ExposureModePickerView: View {
    let selectedShutter: ShutterPreset
    let onShutterSelected: (ShutterPreset) -> Void

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
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.label)
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
