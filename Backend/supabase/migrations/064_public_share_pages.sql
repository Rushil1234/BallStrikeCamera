-- Public, RLS-safe projections for the website share-link landing pages
-- (truecarry.golf/post/<id> and /u/<id>). feed_posts / profiles are otherwise only readable
-- by authenticated users under RLS; these SECURITY DEFINER functions expose ONLY the handful
-- of shareable fields, and ONLY for content that is genuinely public:
--   * a post: visibility='everyone' AND its author is not a private account
--   * a profile: the account is not private
-- Anything private/friends-only returns zero rows, so a shared link to it shows "not found".
-- Granted to anon so the (logged-out) web page can render + generate link previews.

create or replace function public_post(pid uuid)
returns table(author_name text, title text, subtitle text, kind text,
              metric_highlight text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select
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

create or replace function public_profile(pid uuid)
returns table(display_name text, username text, home_course text,
              follower_count int, following_count int)
language sql stable security definer set search_path = public as $$
  select
    pr.display_name,
    pr.username,
    pr.home_course_name,
    (select count(*)::int from follows where following_id = pid and status = 'accepted'),
    (select count(*)::int from follows where follower_id  = pid and status = 'accepted')
  from profiles pr
  where pr.user_id = pid
    and not coalesce(pr.is_private, false);
$$;

grant execute on function public_post(uuid) to anon, authenticated;
grant execute on function public_profile(uuid) to anon, authenticated;
