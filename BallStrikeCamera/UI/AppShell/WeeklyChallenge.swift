import SwiftUI

// MARK: - Camera-verified weekly challenge (Longest Verified Carry)

/// The Feed card for the weekly camera-verified long-drive challenge. Entries
/// come only from camera-tracked shots (ShotSource.live) — the differentiator
/// no self-report app can offer. Free for all tiers.
struct VerifiedChallengeCard: View {
    /// Bump to re-load (FeedView increments it on pull-to-refresh). The reload
    /// is quiet — the loading spinner only shows on the very first fetch.
    var refreshToken: Int = 0

    @EnvironmentObject private var session: AuthSessionStore

    @State private var entries: [ChallengeLeaderboardEntry] = []
    @State private var myBestShot: SavedShot?
    @State private var loading = true
    @State private var submitting = false
    @State private var errorText: String?
    @State private var showFullBoard = false

    private var myUserId: UUID? { session.currentUser?.id }

    private var myEntry: ChallengeLeaderboardEntry? {
        guard let uid = myUserId else { return nil }
        return entries.first(where: { $0.userId == uid })
    }

    private var myRank: Int? {
        guard let uid = myUserId else { return nil }
        return entries.firstIndex(where: { $0.userId == uid }).map { $0 + 1 }
    }

    /// True when the golfer has a camera-tracked carry this week that beats
    /// (or creates) their leaderboard entry.
    private var canSubmit: Bool {
        guard let shot = myBestShot else { return false }
        guard let entry = myEntry else { return true }
        return shot.metrics.carryYards > entry.carryYards
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else if entries.isEmpty {
                Text("No verified entries yet this week. Track a shot on camera and be first on the board.")
                    .font(.system(size: 12))
                    .foregroundColor(TCTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(entries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                        leaderRow(rank: index + 1, entry: entry)
                    }
                }
                if let rank = myRank, rank > 3, let mine = myEntry {
                    leaderRow(rank: rank, entry: mine)
                        .padding(.top, 2)
                }
                if entries.count > 3 {
                    Button { showFullBoard = true } label: {
                        Text("View full leaderboard")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(TCTheme.gold)
                    }
                    .buttonStyle(.plain)
                }
            }

            if canSubmit, let shot = myBestShot {
                submitButton(shot)
            } else if myEntry != nil && myBestShot != nil {
                Text("Your best tracked carry this week is on the board.")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.danger)
            }
        }
        .padding(12)
        .background(TCTheme.panel)
        // Card-level radius outside, row-level inside — matches every other
        // panel card in the feed.
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TCTheme.cardRadius, style: .continuous)
                .strokeBorder(TCTheme.gold.opacity(0.35), lineWidth: 1)
        )
        .sheet(isPresented: $showFullBoard) {
            ChallengeLeaderboardSheet(entries: entries, myUserId: myUserId)
                .tcAppearance()
        }
        .task(id: refreshToken) { await load() }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera.badge.clock")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(TCTheme.gold)
                .frame(width: 34, height: 34)
                .background(TCTheme.gold.opacity(0.13))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Longest Verified Carry")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(TCTheme.textPrimary)
                Text("Camera-tracked shots only · resets Monday")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
            }
            Spacer(minLength: 0)
            TCPill(text: "This Week", color: TCTheme.sage)
        }
    }

    private func leaderRow(rank: Int, entry: ChallengeLeaderboardEntry) -> some View {
        let isMe = entry.userId == myUserId
        return HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(rank == 1 ? TCTheme.gold : TCTheme.textMuted)
                .frame(width: 20, alignment: .center)
            Text(isMe ? "You" : entry.displayName)
                .font(.system(size: 13, weight: isMe ? .bold : .semibold))
                .foregroundColor(TCTheme.textPrimary)
                .lineLimit(1)
            if !entry.clubName.isEmpty {
                Text(entry.clubName)
                    .font(.system(size: 10))
                    .foregroundColor(TCTheme.textMuted)
            }
            Spacer(minLength: 8)
            Text("\(Int(entry.carryYards.rounded())) yd")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(rank == 1 ? TCTheme.gold : TCTheme.textPrimary)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(isMe ? TCTheme.gold.opacity(0.08) : TCTheme.panelRaised.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
    }

    private func submitButton(_ shot: SavedShot) -> some View {
        Button { Task { await submit(shot) } } label: {
            HStack(spacing: 7) {
                if submitting {
                    ProgressView().tint(Color(red: 0.05, green: 0.09, blue: 0.07)).scaleEffect(0.8)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                }
                Text("Enter my best: \(Int(shot.metrics.carryYards.rounded())) yd")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(Color(red: 0.05, green: 0.09, blue: 0.07))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(TCTheme.gold)
            .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(submitting)
    }

    // MARK: Data

    /// Monday 00:00 of the current week (ISO — matches the server's date_trunc).
    private static var weekStart: Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }

    private func load() async {
        guard let uid = myUserId else { loading = false; return }
        async let board = try? session.backend.loadChallengeLeaderboard()
        async let shots = try? session.backend.loadShots(userId: uid)
        entries = await board ?? []
        // Eligible: camera-tracked (live) shots from this week with a real carry.
        let eligible = (await shots ?? []).filter {
            $0.source == .live && $0.metrics.carryYards > 0 && $0.timestamp >= Self.weekStart
        }
        myBestShot = eligible.max(by: { $0.metrics.carryYards < $1.metrics.carryYards })
        loading = false
    }

    private func submit(_ shot: SavedShot) async {
        submitting = true
        errorText = nil
        do {
            try await session.backend.submitChallengeEntry(
                carryYards: shot.metrics.carryYards,
                ballSpeedMph: shot.metrics.ballSpeedMph > 0 ? shot.metrics.ballSpeedMph : nil,
                clubName: shot.clubName ?? "",
                shotId: shot.id
            )
            entries = (try? await session.backend.loadChallengeLeaderboard()) ?? entries
        } catch {
            errorText = "Couldn't submit — try again in a moment."
        }
        submitting = false
    }
}

// MARK: - Full leaderboard sheet

struct ChallengeLeaderboardSheet: View {
    let entries: [ChallengeLeaderboardEntry]
    let myUserId: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            TCTheme.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.badge.clock")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(TCTheme.gold)
                        Text("Longest Verified Carry")
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundColor(TCTheme.textPrimary)
                        Spacer(minLength: 0)
                    }
                    Text("This week's board. Every yard here was measured by the camera — no self-reported numbers.")
                        .font(.system(size: 12))
                        .foregroundColor(TCTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 6) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            row(rank: index + 1, entry: entry)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
        }
    }

    private func row(rank: Int, entry: ChallengeLeaderboardEntry) -> some View {
        let isMe = entry.userId == myUserId
        return HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundColor(rank <= 3 ? TCTheme.gold : TCTheme.textMuted)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(isMe ? "You" : entry.displayName)
                    .font(.system(size: 14, weight: isMe ? .bold : .semibold))
                    .foregroundColor(TCTheme.textPrimary)
                    .lineLimit(1)
                if !entry.clubName.isEmpty {
                    Text(entry.clubName)
                        .font(.system(size: 11))
                        .foregroundColor(TCTheme.textMuted)
                }
            }
            Spacer(minLength: 8)
            if let speed = entry.ballSpeedMph, speed > 0 {
                Text("\(Int(speed.rounded())) mph")
                    .font(.system(size: 11))
                    .foregroundColor(TCTheme.textMuted)
            }
            Text("\(Int(entry.carryYards.rounded())) yd")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(rank == 1 ? TCTheme.gold : TCTheme.textPrimary)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(isMe ? TCTheme.gold.opacity(0.08) : TCTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TCTheme.rowRadius, style: .continuous)
                .strokeBorder(isMe ? TCTheme.gold.opacity(0.4) : TCTheme.border, lineWidth: 1)
        )
    }
}
