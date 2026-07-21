-- Follow/following social graph (replaces mutual-friends for profiles) + profile privacy.
-- Asymmetric: A can follow B without B following back. Private accounts require the
-- target to approve a pending follow request before the follower can see their activity.
--
-- Non-regressive rollout: profiles default to public (is_private=false) and follows starts
-- empty, so the updated feed policy behaves exactly like the old friends-only policy until
-- people actually follow / go private.

alter table profiles add column if not exists is_private boolean not null default false;

create table if not exists follows (
  id uuid primary key default gen_random_uuid(),
  follower_id uuid not null references auth.users(id) on delete cascade,
  following_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'accepted' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  unique (follower_id, following_id),
  check (follower_id <> following_id)
);
create index if not exists follows_following_idx on follows(following_id, status);
create index if not exists follows_follower_idx on follows(follower_id, status);

alter table follows enable row level security;
drop policy if exists "read own follows" on follows;
create policy "read own follows" on follows for select to authenticated
  using (follower_id = (select auth.uid()) or following_id = (select auth.uid()));
-- No insert/update/delete policies: all writes go through the SECURITY DEFINER RPCs below.

create or replace function is_follower(viewer uuid, target uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from follows where follower_id=viewer and following_id=target and status='accepted');
$$;
create or replace function profile_is_private(uid uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce((select is_private from profiles where user_id=uid), false);
$$;
grant execute on function is_follower(uuid,uuid) to authenticated, service_role;
grant execute on function profile_is_private(uuid) to authenticated, service_role;

-- Feed visibility: own OR accepted-follower OR (legacy) friend OR public post from a public account.
drop policy if exists "friends can read feed posts" on feed_posts;
create policy "followers and friends can read feed posts" on feed_posts for select to authenticated
using (
  (select auth.uid()) = user_id
  or is_follower((select auth.uid()), user_id)
  or is_friend((select auth.uid()), user_id)
  or (visibility = 'everyone' and not profile_is_private(user_id))
);

-- Returns a single-column table row (not a scalar) so PostgREST + the app's generic
-- rpc decoder get an array of row objects.
create or replace function follow_user(target uuid)
returns table(status text) language plpgsql security definer set search_path=public as $$
declare me uuid := auth.uid(); priv boolean; st text;
begin
  if me is null or me = target then status := 'invalid'; return next; return; end if;
  priv := coalesce((select is_private from profiles where user_id=target), false);
  st := case when priv then 'pending' else 'accepted' end;
  insert into follows(follower_id, following_id, status) values (me, target, st)
    on conflict (follower_id, following_id)
    do update set status = case when follows.status='accepted' then 'accepted' else excluded.status end;
  status := (select f.status from follows f where f.follower_id=me and f.following_id=target);
  return next;
end $$;

create or replace function unfollow_user(target uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  delete from follows where follower_id=auth.uid() and following_id=target;
end $$;

create or replace function respond_follow_request(follower uuid, accept boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  if accept then
    update follows set status='accepted' where follower_id=follower and following_id=auth.uid() and status='pending';
  else
    delete from follows where follower_id=follower and following_id=auth.uid() and status='pending';
  end if;
end $$;

create or replace function set_profile_privacy(is_priv boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  update profiles set is_private=is_priv, updated_at=now() where user_id=auth.uid();
end $$;

create or replace function profile_social(target uuid)
returns table(follower_count int, following_count int, follow_status text, is_private boolean, can_view boolean)
language sql stable security definer set search_path=public as $$
  select
    (select count(*)::int from follows where following_id=target and status='accepted'),
    (select count(*)::int from follows where follower_id=target and status='accepted'),
    coalesce((select status from follows where follower_id=auth.uid() and following_id=target), 'none'),
    coalesce((select is_private from profiles where user_id=target), false),
    (target = auth.uid()
      or not coalesce((select is_private from profiles where user_id=target), false)
      or exists(select 1 from follows where follower_id=auth.uid() and following_id=target and status='accepted'));
$$;

create or replace function incoming_follow_requests()
returns table(follower_id uuid, display_name text, created_at timestamptz)
language sql stable security definer set search_path=public as $$
  select f.follower_id, coalesce(p.display_name, 'Golfer'), f.created_at
  from follows f left join profiles p on p.user_id = f.follower_id
  where f.following_id = auth.uid() and f.status='pending'
  order by f.created_at desc;
$$;

grant execute on function follow_user(uuid) to authenticated, service_role;
grant execute on function unfollow_user(uuid) to authenticated, service_role;
grant execute on function respond_follow_request(uuid,boolean) to authenticated, service_role;
grant execute on function set_profile_privacy(boolean) to authenticated, service_role;
grant execute on function profile_social(uuid) to authenticated, service_role;
grant execute on function incoming_follow_requests() to authenticated, service_role;
