# TrueCarry iOS App — Improvement Brainstorm & Phase-1 Design

**Date:** 2026-07-03
**Status:** Awaiting user approval (brainstormed autonomously; user was AFK when asked to pick a focus)

## Context

The app is a 240fps camera launch monitor (measured ball speed/HLA/VLA, estimated
spin/carry via JSON ridge models) with range/course/sim modes, course GPS, live
web-sim pairing, GSPro Connect, NFC club tags, a watch app, and Stripe-web
entitlements — ~54k LOC of SwiftUI across 181 files. It works, but it reads as
"almost shipped": several visible placeholders, analytics on mock data, no shot
replay, no tests/CI. This doc brainstorms improvements across four tracks and
designs the recommended first slice.

## The four tracks (brainstorm)

### Track 1 — Launch-monitor accuracy (the moat)
The product's credibility = its numbers.
- **CoreML ball detector** to replace the brightness-blob heuristic
  (`Detection/BallDetector.swift`); the code already anticipates this swap.
  Train on frames the app already saves (`media/shotFrames`). Biggest win for
  mis-detects in poor light / busy backgrounds.
- **Measured spin (partial)**: true spin needs logo tracking at higher zoom —
  hard. Cheaper: improve `SpinEstimator` with VLA+speed+club regression fit
  from real GSPro/foresight reference data collected via the existing
  `Experimental/BallTrackingTester` harness.
- **Carry model**: replace the 0.75 fudge factor in `DistanceEstimator` with
  the sim's own physics engine (physics.js has a full aerodynamic model —
  port `simulateCarry` to Swift so app and sim agree on carry).
- **Calibration UX**: guided setup flow (phone height/angle wizard with a
  level indicator) — accuracy is worthless if setup varies shot to shot.

### Track 2 — Polish & finish (recommended first)
Kill everything a new user can see that says "unfinished":
1. `ModeSelectionView` still says "Sim and Course modes are coming soon" while
   both modes exist and are gated by tier — replace with real tier-gated cards.
2. `AnalyticsView`/`SessionsView` mock data (`InsightMock`, `SessionMock`) →
   drive from real stored sessions (`AppStorageManager` / Supabase `shots`).
   Empty-state designs for new users instead of fake numbers.
3. Shot replay placeholder in `ShotDetailView` → wire the already-captured
   frame buffer (`media/shotFrames`) into a scrubbing replay + slow-mo player;
   the GIF exporter already proves the frames exist.
4. `BallFlightPreviewView` straight-line path → real trajectory arc from the
   measured launch numbers (same aerodynamic step used for carry).
5. `CourseSearchView` "Map coming soon" → MapKit map with course pins from
   `CourseCatalogService` (data already there; the fragile name+location
   matching at lines 425–451 gets hardened with the pro-course IDs).
6. Dead `.sheet { EmptyView() }` in `HomeDashboardView` and the stubbed
   intended-line analysis in `ClubAnalyticsService` — finish or remove.

### Track 3 — Stickiness
- Real social feed (FeedView exists; needs friend shot cards + reactions to
  feel alive), weekly challenges (longest drive / closest-to-pin using
  measured data), club-gapping report ("your 7i goes 152, gap to 6i is 21y —
  too big"), Live Activity polish for rounds, watch-first score entry.

### Track 4 — Foundations
- XCTest target + GitHub Actions iOS build; golden-file tests for
  `ShotMetricsCalculator` using recorded frame sequences from the tester
  harness (deterministic, no camera needed).
- Split `CourseModeGPSHoleView.swift` (3,247 LOC) into hole-map, shot-entry,
  and HUD components.
- Replace `print` logging with `os.Logger` categories.

## Recommended sequencing

**Phase 1 = Track 2 (polish sprint)** — fastest user-visible lift, no new
infrastructure, each item independently shippable. Order: 1 (mode cards, an
hour) → 2 (real analytics) → 3 (shot replay) → 4 (flight arc) → 5 (course map)
→ 6 (dead code). Phase 2 = accuracy (CoreML detector first). Phase 3 =
stickiness. Foundations items land opportunistically: the XCTest target gets
created with Phase 1's analytics work (test the aggregation), CI comes with it.

## Phase-1 design notes

- **Real analytics (item 2):** one aggregation service
  (`Services/Golf/SessionStatsService.swift`, new) that folds stored
  `range_sessions`/`shots` into the structs the views already render; mocks
  become previews only. Empty state: "Hit your first session to see insights"
  with a CTA to Range mode.
- **Shot replay (item 3):** `ShotFrameStore` already persists JPEG bursts per
  shot; a `ReplayPlayerView` (TimelineView-driven, 240→30fps scrub) replaces
  `replayPlaceholder`. Export path reuses `ShotGIFExporter`.
- **Flight arc (item 4):** port the sim's `stepFly` constants (drag/Magnus) to
  a 30-line Swift integrator; both preview arc and carry estimate come from it
  so numbers agree across app and web sim.
- **Course map (item 5):** MapKit `Map` with pins from `CourseCatalogService`;
  selection resolves by pro-feed CourseID (migration 012 lat/lon fuzzy lookup
  already exists server-side).

## Verification

Per item: build + run in simulator, screenshot the changed screen; analytics
verified against a seeded local store (`LocalBackendService` fixtures); replay
verified with a recorded shotFrames folder; new XCTest target runs
`SessionStatsService` and flight-integrator golden tests in CI.

## Out of scope (this phase)

CoreML training, measured spin, StoreKit, Android, watch redesign.
