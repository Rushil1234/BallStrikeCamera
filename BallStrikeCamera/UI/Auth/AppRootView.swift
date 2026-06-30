import SwiftUI

struct AppRootView: View {
    @EnvironmentObject var session: AuthSessionStore
    /// Forwarded from the cold-start launch sequence so the login page plays its
    /// entrance exactly as the splash hands off (defaults true for standalone use).
    var launchComplete: Bool = true

    var body: some View {
        Group {
            if session.isLoading {
                TrueCarryLoadingView()
            } else if session.isLoggedIn {
                MainTabView()
                    .fullScreenCover(isPresented: Binding(
                        get: { session.needsOnboarding },
                        set: { _ in }   // dismissed when completeOnboarding() flips the flag
                    )) {
                        OnboardingView()
                    }
            } else {
                LoginView(startEntrance: launchComplete)
            }
        }
        .tcAppearance()
    }
}

// MARK: - Animated launch / loading screen

struct TrueCarryLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var pulse = false
    @State private var appear = false

    var body: some View {
        ZStack {
            TrueCarryBackground()

            VStack(spacing: 22) {
                ZStack {
                    // Soft pulsing halo behind the logo
                    Circle()
                        .fill(TCTheme.gold.opacity(0.10))
                        .frame(width: 96, height: 96)
                        .scaleEffect(pulse ? 1.12 : 0.88)
                        .opacity(pulse ? 0.0 : 0.9)

                    // Rotating brand arc
                    Circle()
                        .trim(from: 0.0, to: 0.72)
                        .stroke(
                            AngularGradient(
                                colors: [TCTheme.gold.opacity(0.0), TCTheme.gold],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(spin ? 360 : 0))

                    TrueCarryLogo(size: 22)
                        .scaleEffect(pulse ? 1.04 : 0.96)
                }

                Text("Loading your game")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TCTheme.textMuted)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 10)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appear = true }
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
