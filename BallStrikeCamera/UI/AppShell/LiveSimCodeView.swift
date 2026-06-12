import SwiftUI

struct LiveSimCodeView: View {
    @ObservedObject var liveSimService: LiveSimService
    let onStartCamera: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Live Sim")

            VStack(spacing: 16) {

                // Step 1 — open the website
                HStack(spacing: 14) {
                    Image(systemName: "display")
                        .font(.system(size: 22))
                        .foregroundColor(BSTheme.electricCyan)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Open on your screen")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(BSTheme.textPrimary)
                        Text("truecarry.vercel.app/play")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(BSTheme.gold)
                    }
                    Spacer()
                }

                Divider()
                    .background(BSTheme.textMuted.opacity(0.3))

                // Step 2 — type code from website
                VStack(alignment: .leading, spacing: 8) {
                    Text("ENTER CODE FROM SCREEN")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(BSTheme.textMuted)
                        .kerning(1.2)

                    TextField("_ _ _ _ _ _", text: $liveSimService.enteredCode)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(BSTheme.electricCyan)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(BSTheme.backgroundTop.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    liveSimService.isConnectedToSim
                                        ? BSTheme.fairwayGreen.opacity(0.7)
                                        : liveSimService.isReadyToConnect
                                            ? BSTheme.electricCyan.opacity(0.55)
                                            : BSTheme.textMuted.opacity(0.18),
                                    lineWidth: 1
                                )
                        )
                        .disabled(liveSimService.isConnectedToSim)
                }

                // Connect button (shown until connected)
                if !liveSimService.isConnectedToSim {
                    Button {
                        Task { await liveSimService.connect() }
                    } label: {
                        HStack(spacing: 8) {
                            if liveSimService.isBroadcasting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(BSTheme.electricCyan)
                            }
                            Text(liveSimService.isBroadcasting ? "Connecting…" : "Connect")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(liveSimService.isReadyToConnect ? BSTheme.electricCyan.opacity(0.15) : BSTheme.textMuted.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(liveSimService.isReadyToConnect ? BSTheme.electricCyan.opacity(0.5) : BSTheme.textMuted.opacity(0.2), lineWidth: 1)
                        )
                        .foregroundColor(liveSimService.isReadyToConnect ? BSTheme.electricCyan : BSTheme.textMuted)
                    }
                    .disabled(!liveSimService.isReadyToConnect || liveSimService.isBroadcasting)
                } else {
                    // Connected confirmation
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(BSTheme.fairwayGreen)
                        Text("Connected — website should show course selector")
                            .font(.system(size: 13))
                            .foregroundColor(BSTheme.fairwayGreen)
                        Spacer()
                    }
                }

                // Status row
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundColor(BSTheme.textMuted)
                    Spacer()
                    if liveSimService.shotsSent > 0 {
                        Text("\(liveSimService.shotsSent) shot\(liveSimService.shotsSent == 1 ? "" : "s") sent")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(BSTheme.fairwayGreen)
                    }
                }
            }
            .padding(16)
            .background(BSTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(BSTheme.electricCyan.opacity(0.25), lineWidth: 1)
            )

            PremiumActionButton(
                title: liveSimService.isConnectedToSim ? "Hit Shot" : "Connect First",
                icon: "camera.fill",
                style: .gradient(BSTheme.rangeGradient),
                action: onStartCamera
            )
            .glowingAccent(BSTheme.electricCyan)
            .disabled(!liveSimService.isConnectedToSim)
            .opacity(liveSimService.isConnectedToSim ? 1.0 : 0.4)
        }
    }

    private var statusColor: Color {
        if liveSimService.lastBroadcastError != nil { return BSTheme.dangerRed }
        if liveSimService.isBroadcasting            { return BSTheme.gold }
        if liveSimService.shotsSent > 0             { return BSTheme.fairwayGreen }
        if liveSimService.isConnectedToSim          { return BSTheme.fairwayGreen }
        if liveSimService.isReadyToConnect          { return BSTheme.electricCyan }
        return BSTheme.textMuted
    }

    private var statusText: String {
        if let err = liveSimService.lastBroadcastError { return err }
        if liveSimService.isBroadcasting              { return "Connecting…" }
        if liveSimService.shotsSent > 0               { return "Streaming — ready for next shot" }
        if liveSimService.isConnectedToSim            { return "Select a course on the website, then tap Hit Shot" }
        if liveSimService.isReadyToConnect            { return "Tap Connect to pair with the website" }
        return "Enter the code shown on your screen"
    }
}
