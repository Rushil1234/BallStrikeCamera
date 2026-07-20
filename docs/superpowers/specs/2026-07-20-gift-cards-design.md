# True Carry — Gift Cards (Stripe, end-to-end)

Date: 2026-07-20
Status: Design approved (pending written-spec review)

## Goal

Sell True Carry gift cards on `/store` and let recipients redeem them, end-to-end
with Stripe. Redeemed value becomes **Stripe customer-balance credit** that
auto-applies to the recipient's next Pro/Atlas subscription invoice. Build and
prove it in Stripe **test mode** (the account isn't live-verified yet); it goes
live by swapping keys.

Non-goals (v1): applying credit to physical gear (gear checkout doesn't exist
yet — customer balance will cover it automatically when it does); scheduled/
future-dated gift delivery; gift-card refunds/void UI (DB status supports it,
no UI yet).

## Decisions

- **Amounts:** fixed presets **$25 / $50 / $100**. The server validates the
  amount is one of these — the client never sets an arbitrary amount.
- **Redemption model:** Stripe **customer-balance credit** (negative balance).
  No coupon math; Stripe applies it to the next invoice automatically.
- **Redeem location:** a field on **`/account`**; the emailed "Redeem" button
  deep-links to `/account?redeem=CODE` and prefills it. No separate page.
- **Email:** the owner's **Zoho Mail** account over SMTP (`smtp.zoho.com:465`).
  Credentials live only as Supabase secrets, set by the owner (never in chat or
  committed files).
- **Buyer need not be logged in** — you can gift a stranger.

## Architecture

Four moving parts, each independently testable:

### 1. Purchase — `create-giftcard-session` (new edge function)
- Input: `{ amountCents, recipientEmail, purchaserEmail, message? }`.
- Validates `amountCents ∈ {2500, 5000, 10000}` and both emails' shape.
- Creates a Stripe Checkout Session, `mode: "payment"`, one line item via
  `price_data` (`unit_amount = amountCents`, product name "True Carry Gift Card
  — $NN"). Puts `{ type: "giftcard", amountCents, recipientEmail,
  purchaserEmail, message }` in `session.metadata` **and**
  `payment_intent_data.metadata` (so it survives to the webhook).
- Returns the Checkout URL; the store form redirects to it.
- No auth required (public gifting). CORS like the other functions.

### 2. Fulfillment — extend `stripe-webhook`
- On `checkout.session.completed`, branch on `metadata.type`:
  - `"giftcard"` → **new** `handleGiftCardPurchase(session)`.
  - else → existing subscription path (unchanged).
- `handleGiftCardPurchase`:
  1. Generate a code `TC-XXXX-XXXX-XXXX` (Crockford base32, ~15 random chars
     from `crypto.getRandomValues`).
  2. `code_hash = sha256(code)`; insert a `gift_cards` row (status `active`)
     with amount, emails, message, `stripe_session_id`,
     `stripe_payment_intent_id`. Store **only the hash**, never plaintext.
  3. Email the recipient the plaintext code + a `/account?redeem=CODE` button,
     via Zoho SMTP.
- **Idempotency:** unique constraint on `stripe_session_id`; a re-delivered
  webhook hits the conflict and does not double-issue or double-email.

### 3. Redemption — `redeem-gift-card` (new edge function, authenticated)
1. Auth the caller (Bearer token → `supabase.auth.getUser`).
2. Normalize + `sha256` the submitted code.
3. RPC `claim_gift_card(p_code_hash)` — `SECURITY DEFINER`, atomic:
   `update gift_cards set status='redeemed', redeemed_by=auth.uid(),
   redeemed_at=now() where code_hash=$1 and status='active' returning
   amount_cents`. Zero rows → already redeemed / invalid (return a generic
   "invalid or already used" — don't distinguish, to limit probing).
4. Ensure the user has a Stripe customer: read
   `user_entitlements.stripe_customer_id`; if missing, `stripe.customers.create`
   with the user's email and **save it back** to `user_entitlements`. (The
   existing `create-checkout-session` already reuses this id, so the credit will
   apply when they subscribe — the only integration point.)
5. `stripe.customers.createBalanceTransaction(customerId, { amount:
   -amountCents, currency: "usd", description: "Gift card <masked code>" })`.
6. If step 5 throws, **revert**: RPC `unclaim_gift_card(p_code_hash, uid)` sets
   the row back to `active`; return an error so the user can retry.
7. Return `{ ok, amountCents, creditBalanceCents }`.
- Light rate-limit (per user, a few attempts/min) to blunt code probing, though
  codes are high-entropy.

### 4. Store form + account redeem (website)
- **Store:** the gift-card card's "Get it" opens a `GiftCardPanel` (client):
  preset picker ($25/$50/$100), recipient email, optional message, buyer email
  → calls `create-giftcard-session` → `window.location = checkoutUrl`.
- **Account:** a "Redeem a gift card" field on `/account`. Reads `?redeem=` to
  prefill. Submits to `redeem-gift-card`; on success shows
  "$NN credit added — it comes off your next plan automatically." Also surface
  the current credit balance if non-zero.

## Data model — `gift_cards`

```
id                    uuid pk default gen_random_uuid()
code_hash             text not null unique         -- sha256 of the plaintext code
amount_cents          int  not null check (amount_cents in (2500,5000,10000))
currency              text not null default 'usd'
status                text not null default 'active'
                        check (status in ('active','redeemed','void'))
purchaser_email       text
recipient_email       text
message               text
stripe_session_id     text unique                  -- idempotency
stripe_payment_intent_id text
redeemed_by           uuid references auth.users(id)
redeemed_at           timestamptz
created_at            timestamptz not null default now()
```
- RLS **enabled**, **no anon/authenticated policies** — the table is reachable
  only through the service role (webhook) and the `SECURITY DEFINER` RPCs. A
  public key can never read codes or the customer emails (same discipline as
  `store_notify_requests` / `live_sim_state`).
- Indexes: `code_hash` (unique already), `redeemed_by`, `created_at desc`.
- Founder-dashboard read RPCs (`founder_gift_cards_*`) are service-role only —
  optional follow-up, not required for v1.

## Email (Zoho SMTP)

- Sent from the webhook via `denomailer` to `smtp.zoho.com:465` (implicit TLS).
- Secrets (owner sets via Supabase, never pasted in chat):
  `ZOHO_SMTP_USER` (login / From address), `ZOHO_SMTP_PASSWORD`
  (**app-specific** password from Zoho, not the account password).
- One HTML template: the code in a monospace chip, a "Redeem" button to
  `/account?redeem=CODE`, the amount, and the optional gift message.
- If SMTP fails, the row is still created (status `active`) and the failure is
  logged; the code is recoverable from the founder side. Purchase is never lost
  to an email hiccup.

## Secrets / config to add

Supabase function env: `ZOHO_SMTP_USER`, `ZOHO_SMTP_PASSWORD`,
`STRIPE_GIFTCARD_*` (none needed — amounts are inline `price_data`).
`TRUECARRY_WEBSITE_URL` already exists (used for redeem links).

## Security notes

- Codes stored **hashed**; plaintext exists only in the recipient's inbox.
- Amount is server-validated against the preset set — no client-chosen amounts.
- Redemption is atomic (single conditional UPDATE) → **no double-redeem** even
  under concurrent requests; Stripe credit only after a successful claim, with
  revert on Stripe failure.
- Generic redemption errors (don't reveal whether a code exists).
- No new public RLS surface.

## End-to-end test (test mode, $0)

1. `/store` → gift card → pick $25 → emails → Checkout with `4242 4242 4242
   4242` → success.
2. Webhook: one `gift_cards` row (status active), one email delivered to the
   recipient (verify in the Zoho sent folder / inbox).
3. Redeem the code on `/account` as a test user → `claim_gift_card` marks it
   redeemed, Stripe shows a **-$25** customer balance.
4. Subscribe to Pro → the first invoice is reduced by the credit.
5. Re-submit the same code → "invalid or already used"; re-deliver the webhook →
   no duplicate row/email (idempotency).

## Rollout

- All migrations + functions deploy to the existing project
  (`aoxturoezgecwceudeef`) in test mode.
- Register the `checkout.session.completed` event (already handled) — no new
  webhook endpoint needed; the existing one now branches on metadata.
- Live: swap to live Stripe keys once the account is verified; set the Zoho
  secrets; no code change.
