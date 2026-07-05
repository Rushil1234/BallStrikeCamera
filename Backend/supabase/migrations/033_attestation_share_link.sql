-- 033_attestation_share_link.sql
-- Lets a golfer share a public link (iMessage/SMS/anywhere) asking someone WITHOUT a
-- True Carry account to attest a round. The requester still creates the row as themselves,
-- but leaves attester_id null since the recipient isn't a known user yet; share_token is the
-- unguessable key the public web page (truecarrygolf.com/attest/<token>) uses to read and
-- respond to the request. Friend-to-friend attestation (020/023) is unchanged — every row
-- just gets a token now, unused unless the requester chooses to share a link instead.

alter table round_attestations
    alter column attester_id drop not null;

alter table round_attestations
    add column if not exists share_token uuid unique default gen_random_uuid();

-- Public read for the web confirmation page — SECURITY DEFINER bypasses RLS (which is scoped
-- to auth.uid() and would otherwise block an anonymous visitor entirely); the token itself,
-- not auth.uid(), is the security boundary here, mirroring respond_to_attestation's pattern of
-- using an explicit WHERE predicate rather than relying on the caller's row-level policy.
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
    where share_token = p_token;
$$;

revoke execute on function public.get_attestation_by_token(uuid) from public;
grant  execute on function public.get_attestation_by_token(uuid) to anon, authenticated;

-- Public respond — token-gated instead of auth.uid()-gated, and single-use (only fires while
-- status is still 'pending') so a link can't be replayed to flip an already-answered request.
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
      and status = 'pending';

    if not found then
        raise exception 'This attestation link is invalid or has already been used.';
    end if;
end;
$$;

revoke execute on function public.respond_to_attestation_by_token(uuid, boolean, text) from public;
grant  execute on function public.respond_to_attestation_by_token(uuid, boolean, text) to anon, authenticated;
