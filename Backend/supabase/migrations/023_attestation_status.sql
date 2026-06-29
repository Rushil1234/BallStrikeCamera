-- 023_attestation_status.sql
-- Let the requester see WHO verified their round. We denormalize the attester's
-- name onto the row when they respond, via a SECURITY DEFINER RPC (so the name
-- is resolved from the attester's profile, not trusted from the client).

alter table round_attestations
    add column if not exists attester_name text not null default '';

-- Respond to an attestation request addressed to the caller. Sets the status,
-- the timestamp, and stamps the responder's display name for the requester's UI.
create or replace function public.respond_to_attestation(
    p_id     uuid,
    p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    uid uuid := auth.uid();
begin
    if uid is null then
        raise exception 'respond_to_attestation requires an authenticated user';
    end if;

    update round_attestations
    set status        = case when p_accept then 'attested' else 'declined' end,
        responded_at  = now(),
        attester_name = coalesce(
            (select coalesce(nullif(username, ''), nullif(display_name, ''), '')
             from profiles where user_id = uid),
            '')
    where id = p_id
      and attester_id = uid;       -- caller may only respond to their own requests

    if not found then
        raise exception 'attestation not found or not addressed to you';
    end if;
end;
$$;

revoke execute on function public.respond_to_attestation(uuid, boolean) from public, anon;
grant  execute on function public.respond_to_attestation(uuid, boolean) to authenticated;
