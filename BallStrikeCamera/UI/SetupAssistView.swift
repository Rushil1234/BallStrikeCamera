import SwiftUI
import CoreMotion

/// Pre-shot placement wizard shown on the capture screens: a live level
/// bubble, ball-lock check, and framing-distance check. Measured numbers are
/// only as good as phone placement, so this front-loads the setup ritual.
/// Auto-hides shortly after every check goes green; skippable per session;
/// can be disabled for good in the toggle row.
struct SetupAssistOverlay: View {
    @ObservedObject var camera: CameraController
    @AppStorage("tc_setup_assist_enabled") private var assistEnabled = true

    @State private var rollErrDeg: Double = 0
    @State private var pitchDeg: Double = 0
    @State private var motionReady = false
    @State private var allGreenSince: Date?
    @State private var hiddenForSession = false

    private let motion = CMMotionManager()

    // Regulation ball (42.7mm) at a sane tripod distance spans roughly this
    // fraction of the 1280px frame width.
    private static let framingBand: ClosedRange<CGFloat> = 0.012...0.08

    private var levelOK: Bool { motionReady && rollErrDeg < 3 && abs(pitchDeg) < 10 }
    private var ballOK: Bool { camera.currentBallRect != nil }
    private var framing: (ok: Bool, hint: String) {
        guard let r = camera.currentBallRect else { return (false, "Waiting for ball") }
        if r.width < Self.framingBand.lowerBound { return (false, "Move phone closer") }
        if r.width > Self.framingBand.upperBound { return (false, "Move phone back") }
        return (true, "Distance looks right")
    }

    var body: some View {
        if assistEnabled && !hiddenForSession {
            card
                .onAppear(perform: startMotion)
                .onDisappear { motion.stopDeviceMotionUpdates() }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SETUP CHECK")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
                Button("Skip") { hiddenForSession = true }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .buttonStyle(.plain)
            }

            checkRow(ok: levelOK,
                     title: "Phone level",
                     detail: motionReady
                        ? String(format: "tilt %.0f° · aim %.0f°", rollErrDeg, pitchDeg)
                        : "Reading sensors…") {
                levelBubble
            }
            checkRow(ok: ballOK, title: "Ball found",
                     detail: ballOK ? "Locked on" : "Place a ball in view") { EmptyView() }
            checkRow(ok: framing.ok, title: "Framing", detail: framing.hint) { EmptyView() }

            Button {
                assistEnabled = false
            } label: {
                Text("Don't show this again")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 250)
        .background(Color.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .onChange(of: levelOK && ballOK && framing.ok) { all in
            if all {
                allGreenSince = allGreenSince ?? Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    if let t = allGreenSince, Date().timeIntervalSince(t) >= 1.5 {
                        withAnimation { hiddenForSession = true }
                    }
                }
            } else {
                allGreenSince = nil
            }
        }
    }

    private func checkRow<Accessory: View>(
        ok: Bool, title: String, detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ok ? .green : .white.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            accessory()
        }
    }

    /// Horizon bubble: slides with roll error, green when centred.
    private var levelBubble: some View {
        ZStack {
            Capsule()
                .fill(.white.opacity(0.12))
                .frame(width: 54, height: 10)
            Circle()
                .fill(levelOK ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .offset(x: CGFloat(max(-1, min(1, rollErrDeg / 12))) * 22)
                .animation(.easeOut(duration: 0.15), value: rollErrDeg)
        }
    }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 15.0
        motion.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let g = data?.gravity else { return }
            // Landscape capture: level means gravity lies along the device's
            // long (x) axis, either direction. Roll error = deviation of the
            // horizon; pitch = camera aimed up/down (gravity into the screen).
            let a = atan2(g.y, g.x) * 180 / .pi
            rollErrDeg = min(abs(a), abs(abs(a) - 180))
            pitchDeg = asin(max(-1, min(1, g.z))) * 180 / .pi
            motionReady = true
        }
    }
}
