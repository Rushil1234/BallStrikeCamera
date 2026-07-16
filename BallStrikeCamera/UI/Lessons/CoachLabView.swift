import SwiftUI

// MARK: - Ball Flight Lab
// Coach's interactive physics room: three live diagrams (face & path, launch & spin,
// strike point) with sliders and one-tap example presets. The captions rewrite
// themselves as the sliders move, so every position IS a worked example.

struct CoachLabView: View {
    let onDone: () -> Void

    @State private var faceDeg: Double = 4
    @State private var pathDeg: Double = -3
    @State private var launchDeg: Double = 17
    @State private var spinRPM: Double = 6200
    @State private var strike: Double = 0.75

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: TCTheme.sectionGap) {
                    header
                    facePathSection
                    launchSpinSection
                    strikeSection
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 14)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onDone) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(TCTheme.textMuted)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(TCTheme.panelRaised))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            .padding(.top, 10)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ball Flight Lab")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(TCTheme.textPrimary)
            Text("Drag the sliders — the flight, the name of the shot, and the why all update live. These are the same three numbers the camera measures on your real swings.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(TCTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 44)   // clear the close button
    }

    // MARK: Sections

    private var facePathSection: some View {
        labCard(
            title: "Why the ball curves",
            subtitle: "Face sends it, path bends it",
            badge: FaceToPathDiagram.shotName(face: faceDeg, path: pathDeg)
        ) {
            FaceToPathDiagram(faceDeg: $faceDeg, pathDeg: $pathDeg)
                .frame(height: 250)

            labSlider("Face", value: $faceDeg, range: -8...8, unit: "°",
                      leftLabel: "closed", rightLabel: "open", tint: TCTheme.goldLight)
            labSlider("Path", value: $pathDeg, range: -8...8, unit: "°",
                      leftLabel: "out-to-in", rightLabel: "in-to-out", tint: TCTheme.sage)

            presetRow([
                ("Slice", { faceDeg = 5; pathDeg = -5 }),
                ("Draw", { faceDeg = -1.5; pathDeg = 3 }),
                ("Pull hook", { faceDeg = -6; pathDeg = -2 }),
                ("Straight", { faceDeg = 0; pathDeg = 0 }),
            ])

            captionText(FaceToPathDiagram.explanation(face: faceDeg, path: pathDeg))
        }
    }

    private var launchSpinSection: some View {
        labCard(
            title: "Launch & spin",
            subtitle: "The height–distance trade",
            badge: "\(Int(launchDeg))° · \(Int(spinRPM)) rpm"
        ) {
            LaunchSpinDiagram(launchDeg: $launchDeg, spinRPM: $spinRPM)
                .frame(height: 200)

            labSlider("Launch", value: $launchDeg, range: 6...38, unit: "°",
                      leftLabel: "low", rightLabel: "high", tint: TCTheme.goldLight)
            labSlider("Spin", value: $spinRPM, range: 1500...10000, unit: " rpm",
                      leftLabel: "low", rightLabel: "high", tint: TCTheme.sage)

            presetRow([
                ("Driver bomb", { launchDeg = 15; spinRPM = 2300 }),
                ("Stock 7-iron", { launchDeg = 19; spinRPM = 6500 }),
                ("Balloon wedge", { launchDeg = 32; spinRPM = 9500 }),
                ("Thin bullet", { launchDeg = 8; spinRPM = 2200 }),
            ])

            captionText(LaunchSpinDiagram.explanation(launchDeg: launchDeg, spinRPM: spinRPM))
        }
    }

    private var strikeSection: some View {
        labCard(
            title: "Strike point",
            subtitle: "Gear effect — the miss that curves itself",
            badge: abs(strike) < 0.2 ? "Center" : (strike > 0 ? "Toe" : "Heel")
        ) {
            GearEffectDiagram(strike: $strike)
                .frame(height: 210)

            labSlider("Impact", value: $strike, range: -1...1, unit: "",
                      leftLabel: "heel", rightLabel: "toe", tint: TCTheme.gold)

            presetRow([
                ("Heel", { strike = -0.8 }),
                ("Pure", { strike = 0 }),
                ("Toe", { strike = 0.8 }),
            ])

            captionText(GearEffectDiagram.explanation(strike: strike))
        }
    }

    // MARK: Card & control scaffolding

    private func labCard<Content: View>(title: String, subtitle: String, badge: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(TCTheme.textUltraMuted)
                }
                Spacer()
                Text(badge)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(TCTheme.gold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(TCTheme.gold.opacity(0.14)))
                    .animation(nil, value: badge)
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                .fill(TCTheme.panel)
                .overlay(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                    .stroke(TCTheme.border, lineWidth: 1))
        )
    }

    private func labSlider(_ name: String, value: Binding<Double>, range: ClosedRange<Double>,
                           unit: String, leftLabel: String, rightLabel: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(name)
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(TCTheme.textMuted)
                Spacer()
                Text(unit.isEmpty ? "" : (unit == "°" && value.wrappedValue >= 0 ? "+" : "") + String(format: unit == "°" ? "%.1f" : "%.0f", value.wrappedValue) + unit)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(TCTheme.textSecondary)
            }
            Slider(value: value, in: range)
                .tint(tint)
            HStack {
                Text(leftLabel).font(.system(size: 9, weight: .semibold)).foregroundColor(TCTheme.textUltraMuted)
                Spacer()
                Text(rightLabel).font(.system(size: 9, weight: .semibold)).foregroundColor(TCTheme.textUltraMuted)
            }
        }
    }

    private func presetRow(_ presets: [(String, () -> Void)]) -> some View {
        HStack(spacing: 8) {
            ForEach(presets.indices, id: \.self) { i in
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { presets[i].1() }
                } label: {
                    Text(presets[i].0)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(TCTheme.textPrimary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(TCTheme.panelRaised))
                        .overlay(Capsule().stroke(TCTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func captionText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundColor(TCTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(TCTheme.panelRaised.opacity(0.7)))
    }
}
