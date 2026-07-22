import SwiftUI

/// A card that reads a shot or a club's shots and shows a visual coaching
/// summary — stat tiles, colour-coded insight rows, and one focus. Pro-gated;
/// non-Pro golfers see an upgrade prompt. Forest/gold theme. Fully on-device.
struct AICoachCard: View {
    let mode: AICoachService.Mode
    var shots: [AICoachService.ShotPayload] = []
    /// Explicit deep-read payload for round/bag placements (which have no local report).
    /// For shot/session the card builds one from `shots` automatically.
    var deepReadRequest: AICoachService.DeepReadRequest? = nil
    var isPro: Bool
    var title: String = "AI Coach"
    var subtitle: String = "A PGA-level read on your numbers"

    @State private var report: CoachReport?
    @State private var loading = false
    @State private var errorText: String?

    // Opt-in LLM deep read (OpenRouter). Only fires on an explicit tap.
    @State private var deepText: String?
    @State private var deepLoading = false
    @State private var deepError: String?
    @State private var prefilledFromSaved = false   // deepText came from a saved note, not a fresh call

    private var canRun: Bool { isPro && !shots.isEmpty }

    /// The free on-device structured report only applies to shot/session with shot data.
    private var showsLocalReport: Bool {
        (mode == .shot || mode == .session) && !shots.isEmpty
    }

    /// The deep-read payload: an explicit one (round/bag) or one built from shots.
    private var effectiveDeepRead: AICoachService.DeepReadRequest? {
        if let deepReadRequest { return deepReadRequest }
        guard !shots.isEmpty else { return nil }
        switch mode {
        case .shot:    return .forShot(shots[0])
        case .session: return .forSession(shots)
        default:       return nil
        }
    }

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
            } else {
                if showsLocalReport {
                    if let report { reportBody(report) } else { idleBody }
                }
                if effectiveDeepRead != nil {
                    deepReadSection
                }
            }
            if let errorText {
                Text(errorText).font(.system(size: 12)).foregroundColor(TCTheme.danger)
            }
        }
        .tcCard()
        .task(id: effectiveDeepRead?.contextLabel) { await loadSavedNote() }
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
                    Text(mode == .shot ? "Coach me on this shot" : "Analyze these shots")
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

    // MARK: Deep read (opt-in LLM)

    private var deepPrimary: Bool { !showsLocalReport }

    private var deepCTATitle: String {
        switch mode {
        case .round:   return "Analyze my round with AI"
        case .bag:     return "Check my gapping with AI"
        default:       return "Get a deeper AI read"
        }
    }

    @ViewBuilder private var deepReadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsLocalReport {
                Rectangle().fill(TCTheme.border).frame(height: 1).padding(.vertical, 2)
            }
            if let deepText {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .bold)).foregroundColor(TCTheme.gold)
                    Text("AI Coach").font(.system(size: 13, weight: .bold)).foregroundColor(TCTheme.textPrimary)
                    if prefilledFromSaved {
                        Text("· saved").font(.system(size: 11)).foregroundColor(TCTheme.textMuted)
                    }
                    Spacer()
                    if deepLoading {
                        ProgressView().controlSize(.small).tint(TCTheme.gold)
                    } else {
                        Button { Task { await runDeepRead() } } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold)).foregroundColor(TCTheme.gold)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(deepText)
                    .font(.system(size: 14))
                    .foregroundColor(TCTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if prefilledFromSaved {
                    Text("Tap ↻ for a fresh read")
                        .font(.system(size: 11)).foregroundColor(TCTheme.textMuted)
                }
            } else {
                Button { Task { await runDeepRead() } } label: {
                    HStack(spacing: 8) {
                        if deepLoading {
                            ProgressView().tint(deepPrimary ? Color(red: 0.05, green: 0.09, blue: 0.07) : TCTheme.gold)
                            Text("Thinking…")
                        } else {
                            Image(systemName: "wand.and.stars")
                            Text(deepCTATitle)
                        }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(deepPrimary ? Color(red: 0.05, green: 0.09, blue: 0.07) : TCTheme.gold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Group {
                            if deepPrimary {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TCTheme.gold)
                            } else {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(TCTheme.gold.opacity(0.12))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(TCTheme.gold.opacity(0.4), lineWidth: 1))
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
                .disabled(deepLoading)
            }
            if let deepError {
                Text(deepError).font(.system(size: 12)).foregroundColor(TCTheme.danger)
            }
        }
    }

    private func runDeepRead() async {
        guard let request = effectiveDeepRead, !deepLoading else { return }
        deepLoading = true
        deepError = nil
        do {
            let text = try await AICoachService.deepRead(request)
            withAnimation(.easeInOut(duration: 0.25)) { deepText = text; prefilledFromSaved = false }
        } catch {
            deepError = error.localizedDescription
        }
        deepLoading = false
    }

    /// On appear, show the most recent SAVED read for this context (free) instead of making
    /// the golfer re-spend to see coaching they already got. Refresh re-calls the model.
    private func loadSavedNote() async {
        guard isPro, deepText == nil, let req = effectiveDeepRead else { return }
        if let saved = await AICoachService.latestNoteSummary(mode: req.mode, contextLabel: req.contextLabel) {
            withAnimation(.easeInOut(duration: 0.2)) { deepText = saved; prefilledFromSaved = true }
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

// MARK: - Coach history (saved AI summaries on the profile)

/// The golfer's saved AI coaching summaries (ai_coach_notes), newest first. Reachable from
/// the profile. Read-only — the coach saves each deep-read automatically, and those same
/// notes feed future coaching as context.
struct CoachHistoryView: View {
    let backend: AppBackend
    @Environment(\.dismiss) private var dismiss
    @State private var notes: [CoachNote] = []
    @State private var loaded = false

    var body: some View {
        ZStack {
            TrueCarryBackground(pattern: .plain)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if notes.isEmpty {
                        emptyState
                    } else {
                        ForEach(notes) { noteCard($0) }
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, TCTheme.hPad)
                .padding(.top, 8)
            }
        }
        .navigationBarHidden(true)
        .task {
            notes = (try? await backend.loadCoachNotes()) ?? []
            loaded = true
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Coaching History")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Text("Every AI read, saved to your profile")
                    .font(.system(size: 13)).foregroundColor(TCTheme.textMuted)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TCTheme.textMuted)
                    .frame(width: 32, height: 32)
                    .background(TCTheme.panel).clipShape(Circle())
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: loaded ? "sparkles" : "hourglass")
                .font(.system(size: 26)).foregroundColor(TCTheme.textUltraMuted)
            Text(loaded ? "No coaching yet" : "Loading…")
                .font(.system(size: 16, weight: .semibold)).foregroundColor(TCTheme.textPrimary)
            if loaded {
                Text("Tap “Get a deeper AI read” on a shot, session, or round and it'll be saved here.")
                    .font(.system(size: 13)).foregroundColor(TCTheme.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 44)
    }

    private func noteCard(_ note: CoachNote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: note.modeIcon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(TCTheme.gold)
                    .frame(width: 30, height: 30)
                    .background(TCTheme.gold.opacity(0.14)).clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.contextLabel?.isEmpty == false ? note.contextLabel! : note.modeTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TCTheme.textPrimary).lineLimit(1)
                    Text(note.modeTitle + (note.createdAt.map { " · " + relativeTime($0) } ?? ""))
                        .font(.system(size: 11)).foregroundColor(TCTheme.textMuted)
                }
                Spacer(minLength: 0)
            }
            Text(note.summary)
                .font(.system(size: 14))
                .foregroundColor(TCTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
    }
}
