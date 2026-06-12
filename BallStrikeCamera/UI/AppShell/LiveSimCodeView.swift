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

                // Step 2 — type in the code shown on the website
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
                        .background(BSTheme.background.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    liveSimService.isReadyToConnect
                                        ? BSTheme.electricCyan.opacity(0.55)
                                        : BSTheme.textMuted.opacity(0.18),
                                    lineWidth: 1
                                )
                        )
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
                title: liveSimService.isReadyToConnect ? "Hit Shot" : "Enter Code First",
                icon: "camera.fill",
                style: .gradient(BSTheme.rangeGradient),
                action: onStartCamera
            )
            .glowingAccent(BSTheme.electricCyan)
            .disabled(!liveSimService.isReadyToConnect)
            .opacity(liveSimService.isReadyToConnect ? 1.0 : 0.4)
        }
    }

    private var statusColor: Color {
        if liveSimService.lastBroadcastError != nil { return BSTheme.dangerRed }
        if liveSimService.isBroadcasting            { return BSTheme.gold }
        if liveSimService.shotsSent > 0             { return BSTheme.fairwayGreen }
        if liveSimService.isReadyToConnect          { return BSTheme.electricCyan }
        return BSTheme.textMuted
    }

    private var statusText: String {
        if let err = liveSimService.lastBroadcastError { return err }
        if liveSimService.isBroadcasting              { return "Broadcasting…" }
        if liveSimService.shotsSent > 0               { return "Connected — ready for next shot" }
        if liveSimService.isReadyToConnect            { return "Ready — tap Hit Shot to start" }
        return "Enter the code shown on your screen"
    }
}
