# Website Completion — Locker, Auth E2E, Sim Consistency

**Date:** 2026-07-03
**Status:** Approved direction from user ("make the website complete: locker room, sign-in flow end to end, sim transition, everything consistent"); auth-depth question defaulted to pragmatic (user AFK).

## Context

The site (Next.js 15 App Router, plain global CSS, Supabase + Stripe edge
functions) is ~80% built. Survey found: no logged-in nav state anywhere, a
divergent homepage header, a read-only premium-only account page ("locker"),
three inconsistent sim entry points, dead `PricingSection.tsx`, thin
privacy/terms, and Augusta still marked "Coming soon" in `/play` despite the
course having shipped.

## Design (four phases, independently shippable)

### A. Session-aware shell (sign-in end to end)
- New `src/lib/useSession.ts`: client hook wrapping
  `supabase.auth.getSession()` + `onAuthStateChange`, returning
  `{ user, loading, signOut }`.
- `SiteNav.tsx`: when signed in show "Account" (gold) + "Sign out" instead of
  "Sign in / Get the app". Same on mobile menu.
- Homepage `page.tsx`: delete the inline `<header className="head">`, render
  `SiteNav` like every other page (labels already match; this kills the
  duplicate header and gives home the active-underline + session state).
- `/login`: render the already-imported Apple provider button (parity with
  the checkout panel).
- `/account`: keep client-side guard but render a full-screen branded loader
  until `getUser()` resolves (no flash), and reuse `useSession`.

### B. Locker room (web account parity)
- Free-tier unlock: profile, club bag, devices, referral card visible for
  everyone; analytics/usage/activity stay premium-gated with the upsell card
  shown in place of those sections only.
- Profile editing: inline edit form (display name, username, home course)
  writing to `profiles` (same columns the iOS app writes; RLS already allows
  owner writes since the app does it with the same user JWT).
- Bag CRUD: add / edit (name, carry yards) / delete rows in `clubs` for the
  signed-in user, matching the iOS Manage Bag capability.

### C. Sim transition + one sim surface
- New `src/components/SimHost.tsx`: the polished `/play` iframe pattern
  extracted — loading state, `tc-sim-in` entrance transition, fullscreen
  toggle, back/end-session, and postMessage with explicit target origin
  (fix the `"*"` send).
- `/sim` and `/course` adopt SimHost; `/course` gets loading + transition it
  currently lacks.
- One `COURSES` source of truth (`src/lib/courses.ts`) used by `/play` and
  `/course`; **Augusta National enabled** with its own preview image
  (rendered screenshot of the new course) instead of the disabled tile.

### D. Consistency sweep
- Delete dead `src/components/PricingSection.tsx`.
- Real privacy policy + terms content (honest, product-specific: camera data
  stays on device, Supabase-hosted account data, Stripe billing, referral
  terms).
- Leave `/store` and `/bridge`/`/connect` styling for a later pass (visual
  divergence noted, not user-blocking).

## Error handling
Profile/bag writes surface Supabase errors inline (small red text, retry);
sign-out failures fall back to clearing local session. SimHost shows a retry
button if the iframe never posts `SIM_READY` within 15s.

## Testing / verification
`npm run build` green per phase; headless Chrome walkthrough on `next dev`:
sign in (seeded test user) → nav shows Account → locker edit profile + add
club → /play pairing screen renders → /course launches Augusta with
transition. Screenshots at each step. Existing checkout flow untouched
(no changes to EmbeddedCheckoutPanel logic beyond none).

## Out of scope
@supabase/ssr migration, store product pages, bridge/connect restyle,
milestones card, feed on web.
