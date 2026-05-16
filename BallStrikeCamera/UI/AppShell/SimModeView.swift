import SwiftUI

private struct SimProviderOption: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let icon: String
}

struct SimModeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProvider = "GSPro"

    private let providers: [SimProviderOption] = [
        SimProviderOption(name: "GSPro",          subtitle: "Most popular — full feature set",   icon: "display"),
        SimProviderOption(name: "OGS",            subtitle: "Official GSP OpenAPI protocol",     icon: "antenna.radiowaves.left.and.right"),
        SimProviderOption(name: "Local JSON",     subtitle: "Export shot data to JSON file",     icon: "doc.text"),
    ]

    private let jsonPreview = """
{
  "ballSpeedMph":       145.2,
  "launchAngleDeg":      13.1,
  "horizontalAngleDeg":  -2.4,
  "spinRatePrm":       3820.0,
  "carryYards":          252.0
}
"""

    var body: some View {
        NavigationStack {
            ZStack {
                BallStrikeBackgroundView()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: BSTheme.sectionGap) {
                        subheader
                        connectionCard
                        providerSection
                        lastShotSection
                        jsonPreviewSection
                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, BSTheme.hPad)
                    .padding(.top, 4)
                }
            }
            .navigationTitle("Simulator")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.clear, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(BSTheme.electricCyan)
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var subheader: some View {
        Text("Connect BallStrike to your simulator setup over WiFi.")
            .font(.system(size: 14))
            .foregroundColor(BSTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var connectionCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(BSTheme.dangerRed.opacity(0.16))
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(BSTheme.dangerRed)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Not Connected")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(BSTheme.textPrimary)
                Text("Open \(selectedProvider) on your PC and ensure you're on the same WiFi network.")
                    .font(.system(size: 12))
                    .foregroundColor(BSTheme.textMuted)
                    .lineLimit(2)
            }
            Spacer()
            Button {} label: {
                Text("Scan")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSTheme.electricCyan)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(BSTheme.electricCyan.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(BSTheme.electricCyan.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .premiumCard(padding: 16)
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Provider")
            VStack(spacing: 8) {
                ForEach(providers) { p in
                    Button { selectedProvider = p.name } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedProvider == p.name ? BSTheme.simBlue.opacity(0.25) : BSTheme.panel)
                                    .frame(width: 38, height: 38)
                                Image(systemName: p.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(selectedProvider == p.name ? BSTheme.electricCyan : BSTheme.textMuted)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(BSTheme.textPrimary)
                                Text(p.subtitle)
                                    .font(.system(size: 12))
                                    .foregroundColor(BSTheme.textMuted)
                            }
                            Spacer()
                            if selectedProvider == p.name {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(BSTheme.electricCyan)
                                    .font(.system(size: 18))
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedProvider == p.name ? BSTheme.panelRaised : BSTheme.panel)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(selectedProvider == p.name ? BSTheme.electricCyan.opacity(0.40) : BSTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var lastShotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Last Shot Sent")
            HStack(spacing: 10) {
                StatTile(label: "Ball Speed", value: "145", unit: "mph", accent: BSTheme.electricCyan)
                StatTile(label: "Carry",      value: "252", unit: "yd",  accent: BSTheme.fairwayGreen)
                StatTile(label: "Launch",     value: "13.1",unit: "°",   accent: BSTheme.gold)
            }
        }
    }

    private var jsonPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Shot JSON Preview")
            VStack(alignment: .leading, spacing: 0) {
                // Terminal title bar
                HStack(spacing: 6) {
                    ForEach([BSTheme.dangerRed, BSTheme.gold, BSTheme.fairwayGreen], id: \.self) { c in
                        Circle().fill(c).frame(width: 10, height: 10)
                    }
                    Spacer()
                    Text("shot_output.json")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(BSTheme.textMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.04))

                // Code
                Text(jsonPreview)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(BSTheme.electricCyan)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(red: 0.03, green: 0.05, blue: 0.09))
            .clipShape(RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BSTheme.cardRadius, style: .continuous)
                    .strokeBorder(BSTheme.border, lineWidth: 1)
            )
        }
    }
}
