-- Followers / following list for a profile, so the counts on a profile are tappable
-- (Strava/Beli style). Gated by the same visibility rule as profile_social.can_view:
-- you can list a profile's followers/following only if it's your own, the account is
-- public, or you're an accepted follower. Private accounts' lists stay hidden otherwise.
--
-- want_followers = true  -> people who follow `target`
-- want_followers = false -> people `target` follows
-- Each row also reports i_follow: whether the caller already follows that person
-- (accepted), so the list can show a Follow / Following affordance inline.

create or replace function follow_list(target uuid, want_followers boolean)
returns table(user_id uuid, display_name text, home_course text, is_private boolean, i_follow boolean)
language sql stable security definer set search_path=public as $$
  with viewable as (
    select (
      target = auth.uid()
      or not coalesce((select is_private from profiles where user_id=target), false)
      or exists(select 1 from follows where follower_id=auth.uid() and following_id=target and status='accepted')
    ) as ok
  )
  select
    other.uid,
    coalesce(p.display_name, 'Golfer'),
    p.home_course_name,
    coalesce(p.is_private, false),
    exists(select 1 from follows me where me.follower_id=auth.uid() and me.following_id=other.uid and me.status='accepted')
  from (
    select case when want_followers then f.follower_id else f.following_id end as uid, f.created_at
    from follows f
    where f.status='accepted'
      and (case when want_followers then f.following_id else f.follower_id end) = target
  ) other
  left join profiles p on p.user_id = other.uid
  where (select ok from viewable)
  order by other.created_at desc;
$$;

grant execute on function follow_list(uuid, boolean) to authenticated, service_role;
