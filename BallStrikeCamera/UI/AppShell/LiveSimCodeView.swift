import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct LiveSimCodeView: View {
    @ObservedObject var liveSimService: LiveSimService
    let onStartCamera: () -> Void

    @State private var pulse = false
    @State private var shotFlash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BSectionHeader(title: "Live Sim")

            if liveSimService.isConnectedToSim {
                connectedCard
            } else {
                setupCard
            }

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

    // MARK: - Connected (the "really cool" live link)

    private var connectedCard: some View {
        VStack(spacing: 16) {
            // Animated broadcast: concentric rings pulsing out of a signal icon.
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(BSTheme.fairwayGreen.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 72, height: 72)
                        .scaleEffect(pulse ? 2.0 : 0.85)
                        .opacity(pulse ? 0 : 0.7)
                        .animation(
                            .easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(Double(i) * 0.7),
                            value: pulse
                        )
                }
                Circle().fill(BSTheme.fairwayGreen.opacity(0.16)).frame(width: 72, height: 72)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(BSTheme.fairwayGreen)
            }
            .frame(height: 86)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(BSTheme.fairwayGreen).frame(width: 7, height: 7)
                        .opacity(pulse ? 1 : 0.3)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                    Text("LIVE")
                        .font(.system(size: 11, weight: .heavy)).kerning(2.5)
                        .foregroundColor(BSTheme.fairwayGreen)
                }
                Text("Connected to True Carry Sim")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(BSTheme.textPrimary)
                Text("Pick a course on your screen, then tap Hit Shot — every shot streams over instantly.")
                    .font(.system(size: 13))
                    .foregroundColor(BSTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // app ))) sim link visualisation
            HStack(spacing: 14) {
                linkNode(icon: "iphone", label: "App")
                Image(systemName: "wifi")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(BSTheme.fairwayGreen)
                    .opacity(pulse ? 1 : 0.35)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                linkNode(icon: "display", label: "Sim")
            }
            .padding(.top, 2)

            // Mirror of the sim: which hole you're on, distance, score, last result.
            if let s = liveSimService.liveState {
                VStack(spacing: 8) {
                    HStack {
                        Text("ON THE SIM")
                            .font(.system(size: 10, weight: .bold)).kerning(1.5)
                            .foregroundColor(BSTheme.textMuted)
                        Spacer()
                        if let tp = s.toPar {
                            Text(tp == 0 ? "E" : (tp > 0 ? "+\(tp)" : "\(tp)"))
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundColor(BSTheme.gold)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let h = s.hole {
                            Text("Hole \(h)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(BSTheme.textPrimary)
                        }
                        if let p = s.par {
                            Text("Par \(p)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(BSTheme.textMuted)
                        }
                        Spacer()
                        if let d = s.distanceToPinYards {
                            (Text("\(d)").font(.system(size: 16, weight: .bold))
                                + Text("y to pin").font(.system(size: 11)))
                                .foregroundColor(BSTheme.fairwayGreen)
                        }
                    }
                    if let ls = s.lastShot, ls.result != nil || (ls.totalYards ?? 0) > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "scope").font(.system(size: 10, weight: .bold))
                            if let r = ls.result {
                                Text(r.uppercased())
                            } else if let t = ls.totalYards {
                                Text("\(Int(t))y → \((ls.lie ?? "").uppercased())")
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(BSTheme.gold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(BSTheme.backgroundTop.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(BSTheme.gold.opacity(0.25), lineWidth: 1)
                )
            }

            // Live shot telemetry — flashes as each shot streams to the sim.
            if let shot = liveSimService.lastShot {
                VStack(spacing: 10) {
                    HStack {
                        Text("LAST SHOT")
                            .font(.system(size: 10, weight: .bold)).kerning(1.5)
                            .foregroundColor(BSTheme.textMuted)
                        Spacer()
                        Text("just now")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(BSTheme.fairwayGreen)
                            .opacity(shotFlash ? 1 : 0.5)
                    }
                    HStack(spacing: 0) {
                        telemetryStat("\(Int(shot.ballSpeedMph))", "mph", "BALL")
                        telemetryDivider
                        telemetryStat("\(Int(shot.carryYards))", "yd", "CARRY")
                        telemetryDivider
                        telemetryStat("\(Int(shot.totalYards))", "yd", "TOTAL")
                    }
                }
                .padding(12)
                .background(BSTheme.backgroundTop.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(BSTheme.fairwayGreen.opacity(shotFlash ? 0.8 : 0.25),
                                      lineWidth: shotFlash ? 2 : 1)
                )
                .scaleEffect(shotFlash ? 1.015 : 1)
            }

            // session bests + code + change
            HStack(spacing: 8) {
                chip(icon: "number", text: liveSimService.enteredCode, accent: BSTheme.gold)
                if liveSimService.shotsSent > 0 {
                    chip(icon: "scope", text: "\(liveSimService.shotsSent) sent", accent: BSTheme.fairwayGreen)
                }
                if liveSimService.bestCarryYards > 0 {
                    chip(icon: "trophy.fill", text: "\(Int(liveSimService.bestCarryYards))y best", accent: BSTheme.gold)
                }
                Spacer(minLength: 0)
                Button { liveSimService.disconnect() } label: {
                    Text("Change code")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BSTheme.textMuted)
                }
            }
        }
        // Flash + haptic each time a new shot streams to the sim.
        .onChange(of: liveSimService.shotsSent) { _ in
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { shotFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(.easeOut(duration: 0.5)) { shotFlash = false }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(BSTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(BSTheme.fairwayGreen.opacity(0.45), lineWidth: 1.2)
        )
        .shadow(color: BSTheme.fairwayGreen.opacity(0.14), radius: 16, y: 6)
        .onAppear { pulse = true }
    }

    private func linkNode(icon: String, label: String) -> some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(BSTheme.backgroundTop.opacity(0.6))
                    .frame(width: 46, height: 46)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(BSTheme.fairwayGreen.opacity(0.35), lineWidth: 1)
                    )
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(BSTheme.textPrimary)
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(BSTheme.textMuted)
        }
    }

    private func chip(icon: String, text: String, accent: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(accent)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(accent.opacity(0.12))
        .clipShape(Capsule())
    }

    private func telemetryStat(_ value: String, _ unit: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(BSTheme.textPrimary)
                Text(unit)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BSTheme.textMuted)
            }
            Text(label)
                .font(.system(size: 9, weight: .bold)).kerning(1)
                .foregroundColor(BSTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var telemetryDivider: some View {
        Rectangle()
            .fill(BSTheme.textMuted.opacity(0.18))
            .frame(width: 1, height: 30)
    }

    // MARK: - Setup (not connected)

    private var setupCard: some View {
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

            Divider().background(BSTheme.textMuted.opacity(0.3))

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
                                liveSimService.isReadyToConnect
                                    ? BSTheme.electricCyan.opacity(0.55)
                                    : BSTheme.textMuted.opacity(0.18),
                                lineWidth: 1
                            )
                    )
            }

            // Connect button
            Button {
                Task { await liveSimService.connect() }
            } label: {
                HStack(spacing: 8) {
                    if liveSimService.isBroadcasting {
                        ProgressView().scaleEffect(0.8).tint(BSTheme.electricCyan)
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

            // Status row
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundColor(liveSimService.lastBroadcastError != nil ? BSTheme.dangerRed : BSTheme.textMuted)
                Spacer()
            }
        }
        .padding(16)
        .background(BSTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(BSTheme.electricCyan.opacity(0.25), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        if liveSimService.lastBroadcastError != nil { return BSTheme.dangerRed }
        if liveSimService.isBroadcasting            { return BSTheme.gold }
        if liveSimService.isReadyToConnect          { return BSTheme.electricCyan }
        return BSTheme.textMuted
    }

    private var statusText: String {
        if let err = liveSimService.lastBroadcastError { return err }
        if liveSimService.isBroadcasting              { return "Connecting…" }
        if liveSimService.isReadyToConnect            { return "Tap Connect to pair with the website" }
        return "Enter the code shown on your screen"
    }
}
