# Beginner Mode + Robust Tutorial — Design

Date: 2026-07-15
Status: Approved, implementing

## Goal

Make True Carry approachable for beginners who don't know launch-monitor
jargon. Two capabilities:

1. **Guided first-run tutorial** — an interactive coach-mark tour that runs the
   first time a new user lands in the app shell (after the existing 4 intro
   slides). It spotlights real UI elements and walks the user through the app.
2. **Curated glossary** — small tappable `ⓘ` marks on confusing terms that open
   a plain-English definition card.

Plus a **"Beginner help" toggle + "Replay tutorial"** control in Locker.

## Relationship to existing onboarding

The existing `OnboardingView` (4 static slides, server-gated by
`profiles.onboarding_completed`) is unchanged. New flow for a fresh user:

```
intro slides → land in app shell → guided tour auto-starts (first time only)
```

## Components

New group `UI/Learning/` with three files:

- **BeginnerHelp.swift** — local persistence keys, `GlossaryEntry` model +
  curated catalog, the reusable `InfoMark` view, and `GlossaryCardView`.
- **TutorialController.swift** — `ObservableObject` driving the linear tour:
  step list, current index, active flag, requested tab. Plus `TutorialStep`
  and `TutorialAnchorID`.
- **TutorialOverlay.swift** — the `.tutorialAnchor(_:)` view modifier +
  `PreferenceKey`, and `TutorialOverlayView` (dim scrim with a spotlight
  cut-out around the current target and a caption card with progress dots /
  Skip / Next).

### Guided tour (linear, drivable steps)

Runs over navigation surfaces the controller can drive without requiring a real
shot:

1. Feed tab
2. Insights tab
3. Play tab (controller switches to it)
4. "Start Session" hero button on the Play screen
5. History tab
6. Locker tab (mentions where to replay the tutorial)
7. Closing centered card ("tap any ⓘ to learn a term")

The controller sets `requestedTab`; the shell observes it and switches tabs so
the correct anchor is on screen before the spotlight draws.

### Contextual coach marks (state-dependent steps)

The two steps that depend on real activity — **camera/tripod setup** and
**reading your shot metrics** — cannot be forced mid-tour (we won't open the
live camera or fake a shot). They ship as one-time dismissible hint cards
(`FirstTimeHint`) that appear the first time the user reaches the camera screen
and their first result card. Gated by a per-id "seen" flag and the beginner-help
toggle.

### Glossary / info marks

`InfoMark(entryID:)` renders a small `ⓘ`; tapping presents `GlossaryCardView`
in a bottom sheet (`presentationDetents`, iOS 16+). Hidden entirely when
beginner help is off. Curated ~18-entry catalog: ball speed, club speed, smash
factor, launch angle (VLA), spin rate, carry, total, apex, HLA / launch
direction, dispersion, NFC club tag, gapping, range/course/sim sessions,
handicap, etc.

Wired initially onto the highest-jargon surfaces: the shot result metrics bar
(HLA, VLA, smash, ball speed) and the Locker handicap stat. Trivially
extensible elsewhere via `InfoMark("<id>")`.

## Toggle & persistence

Local `@AppStorage`, no Supabase migration:

- `tc.beginnerHelp` (Bool, default **true**) — shows/hides `ⓘ` marks and
  contextual hints.
- `tc.tutorialCompleted` (Bool, default false) — gates auto-start of the tour.
- `tc.coach.<id>` (Bool) — per-screen first-time hint seen flags.

Locker gains a "Help & Learning" card: the toggle + a "Replay tutorial" button
(re-activates the tour from step 0).

## Hook-ins

- `TrueCarryAppShell` owns `TutorialController`, hosts the overlay, drives tab
  switches, and auto-starts the tour.
- `TCBottomDock` adds `.tutorialAnchor(tab.anchorID)` to each dock item.
- `TrueCarryPlayView` adds `.tutorialAnchor(.playStartHero)` on the start
  button; `RangeCameraScreen` and `ShotResultView` add `FirstTimeHint`s.
- `TrueCarryLockerView` adds the settings card.

## Deviation from the original 7-file plan

Consolidated 7 files → 3 to minimize edits to the hand-maintained
(non-file-system-synchronized) `.pbxproj`. Concerns stay separated within the
files.
