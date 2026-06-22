-- 019_usernames_sessions_visibility.sql
-- True Carry — usernames, session lifecycle columns, shot/session visibility,
-- and a "golfers at my home course" helper. Idempotent.

-- ── Profiles: username ──────────────────────────────────────────────────────────
alter table profiles add column if not exists username text;

-- Case-insensitive uniqueness for usernames (nulls allowed until a user picks one).
create unique index if not exists profiles_username_lower_uniq
    on profiles (lower(username))
    where username is not null;

create index if not exists profiles_home_course_idx
    on profiles (lower(home_course_name))
    where home_course_name <> '';

-- ── Shots: real session_id + visibility columns (mirror of payload, for querying/RLS) ──
alter table shots add column if not exists session_id uuid;
alter table shots add column if not exists visibility text not null default 'friends';
create index if not exists shots_session_idx on shots (session_id);

-- ── Session tables: lifecycle + visibility ────────────────────────────────────────
do $$
declare t text;
begin
    foreach t in array array['range_sessions','sim_sessions','course_rounds'] loop
        execute format('alter table %I add column if not exists ended_at timestamptz', t);
        execute format('alter table %I add column if not exists is_saved boolean not null default true', t);
        execute format('alter table %I add column if not exists visibility text not null default ''friends''', t);
    end loop;
end $$;

-- ── Same-home-course helper (for "golfers at my home course") ───────────────────────
create or replace function public.shares_home_course(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1
        from profiles pa
        join profiles pb on lower(pb.home_course_name) = lower(pa.home_course_name)
        where pa.user_id = a
          and pb.user_id = b
          and coalesce(pa.home_course_name, '') <> ''
    );
$$;

-- Golfers who share the caller's home course (friends + same-course members).
create or replace function public.golfers_at_home_course()
returns table (
    user_id text,
    display_name text,
    username text,
    home_course_name text,
    profile_image_path text,
    is_friend boolean
)
language sql security definer set search_path = public as $$
    with me as (select home_course_name from profiles where user_id = auth.uid())
    select p.user_id::text, p.display_name, p.username, p.home_course_name, p.profile_image_path,
           public.is_friend(auth.uid(), p.user_id) as is_friend
    from profiles p, me
    where p.user_id <> auth.uid()
      and coalesce(me.home_course_name, '') <> ''
      and lower(p.home_course_name) = lower(me.home_course_name)
    order by p.display_name;
$$;

-- ── Visibility RLS for shots: owner always; otherwise friends or same-home-course ───
alter table shots enable row level security;
drop policy if exists "read own or visible shots" on shots;
create policy "read own or visible shots" on shots
    for select using (
        user_id = auth.uid()
        or (visibility = 'public')
        or (visibility = 'friends' and (public.is_friend(auth.uid(), user_id)
                                        or public.shares_home_course(auth.uid(), user_id)))
    );

-- Owner-only write paths remain (existing policies in 003 cover insert/update/delete by user_id).
