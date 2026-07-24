-- Add author_id to public_post so the web share page can LINK the author name to their
-- profile (/u/<author_id>). Safe: public_post already only returns rows whose author is a
-- non-private account, so the linked profile always resolves via public_profile.
--
-- Return type (OUT columns) changes, so the function must be dropped and recreated —
-- CREATE OR REPLACE can't alter the output signature.

drop function if exists public_post(uuid);

create function public_post(pid uuid)
returns table(author_id uuid, author_name text, title text, subtitle text, kind text,
              metric_highlight text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select
    p.user_id,
    p.payload->>'author_name',
    p.payload->>'title',
    p.payload->>'subtitle',
    p.payload->>'type',
    p.payload->>'metric_highlight',
    p."timestamp"
  from feed_posts p
  where p.id = pid
    and p.visibility = 'everyone'
    and not profile_is_private(p.user_id);
$$;

grant execute on function public_post(uuid) to anon, authenticated;
