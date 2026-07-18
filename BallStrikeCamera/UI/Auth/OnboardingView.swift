import SwiftUI

/// First-run flow, shown once after a user's first login (persisted to Supabase via
/// profiles.onboarding_completed, so it never reappears and state is known server-side).
///
/// Two quick questions — golf experience and what they already know — feed a GolfProfile
/// that tailors EVERY guide in the app: the welcome tour that follows on the main shell,
/// and each page's first-visit walkthrough. A brand-new golfer gets every term defined
/// and is steered to Coach; a plus-handicap gets the terse version.
struct OnboardingView: View {
    @EnvironmentObject var session: AuthSessionStore
    @State private var page = 0
    @State private var finishing = false
    @State private var experience: GolfProfile.Experience? = nil
    @State private var knowledge: Set<GolfProfile.Knowledge> = []
    @State private var noneOfThese = false

    var body: some View {
        ZStack {
            TrueCarryBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    if page > 0 {
                        Button("Back") { withAnimation { page -= 1 } }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(TCTheme.textMuted)
                    }
                    Spacer()
                    Button("Skip") { Task { await finish() } }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TCTheme.textMuted)
                        .disabled(finishing)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                if page == 0 { experiencePage } else { knowledgePage }

                Button {
                    if page == 0 {
                        withAnimation { page = 1 }
                    } else {
                        Task { await finish() }
                    }
                } label: {
                    Text(page == 0 ? "Next" : "Show me around")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(TCTheme.gold.opacity(canAdvance ? 1 : 0.35))
                        .foregroundColor(Color(red: 0.05, green: 0.09, blue: 0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(finishing || !canAdvance)
                .padding(.horizontal, 20)
                .padding(.bottom, 26)
            }
        }
    }

    private var canAdvance: Bool {
        page == 0 ? experience != nil : (!knowledge.isEmpty || noneOfThese)
    }

    // MARK: Page 1 — experience

    private var experiencePage: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Welcome to True Carry",
                   "First, how much golf have you played? This tailors every explanation in the app to you.")
            ForEach(GolfProfile.Experience.allCases, id: \.self) { exp in
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { experience = exp }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: experience == exp ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(experience == exp ? TCTheme.gold : TCTheme.textMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exp.label)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(TCTheme.textPrimary)
                            Text(exp.blurb)
                                .font(.system(size: 12))
                                .foregroundColor(TCTheme.textMuted)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(experience == exp ? TCTheme.gold.opacity(0.10) : TCTheme.panel)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(experience == exp ? TCTheme.gold.opacity(0.6) : TCTheme.border,
                                        lineWidth: 1))
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    // MARK: Page 2 — knowledge

    private var knowledgePage: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("What do you already know?",
                   "Pick everything you're comfortable with — we'll define the rest as you go.")
            ForEach(GolfProfile.Knowledge.allCases, id: \.self) { k in
                let on = knowledge.contains(k)
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        if on { knowledge.remove(k) } else { knowledge.insert(k); noneOfThese = false }
                    }
                } label: {
                    knowledgeRow(k.label, selected: on)
                }
                .buttonStyle(.plain)
            }
            Button {
                withAnimation(.easeOut(duration: 0.12)) {
                    noneOfThese.toggle()
                    if noneOfThese { knowledge.removeAll() }
                }
            } label: {
                knowledgeRow("None of these yet — teach me everything", selected: noneOfThese)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private func knowledgeRow(_ label: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark.square.fill" : "square")
                .font(.system(size: 18))
                .foregroundColor(selected ? TCTheme.gold : TCTheme.textMuted)
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(TCTheme.textPrimary)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? TCTheme.gold.opacity(0.10) : TCTheme.panel)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? TCTheme.gold.opacity(0.6) : TCTheme.border, lineWidth: 1))
        )
    }

    private func header(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(TCTheme.textPrimary)
            Text(sub)
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }

    private func finish() async {
        guard !finishing else { return }
        finishing = true
        var profile = GolfProfile()
        profile.experience = experience ?? .playRegularly
        profile.knowledge = knowledge
        profile.save()
        // The shell's welcome tour (dock spotlights) fires next because this key is unset.
        UserDefaults.standard.set(false, forKey: "tc_welcome_tour_done_v1")
        await session.completeOnboarding()   // flips needsOnboarding -> false, dismissing the cover
    }
}
