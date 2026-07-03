# iOS Polish Sprint (Track 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove every user-visible "unfinished" edge in the TrueCarry iOS app: stale coming-soon copy, mock-data screens, unwired shot replay, fake flight path, map stub, dead sheets.

**Architecture:** Six independent fixes, each shippable alone. New logic lives in two small new units (`SessionStatsService` for real analytics aggregation, `FlightArcModel` for trajectory) consumed by existing SwiftUI views; everything else is wiring existing stored data (`AppStorageManager` JSON stores, `media/shotFrames` JPEG bursts) into views that currently fake it.

**Tech Stack:** SwiftUI, AVFoundation app (iOS 17+), local JSON persistence via `AppStorageManager`, Supabase backend behind `AppBackend` protocol. No new dependencies.

## Global Constraints

- Build gate for every task: `xcodebuild -project BallStrikeCamera.xcodeproj -scheme BallStrikeCamera -sdk iphonesimulator -configuration Debug build` must succeed (quiet with `| tail -5`; exit 0).
- There is **no test target** in the project; adding one is Track 4. Verification here = build gate + fixture-driven runtime checks noted per task. Pure-logic units (Tasks 2, 4) must ALSO ship a `#Preview`/fixture path so behavior is eyeballable.
- Do not restructure files beyond the task's scope; follow existing patterns (`BSTheme`/`TCTheme` styling, `AppStorageManager.load/loadAll`).
- Commit after each task with a `feat:`/`fix:` message.
- User-visible copy: no "coming soon" phrasing anywhere after this sprint.

---

### Task 1: Real tier-gated mode cards (kill "coming soon")

**Files:**
- Modify: `BallStrikeCamera/UI/AppShell/ModeSelectionView.swift` (comingSoonNote at ~line 73; dead `.sheet { EmptyView() }` at ~line 60)
- Modify: `BallStrikeCamera/UI/AppShell/HomeDashboardView.swift:80` (dead `.sheet { EmptyView() }`)

**Interfaces:**
- Consumes: `EntitlementViewModel` (already injected via environment in the app shell; exposes current tier), `AppConfig.pricingURL`.
- Produces: nothing new — view-only change.

- [ ] **Step 1:** In `ModeSelectionView.swift`, delete the `comingSoonNote` view and its call site. Replace with a tier note that reflects reality, reading the entitlement from the environment object already available in this view hierarchy (check the file's top for `@EnvironmentObject`; if absent, add `@EnvironmentObject var entitlements: EntitlementViewModel`):

```swift
private var tierNote: some View {
    HStack(spacing: 8) {
        Image(systemName: "lock.open.fill")
            .foregroundColor(BSTheme.gold)
        Text(tierNoteText)
            .font(.system(size: 12))
            .foregroundColor(BSTheme.textMuted)
        Spacer()
        if !entitlements.isPro {
            Button("Upgrade") { openURL(AppConfig.pricingURL) }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BSTheme.gold)
        }
    }
    .padding(.horizontal, 16).padding(.vertical, 12)
    .background(BSTheme.gold.opacity(0.07))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(BSTheme.gold.opacity(0.25), lineWidth: 1))
}

private var tierNoteText: String {
    if entitlements.isPro { return "All modes unlocked." }
    if entitlements.isBasic { return "Course Mode unlocked. Sim Mode requires Pro." }
    return "Range Mode is free. Course requires Basic, Sim requires Pro."
}
```
(Adjust `isPro`/`isBasic` to the actual accessor names on `EntitlementViewModel` — read `Services/EntitlementService.swift` first; the tier enum is free/basic/pro/admin.)
Add `@Environment(\.openURL) private var openURL` if not present.

- [ ] **Step 2:** Delete the dead `.sheet(isPresented: $showCourse) { EmptyView() }` in `ModeSelectionView.swift` and the `.sheet { EmptyView() }` at `HomeDashboardView.swift:80`, plus their now-unused `@State` booleans if nothing else reads them.

- [ ] **Step 3:** Build gate. Expected: succeeds; grep the repo for `coming soon` (case-insensitive) — `ModeSelectionView` no longer matches.

- [ ] **Step 4:** Commit: `fix(ios): mode selection reflects real tier gating, remove coming-soon copy and dead sheets`

---

### Task 2: Real analytics — SessionStatsService + de-mock SessionsView

**Files:**
- Create: `BallStrikeCamera/Services/Golf/SessionStatsService.swift`
- Modify: `BallStrikeCamera/UI/AppShell/SessionsView.swift` (SessionMock array, lines 5–35)
- Modify (if it renders `InsightMock`): `BallStrikeCamera/UI/AppShell/AnalyticsView.swift` — replace mock arrays the same way.

**Interfaces:**
- Consumes: `AppStorageManager.loadAll(_:from:)`, `AppStorageManager` dirs for `sessions/range`, `sessions/sim`, `shots`; models `RangeSession`/`SimSession`/`SavedShot` (read `Models/AppModels.swift` for exact names/fields — `SavedShotMetrics.carryYards`, `.clubName`, `.createdAt` exist).
- Produces:

```swift
struct SessionSummary: Identifiable {
    enum Kind { case range, sim, shot }
    let id: UUID
    let kind: Kind
    let title: String        // "Range Session"
    let subtitle: String     // "7 Iron focus · 23 shots"
    let stat: String         // "156"
    let statUnit: String     // "yd avg"
    let date: Date
}

enum SessionStatsService {
    /// Newest-first summaries across range + sim sessions for the user.
    static func recentSummaries(userId: UUID, limit: Int = 20) -> [SessionSummary]
}
```

- [ ] **Step 1:** Implement `SessionStatsService.recentSummaries`: load range and sim sessions via `AppStorageManager.loadAll`, map each to a `SessionSummary` (avg carry from the session's shots; dominant club name for the subtitle: most-frequent `clubName` among its shots, else "Mixed bag"), merge, sort by date desc, prefix(limit). Handle missing dirs by returning `[]` (loadAll already throws — wrap in `try?`).

- [ ] **Step 2:** In `SessionsView.swift`, delete `SessionMock` and the hardcoded array. Replace with `@State private var sessions: [SessionSummary] = []` + `.task { sessions = SessionStatsService.recentSummaries(userId: currentUserId) }` (get the user id the same way sibling views do — grep `userId` in `FeedView.swift` for the pattern). Map `SessionSummary.kind` to the existing icon/accent constants that the mock rows used. Relative date via `Date.RelativeFormatStyle`.

- [ ] **Step 3:** Empty state: when `sessions.isEmpty`, render the existing card chrome with: target icon, "No sessions yet", "Hit your first range session to see it here", and a button that switches to the Play tab (grep `TCTab` selection binding for how tabs are switched programmatically).

- [ ] **Step 4:** Apply the same replacement to `AnalyticsView.swift`'s `InsightMock` usage: insights become computed from real shots (avg carry per club from all `SavedShot`s) or the empty state. Keep it to the aggregations the view already displays — no new chart types.

- [ ] **Step 5:** Build gate. Runtime check: run in simulator with a seeded local store — use guest mode (LocalBackendService) and hit 2 shots in Range mode with the camera simulated? Not feasible headless; instead add `#Preview` with fixture summaries AND verify on-device data path by temporarily logging `sessions.count` (remove log before commit).

- [ ] **Step 6:** Commit: `feat(ios): sessions & insights driven by real stored data with empty states`

---

### Task 3: Shot replay player from stored frame bursts

**Files:**
- Create: `BallStrikeCamera/UI/History/ReplayPlayerView.swift`
- Modify: `BallStrikeCamera/UI/History/ShotDetailView.swift` (Replay section, lines ~75–95; `replayPlaceholder` at ~83/93)

**Interfaces:**
- Consumes: `AppStorageManager.shotFramesDir(userId:shotId:)` (JPEG frames, `SavedShotMedia.frameCount` ~41), `AnimatedFramesView` (ShotGIFExporter.swift:70) as reference for UIImage loading.
- Produces: `ReplayPlayerView(userId: UUID, shot: SavedShot)` — self-contained; internally falls back to the composite image when no frames exist on this device.

- [ ] **Step 1:** Implement `ReplayPlayerView`: load sorted JPEG URLs from the frames dir; decode to `[UIImage]` off-main (`Task.detached`); UI = current frame `Image`, a `Slider` scrubber (frame index), play/pause button driving a `TimelineView(.periodic(from:by:))` at 1/30s per frame (captured at 240fps → ~8× slow-mo, label it "8× SLOW-MO"), and a speed toggle (¼×/1×) that steps 1 or 8 frames per tick.

- [ ] **Step 2:** In `ShotDetailView`, replace the Replay `Group` body: if frames exist on disk → `ReplayPlayerView`; else keep the existing composite `AsyncImage` path; else `replayPlaceholder` (now only for genuinely media-less shots — keep it but change its copy to "No replay media for this shot").

- [ ] **Step 3:** Build gate + runtime check: the `Experimental/BallTrackingTester` tree ships recorded frames (grep `Resources` there for sample bursts); if none, verify via `#Preview` with a fixtures folder copied into the preview bundle. Screenshot the player scrubbing.

- [ ] **Step 4:** Commit: `feat(ios): scrubbing slow-mo shot replay from captured frame bursts`

---

### Task 4: Real flight arc in BallFlightPreviewView

**Files:**
- Create: `BallStrikeCamera/Analysis/FlightArcModel.swift`
- Modify: `BallStrikeCamera/UI/BallFlightPreviewView.swift` (placeholder branch, lines ~148–170, and the real-data path so both use the model)

**Interfaces:**
- Consumes: `SavedShotMetrics` fields: `ballSpeedMph`, `vlaDegrees`, `hlaDegrees`+`hlaDirection`, `backspinRpm`, `sidespinRpm`.
- Produces:

```swift
enum FlightArcModel {
    struct Sample { let downrangeYd: Double; let offlineYd: Double; let heightFt: Double }
    /// Integrates a drag+Magnus point-mass flight; ~60 samples to landing.
    static func trajectory(ballSpeedMph: Double, vlaDeg: Double, hlaDeg: Double,
                           backspinRpm: Double, sidespinRpm: Double) -> [Sample]
}
```

- [ ] **Step 1:** Implement the integrator with the sim's constants (TrueCarry_Sim/js/physics.js lines 23-31): `G=9.81, R=0.0214, AERO=0.0192, CD_BASE=0.255, CL_MAX=0.32, CL_SLOPE` (read the js for the exact slope), spin decay `exp(-t/10)`, dt=1/60 substeps until y<0. This is ~40 lines of Swift; port faithfully so app arcs match the web sim.

- [ ] **Step 2:** In `BallFlightPreviewView.drawShotPath`, when launch metrics exist, draw the top-down polyline from `trajectory()` samples (downrange/offline), scaled by the view's existing `Scale`/`toPoint` helpers; delete the dashed placeholder line — when no metrics at all, show only the "Distance unavailable" label (keep that).

- [ ] **Step 3:** Sanity fixture in a `#Preview`: 150mph/12°/2600rpm driver should land ~250–270yd downrange; log-check once, remove log.

- [ ] **Step 4:** Build gate. Commit: `feat(ios): physically-integrated flight arc shared-constants with web sim`

---

### Task 5: Course search map

**Files:**
- Modify: `BallStrikeCamera/UI/Courses/CourseSearchView.swift` ("Map coming soon" badges; fragile matching at lines 425–451)

**Interfaces:**
- Consumes: `CourseCatalogService` (Supabase `course_geometries` with lat/lon from migration 012), `LocationService` for user region.

- [ ] **Step 1:** Replace the "Map coming soon" badge/section with a `Map` (MapKit SwiftUI, iOS 17 `Map(position:)` API) centered on the user (fallback: last search result region), showing `Annotation` pins for catalog results (name + tier badge). Tapping a pin selects the course exactly like tapping a list row (route through the same selection handler).

- [ ] **Step 2:** Harden the name+location matching (lines 425–451): prefer resolving by catalog row id when the search result came from the catalog; keep fuzzy name+proximity only for MapKit-sourced results, and tighten it to require distance < 1km AND normalized-name match (existing `findCourseGeometryNear` server logic is the model).

- [ ] **Step 3:** Build gate + simulator screenshot of the map with pins (seed location: any catalog course's coords via simulator's custom location).

- [ ] **Step 4:** Commit: `feat(ios): course search map with catalog pins; harden course resolution`

---

### Task 6: Dead-stub cleanup

**Files:**
- Modify: `BallStrikeCamera/Services/Golf/ClubAnalyticsService.swift:100` (intended-line stub)
- Modify: any remaining `.sheet { EmptyView() }`, `EmptyView() //` placeholders — `grep -rn 'EmptyView()' BallStrikeCamera/UI` and audit each.

- [ ] **Step 1:** For the intended-line stub: it returns zero today. If `AnalyticsView` (post-Task 2) no longer renders that stat, delete the function and its call sites; if it does render, implement it as signed mean of `hlaDegrees` (left = negative) across shots — that IS the intended-line deviation the UI describes.

- [ ] **Step 2:** Audit remaining `EmptyView()` placeholder sheets; delete dead ones (with their state vars). Do not touch legitimate `EmptyView()` uses in ternaries.

- [ ] **Step 3:** Build gate; full-app smoke in simulator: launch, tab through all five tabs, open a shot detail, open course search. No blank sheets, no "coming soon".

- [ ] **Step 4:** Commit: `chore(ios): remove dead placeholder sheets and stub analytics path`

---

## Final verification

1. `xcodebuild ... build` green.
2. Simulator run: five-tab walkthrough screenshots (Feed, Insights with real/empty data, Play mode cards, History→ShotDetail replay, Locker) + course search map.
3. `grep -rin "coming soon" BallStrikeCamera/` returns nothing user-visible.
4. Push after user review.

## Follow-up (separate plan)

Track 3 stickiness (feed liveliness, weekly challenges, club-gapping report, Live Activity polish) gets its own plan once this sprint ships.
