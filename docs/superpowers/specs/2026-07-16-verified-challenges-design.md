# Camera-Verified Weekly Challenges — Design

Date: 2026-07-16
Status: Approved, implementing (iOS built; migration 041 pending apply)
Series: differentiators 3/3 (verified handicap card + ghost match shipped).

## Goal

A weekly global leaderboard — v1: **Longest Verified Carry** — where entries
come only from camera-tracked shots (`ShotSource.live`). The anti-cheat no
self-report golf app can offer. Free for all tiers.

## Backend (Backend/supabase/migrations/041_weekly_challenges.sql)

- `challenge_entries`: user_id, week_start (Monday UTC), challenge_type
  (default `longest_carry`), carry_yards, ball_speed_mph, club_name, shot_id,
  `unique (user_id, week_start, challenge_type)` — one best entry per user/week.
- RLS on; users SELECT their own rows; **all writes go through RPC** (no table
  grants), so arbitrary values can't be forged via PostgREST.
- `submit_challenge_entry(p_carry_yards, p_ball_speed_mph, p_club_name,
  p_shot_id)` — SECURITY DEFINER: sanity bounds (carry 25–450 yd, ball speed
  ≤ 250 mph — rejected, not clamped), keep-best upsert on the week key.
- `weekly_challenge_leaderboard()` — SECURITY DEFINER, stable: top 50 for the
  current week with the minimal profiles projection (display_name), matching
  the `search_users` pattern. Both RPCs granted to `authenticated` only.

**Trust boundary (v1, honest):** the server cannot prove a value came from the
camera; the client submits only `source == .live` shots, and the server adds
bounds + RPC-only writes. Server-side provenance (signed shot payloads) is a
possible v2.

## iOS

- `ChallengeLeaderboardEntry` (Models/SocialModels.swift) — decoded from the
  leaderboard RPC.
- `AppBackend` gains `submitChallengeEntry(...)` + `loadChallengeLeaderboard()`
  with local-backend no-op defaults; `SupabaseBackendService` implements both
  via the existing `rpc`/`rpcVoid` helpers.
- `UI/AppShell/WeeklyChallenge.swift`:
  - `VerifiedChallengeCard` — inserted at the top of FeedView's existing
    "Weekly Challenges" section (above the personal progress rows). Shows top 3
    (+ your row if ranked below), a gold **"Enter my best: N yd"** button that
    appears only when your best camera-tracked carry this week beats your
    board entry, and "View full leaderboard".
  - `ChallengeLeaderboardSheet` — the full top-50 board, "You" highlighted.
- Week window on the client uses ISO-8601 Monday UTC to match the server's
  `date_trunc('week', now() at time zone 'utc')`.

## Footprint

Migration 041 (pending apply via Supabase MCP), 1 new UI file + pbxproj
(BFED…B9/F9), small additions to SocialModels / AppBackend /
SupabaseBackendService / FeedView. No entitlement gating.
