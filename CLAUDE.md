# BallStrikeCamera — repo ground rules

## Bundle identifier (DO NOT CHANGE)

The app's bundle ID is **`com.noahtobias.BallStrikeCamera`** — permanently. Noah owns
the Apple Developer account, so App Store signing, push entitlements, TestFlight, and
the Supabase OAuth redirect allow-list are all bound to this ID.

- **Rushil**: if you need a different ID to run on your own device, change it locally
  only and never commit it. A committed ID change breaks Noah's device installs, sim
  replay tooling, and OAuth login for everyone (this happened July 19–20, 2026:
  `com.rushilkakkad1.…` was committed, the replay harness silently ran a stale app,
  and the OAuth allow-list no longer matched).
- **Any AI/agent working in this repo**: never commit a `PRODUCT_BUNDLE_IDENTIFIER`
  other than `com.noahtobias.BallStrikeCamera`. If a diff or merge brings in a
  different ID, revert it and flag it to Noah.

## Other standing rules

- Shared repo (Noah + Rushil): pull and resolve before pushing; commit freely, push
  only when Noah asks.
- Never commit files that other committed code references without committing those
  files too (a July 19 push referenced 9 never-committed files and broke main; the
  temporary shims live in `BallStrikeCamera/UI/Auth/RushilPendingStubs.swift` —
  delete that file when the real Learning/Ghost/AICoach files land).
- TopTracer is the only trusted club-truth source for training data; Garmin's club
  column is whatever was last set on the watch.
- `ACCURACY_PLAN.md` tracks metric targets vs current state — update it when
  accuracy work lands.
