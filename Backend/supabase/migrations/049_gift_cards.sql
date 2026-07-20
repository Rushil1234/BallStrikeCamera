-- ============================================================================
-- 049_gift_cards.sql
-- Store gift cards. A card is bought via a Stripe payment-mode Checkout Session;
-- the stripe-webhook generates a code, stores ONLY its SHA-256 hash here, and
-- emails the plaintext to the recipient. Redemption (redeem-gift-card edge fn)
-- atomically claims the row and adds the amount as Stripe customer-balance credit.
--
-- SECURITY: RLS is enabled with NO policies, so the table is unreachable with the
-- anon/authenticated keys — only the service role (webhook) and the SECURITY
-- DEFINER RPCs below can touch it. Codes are stored hashed; a DB leak never
-- yields usable codes or the customer email list. (Same discipline as
-- store_notify_requests / live_sim_state.)
-- ============================================================================

create table if not exists public.gift_cards (
  id                        uuid primary key default gen_random_uuid(),
  code_hash                 text not null unique,          -- sha256(plaintext code)
  amount_cents              integer not null check (amount_cents in (2500, 5000, 10000)),
  currency                  text not null default 'usd',
  status                    text not null default 'active'
                              check (status in ('active', 'redeemed', 'void')),
  purchaser_email           text,
  recipient_email           text,
  message                   text,
  stripe_session_id         text unique,                   -- idempotency for the webhook
  stripe_payment_intent_id  text,
  redeemed_by               uuid references auth.users(id) on delete set null,
  redeemed_at               timestamptz,
  created_at                timestamptz not null default now(),
  constraint gift_message_len check (message is null or char_length(message) <= 500)
);

create index if not exists gift_cards_redeemed_by_idx on public.gift_cards (redeemed_by);
create index if not exists gift_cards_created_idx     on public.gift_cards (created_at desc);

alter table public.gift_cards enable row level security;
-- No policies on purpose: service role + SECURITY DEFINER RPCs only.

-- ── Redemption RPCs ─────────────────────────────────────────────────────────
-- Called only by the redeem-gift-card edge function using the service role,
-- which has already verified the user. The verified uid is passed as p_user.

-- Atomically claim an active card. Returns the amount in cents, or NULL if the
-- code doesn't exist or was already redeemed/void. The single conditional UPDATE
-- makes concurrent double-redeem impossible.
create or replace function public.claim_gift_card(p_user uuid, p_code_hash text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_amount integer;
begin
  update public.gift_cards
     set status = 'redeemed', redeemed_by = p_user, redeemed_at = now()
   where code_hash = p_code_hash
     and status = 'active'
  returning amount_cents into v_amount;

  return v_amount;  -- NULL when nothing matched
end;
$$;

-- Revert a claim if the follow-on Stripe credit fails, so the card can be
-- retried. Only reverts a row this same user just claimed.
create or replace function public.unclaim_gift_card(p_user uuid, p_code_hash text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.gift_cards
     set status = 'active', redeemed_by = null, redeemed_at = null
   where code_hash = p_code_hash
     and status = 'redeemed'
     and redeemed_by = p_user;
end;
$$;

revoke all on function public.claim_gift_card(uuid, text)   from public, anon, authenticated;
revoke all on function public.unclaim_gift_card(uuid, text) from public, anon, authenticated;
grant execute on function public.claim_gift_card(uuid, text)   to service_role;
grant execute on function public.unclaim_gift_card(uuid, text) to service_role;

-- ── Founder-dashboard read (service-role only) ──────────────────────────────
create or replace function public.founder_gift_cards_summary()
returns table(
  total_issued        bigint,
  total_redeemed      bigint,
  cents_issued        bigint,
  cents_redeemed      bigint,
  cents_outstanding   bigint
)
language sql
security definer
set search_path = public
as $$
  select
    count(*)                                                        as total_issued,
    count(*) filter (where status = 'redeemed')                    as total_redeemed,
    coalesce(sum(amount_cents), 0)                                 as cents_issued,
    coalesce(sum(amount_cents) filter (where status = 'redeemed'), 0) as cents_redeemed,
    coalesce(sum(amount_cents) filter (where status = 'active'), 0)   as cents_outstanding
  from public.gift_cards;
$$;

revoke all on function public.founder_gift_cards_summary() from public, anon, authenticated;
grant execute on function public.founder_gift_cards_summary() to service_role;
