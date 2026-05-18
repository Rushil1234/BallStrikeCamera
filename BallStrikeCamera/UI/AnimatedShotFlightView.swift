import SwiftUI

struct AnimatedShotFlightView: View {

    let carryYards: Double?
    let totalYards: Double?
    let hlaDegrees: Double?
    let vlaDegrees: Double?
    let ballSpeedMph: Double?
    let sidespinRpmSigned: Double?
    let spinAxisDegreesSigned: Double?

    private enum Stage { case launch, topDown }
    @State private var stage: Stage = .launch
    @State private var launchOpacity: Double = 1
    @State private var topDownOpacity: Double = 0

    // New UUID each restart forces child view re-init, restarting its onAppear animation
    @State private var sideKey:   UUID = UUID()
    @State private var topKey:    UUID = UUID()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Stage 1: side-view launch
            SideLaunchAngleView(
                vlaDegrees: vlaDegrees,
                ballSpeedMph: ballSpeedMph,
                carryYards: carryYards
            )
            .id(sideKey)
            .opacity(launchOpacity)

            // Stage 2: top-down grid
            TopDownShotGridView(
                carryYards: carryYards,
                totalYards: totalYards,
                hlaDegrees: hlaDegrees,
                sidespinRpmSigned: sidespinRpmSigned,
                spinAxisDegreesSigned: spinAxisDegreesSigned
            )
            .id(topKey)
            .opacity(topDownOpacity)

            // Stage label + replay button (only during top-down)
            if stage == .topDown {
                Button(action: replayAll) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Replay")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.60))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .padding(12)
                .transition(.opacity)
            }
        }
        .onAppear { startSequence() }
    }

    // MARK: - Sequence

    private func startSequence() {
        // Reset to launch stage
        stage = .launch
        launchOpacity  = 1
        topDownOpacity = 0
        sideKey = UUID()   // forces SideLaunchAngleView.onAppear to fire again

        // After launch animation plays (~1.4s), cross-fade to top-down
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
            withAnimation(.easeInOut(duration: 0.60)) {
                launchOpacity  = 0
                topDownOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                stage  = .topDown
                topKey = UUID()   // forces TopDownShotGridView.onAppear to fire again
            }
        }
    }

    private func replayAll() {
        withAnimation(.easeInOut(duration: 0.30)) {
            launchOpacity  = 1
            topDownOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            startSequence()
        }
    }
}
