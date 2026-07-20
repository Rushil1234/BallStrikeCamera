# Ghost Match — Design

Date: 2026-07-16
Status: Approved, implementing
Series: differentiators 2/3 (verified handicap card shipped; camera-verified challenges next).

## Goal

Race a past round on the same course, match-play style, while playing course
mode. All local: reads rounds already saved, no backend or migrations.

## Placement change from the approved sketch

The sketch put the ghost picker on `RoundSetupView`, but that view is dead code
(no call sites — the live flow is CourseSearch → fullScreenCover
`CourseModeGPSHoleView` directly). The picker therefore lives in the hole view:
after the round starts, past scored rounds on the same `courseId` load in the
background; when any exist, a dismissible **offer chip** ("Race your ghost —
best here: 82") appears under the wind pill. Tapping opens a picker sheet
(rounds best-first, gold "Best" pill on the top row).

## Components (UI/Courses/GhostMatch.swift)

- **`GhostMatchScorer`** — pure match-play math. Holes compared by
  `holeNumber`; only holes where BOTH rounds have a score count. Status text:
  "1 UP thru 5", "ALL SQUARE thru 3", closed-out "WON 3&2" / "LOST 2&1",
  finished "WON 2 UP" / "HALVED". Decided when lead > holes remaining
  (round length = max of both hole counts).
- **`GhostStrip`** — HUD pill (existing `hudGlass` style) under the wind pill:
  "Ghost: 4 here · 1 UP thru 5". Gold when up, silver when down, white when
  square. X ends the match.
- **`GhostOfferChip`** — the dismissible invitation.
- **`GhostPickerSheet`** — past-round list, best first.

## State & lifecycle

`ghostRound` / `ghostCandidates` / `showGhostPicker` / `ghostOfferDismissed`
are `@State` on `CourseModeGPSHoleView` — in-memory for this presentation only.
If the app dies mid-round, resuming the round does re-offer the ghost (the
candidates reload), but the previously selected ghost is not remembered — an
accepted v1 tradeoff. Match status recomputes reactively from
`vm.activeRound.holes`, so score entry updates it immediately.

## Footprint

New file + pbxproj (BFED…B8/F8), ~40 lines in `CourseModeGPSHoleView`
(state, strip insertion, candidate load in `.task`, picker sheet).
