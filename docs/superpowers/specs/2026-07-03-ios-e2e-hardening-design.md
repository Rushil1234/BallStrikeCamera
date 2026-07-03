# iOS End-to-End Hardening — Tests + CI

**Date:** 2026-07-03
**Status:** executing (user asked to "make the app end to end perfect"; journey audit found no remaining stubs — the real gap is zero tests/CI with two active contributors)

## Findings from the audit

- Post-merge build (incl. teammate's `40776d6` auth/analytics/CrashReporter work): **green**.
- No TODO/FIXME/coming-soon stubs remain in user-visible code; no force-unwrap/fatalError
  patterns in the new auth files.
- The app's structural gap: **no automated tests, no iOS CI**. Yesterday's sprint started
  from a silently broken baseline (file missing from target) — the exact failure class CI kills.

## Design

1. `tools/ios-logic-tests.sh` + `tools/ios-logic-tests/main.swift`: assert-style golden
   tests compiled with `swiftc` against the app's pure logic files directly
   (FlightArcModel; ClubAnalyticsService + TrackedShot models if dependency-clean).
   No Xcode test-target surgery (pbxproj edits are the riskiest change class in this repo).
   Failing assert = nonzero exit.
2. `.github/workflows/quality.yml`: on push/PR touching app or sim paths —
   (a) `xcodebuild build` for iphonesimulator without signing,
   (b) `tools/ios-logic-tests.sh`,
   (c) `TrueCarry_Sim/tools/test.sh` (JavaScriptCore bot regression, runs on macOS runners).
3. Simulator boot smoke re-run locally post-changes; push main.

## Out of scope
Track 3 features (feed/challenges/Live Activity), structured logging migration
(320 print sites), XCUITest UI automation.
