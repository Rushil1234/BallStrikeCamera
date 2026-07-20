import SwiftUI

/// A card that fetches short AI coaching for a shot or a recent-shots session
/// summary. Pro-gated: non-Pro golfers see an upgrade prompt instead of the
/// button. Styled to match the app's forest/gold theme.
struct AICoachCard: View {
    let mode: AICoachService.Mode
    let shots: [AICoachService.ShotPayload]
    var isPro: Bool
    var title: String = "AI Coach"
    var subtitle: String = "A PGA-level read on your numbers"

    @State private var coaching: String?
    @State private var loading = false
    @State private var errorText: String?

    private var canRun: Bool { isPro && !shots.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !isPro {
                lockedBody
            } else if let coaching {
                coachingBody(coaching)
            } else {
                idleBody
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.danger)
            }
        }
        .tcCard()
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(TCTheme.gold.opacity(0.14)).frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(TCTheme.gold)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .serif))
                    .foregroundColor(TCTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
            }
            Spacer(minLength: 0)
            if isPro {
                InfoMark("smash_factor", size: 14)
            }
        }
    }

    private var idleBody: some View {
        Button {
            Task { await run() }
        } label: {
            HStack(spacing: 8) {
                if loading {
                    ProgressView().tint(Color(red: 0.05, green: 0.09, blue: 0.07))
                    Text("Reading your shots…")
                } else {
                    Image(systemName: "wand.and.stars")
                    Text(mode == .session ? "Analyze my recent shots" : "Coach me on this shot")
                }
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(Color(red: 0.05, green: 0.09, blue: 0.07))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(canRun ? TCTheme.gold : TCTheme.gold.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canRun || loading)
    }

    private func coachingBody(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await run() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Regenerate")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TCTheme.gold)
            }
            .buttonStyle(.plain)
            .disabled(loading)
        }
    }

    private var lockedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Get personalized coaching on your face angle, path, spin, and gapping — powered by AI. Available on Pro.")
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Pro feature")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(TCTheme.gold)
        }
    }

    // MARK: Fetch

    private func run() async {
        guard canRun, !loading else { return }
        loading = true
        errorText = nil
        do {
            let text = try await AICoachService.fetchCoaching(mode: mode, shots: shots)
            withAnimation(.easeInOut(duration: 0.25)) { coaching = text }
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}
