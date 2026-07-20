# Learn Hub — Design

Date: 2026-07-16
Status: Approved, implementing

## Goal

Give beginners a free, offline library of short lessons (2–3 min reads) that
teach them to read their own launch-monitor numbers. Complements the existing
beginner stack: intro slides → guided tutorial → ⓘ glossary marks → **lessons**
(this) → Pro AI coach.

## Placement

Third row in Locker's existing "Help & Learning" card: **"Learn the basics"**
(book icon). Presented as a sheet wrapped in `NavigationStack` — the same
pattern as Locker's Clubs / Sessions / Profile sheets. Always visible: the
beginner-help toggle keeps controlling only the ⓘ marks, not lessons.

## Components

One new file `UI/Learning/LearnHub.swift`:

- **`LearnLesson`** — id, SF Symbol icon, title, minutes, summary, sections
  (`heading` + `body` pairs), related glossary IDs. Curated 7-lesson catalog
  lives in Swift (no backend, no network):
  1. Reading your first shot — carry vs total, ball speed is king
  2. Smash factor — strike quality in one number
  3. Why the ball curves — face vs path, named shot shapes
  4. Backspin & sidespin — friend and foe
  5. Launch angle — the window that maximizes carry
  6. Know your real distances — gapping; carry (not total) picks the club
  7. Getting a clean reading — camera height, tripod, lighting
- **`LearnHubView`** — lesson list on `TrueCarryBackground`; each row: gold
  icon chip, title, "N min read", sage checkmark once read, chevron.
- **`LearnLessonView`** — serif title, sections, then a "Terms in this lesson"
  chip row; each chip opens the existing `GlossaryCardView` sheet
  (`.sheet(item:)`, `GlossaryEntry` is already `Identifiable`).

## Read state

`TCLearning.learnReadKey` (`"tc.learn.read"`), a comma-joined id string in
UserDefaults — same local-only pattern as the tutorial flags. A lesson is
marked read when its view appears.

## Footprint

- New: `UI/Learning/LearnHub.swift` (+ pbxproj registration, `BFED…` pattern)
- Edited: `TrueCarryLockerView.swift` (~12 lines: state, sheet, card row)
- No data model, migrations, or entitlement changes. Free for all tiers.
