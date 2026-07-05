-- 034_attestation_expiry_ratelimit.sql
-- Two hardening additions to round_attestations (raised after shipping 033's share-link flow):
--   1. Expiry — a link stops working after a window (7 days) instead of staying valid forever
--      until answered.
--   2. Rate limiting — reuses the generic enforce_rate_limit()/tg_rate_limit() mechanism from
--      026_rate_limiting.sql so a user can't spam-create attestation requests (friend- or
--      link-based; both go through the same INSERT path).
--
-- Anonymous responses (someone tapping a link with no account) are deliberately NOT rate-limited
-- here: enforce_rate_limit() keys off auth.uid(), which is null for anon callers, and IP-based
-- limiting for a single Postgres function is a bigger, more fragile addition (shared NAT/IPv6
-- rotation cause false positives) that isn't worth it against a 122-bit random token — brute
-- forcing share_token guesses is already computationally infeasible. The single-use
-- `status = 'pending'` guard (033) remains the actual anti-replay mechanism for that side.

alter table round_attestations
    add column if not exists expires_at timestamptz not null default (now() + interval '7 days');

drop trigger if exists rl_round_attestations on round_attestations;
create trigger rl_round_attestations before insert on round_attestations
    for each row execute function public.tg_rate_limit('attestation_request_insert', '10', '60');

-- Expired links read as "not found" rather than confirming a token ever existed.
create or replace function public.get_attestation_by_token(p_token uuid)
returns table (
    course_name    text,
    round_date     timestamptz,
    score          integer,
    to_par         integer,
    requester_name text,
    status         text
)
language sql
security definer
set search_path = public
stable
as $$
    select course_name, round_date, score, to_par, requester_name, status
    from round_attestations
    where share_token = p_token
      and expires_at > now();
$$;

-- Same token + pending-only guard as before, now additionally gated on expiry.
create or replace function public.respond_to_attestation_by_token(
    p_token         uuid,
    p_accept        boolean,
    p_attester_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    update round_attestations
    set status        = case when p_accept then 'attested' else 'declined' end,
        responded_at  = now(),
        attester_name = coalesce(nullif(trim(p_attester_name), ''), 'A friend')
    where share_token = p_token
      and status = 'pending'
      and expires_at > now();

    if not found then
        raise exception 'This attestation link is invalid, expired, or has already been used.';
    end if;
end;
$$;

revoke execute on function public.get_attestation_by_token(uuid) from public;
grant  execute on function public.get_attestation_by_token(uuid) to anon, authenticated;
revoke execute on function public.respond_to_attestation_by_token(uuid, boolean, text) from public;
grant  execute on function public.respond_to_attestation_by_token(uuid, boolean, text) to anon, authenticated;
