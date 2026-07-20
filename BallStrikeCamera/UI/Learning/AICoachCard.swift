import SwiftUI

/// A card that reads a shot or a club's shots and shows a visual coaching
/// summary — stat tiles, colour-coded insight rows, and one focus. Pro-gated;
/// non-Pro golfers see an upgrade prompt. Forest/gold theme. Fully on-device.
struct AICoachCard: View {
    let mode: AICoachService.Mode
    let shots: [AICoachService.ShotPayload]
    var isPro: Bool
    var title: String = "AI Coach"
    var subtitle: String = "A PGA-level read on your numbers"

    @State private var report: CoachReport?
    @State private var loading = false
    @State private var errorText: String?

    private var canRun: Bool { isPro && !shots.isEmpty }

    // tone → accent colour (forest-green good, gold watch, muted info)
    private func color(_ t: CoachReport.Tone) -> Color {
        switch t {
        case .good:  return Color(red: 0.42, green: 0.78, blue: 0.52)
        case .watch: return TCTheme.gold
        case .info:  return TCTheme.textMuted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !isPro {
                lockedBody
            } else if let report {
                reportBody(report)
            } else {
                idleBody
            }
            if let errorText {
                Text(errorText).font(.system(size: 12)).foregroundColor(TCTheme.danger)
            }
        }
        .tcCard()
    }

    // MARK: Header

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
            if isPro, report != nil {
                Button { Task { await run() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(TCTheme.gold)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .disabled(loading)
            } else if isPro {
                InfoMark("smash_factor", size: 14)
            }
        }
    }

    // MARK: Idle

    private var idleBody: some View {
        Button { Task { await run() } } label: {
            HStack(spacing: 8) {
                if loading {
                    ProgressView().tint(Color(red: 0.05, green: 0.09, blue: 0.07))
                    Text("Reading your shots…")
                } else {
                    Image(systemName: "wand.and.stars")
                    Text(mode == .session ? "Analyze these shots" : "Coach me on this shot")
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

    // MARK: Report

    private func reportBody(_ r: CoachReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // headline + shot count
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(r.headline)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundColor(TCTheme.textPrimary)
                Text(r.sub)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TCTheme.textMuted)
                Spacer(minLength: 0)
            }

            // stat tiles
            if !r.stats.isEmpty {
                HStack(spacing: 8) {
                    ForEach(r.stats) { statTile($0) }
                }
            }

            // insight rows
            VStack(alignment: .leading, spacing: 9) {
                ForEach(r.insights) { insightRow($0) }
            }

            // focus callout
            if let focus = r.focus {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "scope")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(TCTheme.gold)
                    Text(focus)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TCTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(TCTheme.gold.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(TCTheme.gold.opacity(0.35), lineWidth: 1))
                )
            }
        }
    }

    private func statTile(_ s: CoachReport.Stat) -> some View {
        VStack(spacing: 2) {
            Text(s.value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(TCTheme.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(s.label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundColor(TCTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(TCTheme.panelRaised)
        )
    }

    private func insightRow(_ ins: CoachReport.Insight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(color(ins.tone).opacity(0.16)).frame(width: 26, height: 26)
                Image(systemName: ins.icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color(ins.tone))
            }
            Text(ins.text)
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Locked

    private var lockedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Get personalized coaching on your carry, start line, launch, and gapping — powered by AI. Available on Pro.")
                .font(.system(size: 13))
                .foregroundColor(TCTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold))
                Text("Pro feature").font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(TCTheme.gold)
        }
    }

    // MARK: Run

    private func run() async {
        guard canRun, !loading else { return }
        loading = true
        errorText = nil
        do {
            let r = try await AICoachService.report(mode: mode, shots: shots)
            withAnimation(.easeInOut(duration: 0.25)) { report = r }
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}
