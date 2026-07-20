# Verified Handicap Card — Design

Date: 2026-07-16
Status: Approved, implementing
Series: differentiators 1/3 (this), then ghost match, then camera-verified challenges.

## Goal

A shareable, branded card image of the golfer's Handicap Index that carries the
trust signal no competitor can print: how many of the counted rounds were
attested by playing partners (existing `round_attestations` infra). Sharing is
free for all tiers — the card is marketing.

## What it shows

Fixed brand-dark card (reads right in any chat/light mode):

- `TCWordmark` lockup (existing component, `onDark`)
- "HANDICAP INDEX" + the index, large
- Trust lines: "Best K of last N rounds" (from `HandicapService.Result`) and,
  when ≥ 1 counted round is attested, "M attested by playing partners"
- Gold `checkmark.seal.fill` + "TRUE CARRY VERIFIED" ribbon — shown only when
  at least one counted round is attested (honest: the seal means peer-attested,
  and we never claim camera-measured *scores*)
- Footer: date + truecarrygolf.com

## How

- New `UI/History/HandicapShareCard.swift`: `HandicapShareCardView` (fixed
  ~340pt layout, `TCTheme.capture*` palette) + `renderHandicapCard(...)`
  using `ImageRenderer` at 3× scale (iOS 16+, app's floor).
- `HandicapView` (UI/History/TrueCarryHistoryView.swift) gains:
  - `@EnvironmentObject session` and a `.task` that loads
    `session.backend.loadSentAttestations(userId:)` (local backend already
    defaults to `[]`; errors degrade to unverified, never block the screen)
  - attested-counted count = counted differentials whose `round.id` appears in
    sent attestations with `status == "attested"`
  - a "Share my handicap" gold button under the summary card (shown only when
    an index exists) → renders the card → existing `ShareSheet`

## Footprint

New file + pbxproj registration (`BFED…B7/F7` pattern), ~40 lines in
`HandicapView`. No migrations, no entitlement changes.
