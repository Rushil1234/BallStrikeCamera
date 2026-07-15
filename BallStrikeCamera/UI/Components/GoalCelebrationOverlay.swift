import SwiftUI

// MARK: - Goal celebration popup

/// App-wide toast for weekly-goal completions and sim-course unlocks. Mounted once in
/// TrueCarryAppShell; presents the service's queue one card at a time, auto-dismissing
/// after a few seconds (tap to dismiss immediately).
struct GoalCelebrationOverlay: View {
    @ObservedObject private var goals = WeeklyGoalsService.shared
    @State private var visibleCelebration: GoalCelebration?
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        VStack {
            if let celebration = visibleCelebration {
                celebrationCard(celebration)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { dismiss(celebration) }
            }
            Spacer()
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: visibleCelebration)
        .onChange(of: goals.celebrationQueue) { _ in presentNextIfIdle() }
        .onAppear { presentNextIfIdle() }
    }

    private func celebrationCard(_ c: GoalCelebration) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(c.isUnlock ? TCTheme.gold.opacity(0.18) : TCTheme.sage.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: c.isUnlock ? "trophy.fill" : c.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(c.isUnlock ? TCTheme.gold : TCTheme.sage)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Text(c.message)
                    .font(.system(size: 13))
                    .foregroundColor(TCTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(TCTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder((c.isUnlock ? TCTheme.gold : TCTheme.sage).opacity(0.45), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func presentNextIfIdle() {
        guard visibleCelebration == nil, let next = goals.celebrationQueue.first else { return }
        visibleCelebration = next
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            guard !Task.isCancelled else { return }
            dismiss(next)
        }
    }

    private func dismiss(_ celebration: GoalCelebration) {
        dismissTask?.cancel()
        visibleCelebration = nil
        goals.dismissCelebration(celebration)
        // Let the exit animation finish before the next card slides in.
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            presentNextIfIdle()
        }
    }
}

// MARK: - Sim course unlocks card (home feed)

/// The unlock ladder the weekly challenges feed into: every completed challenge (the same
/// cards in the feed's Weekly Challenges section) banks one permanent credit, and lifetime
/// credits unlock sim courses — no re-accomplishing goals each week.
struct SimUnlocksCard: View {
    @ObservedObject private var goals = WeeklyGoalsService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SIM COURSE UNLOCKS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(TCTheme.textMuted)
                    .tracking(1.4)
                Spacer()
                Text("\(goals.totalGoalsCompleted) goal\(goals.totalGoalsCompleted == 1 ? "" : "s") completed")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(TCTheme.textUltraMuted)
            }

            ForEach(WeeklyGoalsService.unlockLadder) { course in
                ladderRow(course)
            }

            Text("Complete the weekly challenges above — every one you finish counts forever.")
                .font(.system(size: 11))
                .foregroundColor(TCTheme.textUltraMuted)
        }
        .tcCard(padding: 14)
    }

    private func ladderRow(_ course: SimCourseUnlock) -> some View {
        let unlocked = goals.isUnlocked(course.id)
        let remaining = max(0, course.goalsRequired - goals.totalGoalsCompleted)
        return HStack(spacing: 10) {
            Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(unlocked ? TCTheme.sage : TCTheme.gold)
                .frame(width: 20)
            Text(course.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(unlocked ? TCTheme.textPrimary : TCTheme.textMuted)
            Spacer()
            if unlocked {
                Text("Unlocked")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(TCTheme.sage)
            } else {
                Text(remaining == 1 ? "1 goal away" : "\(remaining) goals away")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(TCTheme.textUltraMuted)
            }
        }
    }
}
