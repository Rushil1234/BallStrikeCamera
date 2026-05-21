import SwiftUI

// MARK: - True Carry Launch Sequence
//
// Cold-start splash. The brand's green-side contour pattern is the connective
// tissue: a sonar ping ripples out from a single gold pin dot, settles into a
// static contour field, then the Atlas mark resolves from blur, the wordmark
// rises, and a light sweep hands off to the app. Mirrors the brand motion spec.

struct TrueCarryLaunchView: View {
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Brand palette — fixed forest scene regardless of app light/dark mode.
    private let forest = Color(red: 0.118, green: 0.165, blue: 0.133) // #1E2A22
    private let forestDeep = Color(red: 0.039, green: 0.051, blue: 0.043)
    private let bone   = Color(red: 0.925, green: 0.894, blue: 0.824) // #ECE4D2
    private let gold   = Color(red: 0.722, green: 0.604, blue: 0.369) // #B89A5E

    // Animation state
    @State private var pinIn = false
    @State private var ringsGo = false
    @State private var contourIn = false
    @State private var markIn = false
    @State private var wordRise = false
    @State private var detailsIn = false
    @State private var sweepGo = false
    @State private var finishing = false

    var body: some View {
        ZStack {
            // Backdrop
            RadialGradient(colors: [forest, forestDeep],
                           center: .center, startRadius: 40, endRadius: 520)
                .ignoresSafeArea()

            // Settled contour field (fades in behind the mark)
            contourField
                .opacity(contourIn ? 1 : 0)

            // Sonar ripple rings
            if !reduceMotion {
                ForEach(0..<5, id: \.self) { i in
                    LaunchRippleRing(start: ringsGo, delay: 0.30 + Double(i) * 0.26, color: bone)
                }
            }

            // Center pin dot
            Circle()
                .fill(gold)
                .frame(width: 7, height: 7)
                .shadow(color: gold.opacity(0.9), radius: 8)
                .scaleEffect(pinIn ? 1 : 0)
                .opacity(pinIn ? 1 : 0)

            // Launch mark + wordmark + details
            VStack(spacing: 26) {
                Image("tc_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(gold.opacity(0.30), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 30, x: 0, y: 18)
                    .scaleEffect(markIn ? 1 : 0.92)
                    .opacity(markIn ? 1 : 0)
                    .blur(radius: markIn ? 0 : 6)

                wordmark
                    .opacity(wordRise ? 1 : 0)

                VStack(spacing: 18) {
                    (Text("BEAR EVERY ") + Text("YARD.").foregroundColor(gold))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(3.0)
                        .foregroundColor(bone.opacity(0.6))

                    // Indeterminate loader bar
                    LaunchLoaderBar(animate: detailsIn && !reduceMotion, color: gold, track: bone)
                        .frame(width: 86, height: 1)
                }
                .opacity(detailsIn ? 1 : 0)
            }
            .offset(y: finishing ? -28 : 0)
            .opacity(finishing ? 0 : 1)

            // Light sweep at handoff
            sweep
        }
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .onAppear { run() }
    }

    // MARK: Wordmark — "True Carry." with staggered rise

    private var wordmark: some View {
        HStack(spacing: 0) {
            risingWord(Text("True ").foregroundColor(bone), delay: 0)
            risingWord(Text("Carry.").italic().foregroundColor(gold), delay: 0.12)
        }
        .font(.system(size: 38, design: .serif))
    }

    private func risingWord(_ text: Text, delay: Double) -> some View {
        text
            .offset(y: wordRise ? 0 : 44)
            .animation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.9).delay(delay), value: wordRise)
            .clipped()
    }

    // MARK: Contour field — 8 concentric static rings

    private var contourField: some View {
        ZStack {
            ForEach(1...8, id: \.self) { i in
                Circle()
                    .stroke(bone.opacity(0.12), lineWidth: 1)
                    .frame(width: CGFloat(i) * 92, height: CGFloat(i) * 92)
            }
        }
    }

    // MARK: Sweep

    private var sweep: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, bone.opacity(0.14), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.6)
            .rotationEffect(.degrees(12))
            .offset(x: sweepGo ? geo.size.width : -geo.size.width * 0.8)
            .opacity(sweepGo ? 1 : 0)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // MARK: Timeline

    private func run() {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.4)) { pinIn = true; contourIn = true; markIn = true; wordRise = true; detailsIn = true }
            after(1.4) { finish() }
            return
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.15)) { pinIn = true }
        ringsGo = true // ripple rings self-animate on their delays
        after(1.7) { withAnimation(.easeInOut(duration: 1.0)) { contourIn = true } }
        after(1.8) { withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 1.0)) { markIn = true } }
        after(2.5) { withAnimation { wordRise = true } }   // each word carries its own delay
        after(3.1) { withAnimation(.easeOut(duration: 0.6)) { detailsIn = true } }
        after(4.3) {
            withAnimation(.easeInOut(duration: 0.9)) { sweepGo = true }
            withAnimation(.easeInOut(duration: 0.8).delay(0.2)) { finishing = true }
        }
        after(5.2) { finish() }
    }

    private func skip() {
        guard !finishing else { return }
        withAnimation(.easeInOut(duration: 0.45)) { finishing = true }
        after(0.45) { finish() }
    }

    @State private var finished = false
    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }

    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

// MARK: - Ripple ring (one sonar ping)

private struct LaunchRippleRing: View {
    let start: Bool
    let delay: Double
    let color: Color
    @State private var animate = false

    var body: some View {
        Circle()
            .stroke(color.opacity(animate ? 0 : 0.55), lineWidth: 1)
            .frame(width: 64, height: 64)
            .scaleEffect(animate ? 8.5 : 0.05)
            .opacity(animate ? 0 : 1)
            .onChange(of: start) { go in
                guard go else { return }
                withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 2.2).delay(delay)) {
                    animate = true
                }
            }
            .onAppear {
                if start {
                    withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 2.2).delay(delay)) {
                        animate = true
                    }
                }
            }
    }
}

// MARK: - Indeterminate loader bar

private struct LaunchLoaderBar: View {
    let animate: Bool
    let color: Color
    let track: Color
    @State private var slide = false

    var body: some View {
        GeometryReader { geo in
            track.opacity(0.18)
            LinearGradient(colors: [.clear, color, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.32)
                .offset(x: slide ? geo.size.width : -geo.size.width * 0.4)
        }
        .clipped()
        .onChange(of: animate) { on in
            guard on else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) { slide = true }
        }
    }
}
