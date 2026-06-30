import SwiftUI

/// First-run tutorial, shown once after a user's first login. Completion is
/// persisted to Supabase (profiles.onboarding_completed) via the auth store, so
/// it never reappears and the state is known server-side.
struct OnboardingView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var page = 0
    @State private var finishing = false

    private struct Slide { let icon: String; let title: String; let body: String }

    private let slides: [Slide] = [
        Slide(icon: "iphone.gen3",
              title: "Welcome to True Carry",
              body: "Your iPhone is the launch monitor. Stand it on a tripod beside the ball — no extra hardware to buy."),
        Slide(icon: "camera.aperture",
              title: "It reads the strike",
              body: "True Carry captures impact at 240 frames per second to measure ball speed, launch angle, and the carry the ball actually flies."),
        Slide(icon: "wave.3.right",
              title: "Tag your clubs",
              body: "Tap an NFC club card before a shot and it's logged to that club automatically — your gapping builds itself."),
        Slide(icon: "dot.radiowaves.left.and.right",
              title: "Play anywhere",
              body: "Warm up on the range, stream live to the web simulator, or play a full course round with scoring."),
    ]

    private var isLast: Bool { page >= slides.count - 1 }

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { Task { await finish() } }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TCTheme.textMuted)
                        .disabled(finishing)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                TabView(selection: $page) {
                    ForEach(slides.indices, id: \.self) { i in
                        slideView(slides[i]).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    if isLast { Task { await finish() } }
                    else { withAnimation { page += 1 } }
                } label: {
                    Text(isLast ? "Get started" : "Next")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(TCTheme.gold)
                        .foregroundColor(Color(red: 0.05, green: 0.09, blue: 0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(finishing)
                .padding(.horizontal, 20)
                .padding(.bottom, 26)
            }
        }
    }

    private func slideView(_ s: Slide) -> some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(TCTheme.gold.opacity(0.12)).frame(width: 112, height: 112)
                Image(systemName: s.icon)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundColor(TCTheme.gold)
            }
            Text(s.title)
                .font(.system(size: 25, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text(s.body)
                .font(.system(size: 15))
                .foregroundColor(TCTheme.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private func finish() async {
        guard !finishing else { return }
        finishing = true
        await session.completeOnboarding()   // flips needsOnboarding -> false, dismissing the cover
    }
}
