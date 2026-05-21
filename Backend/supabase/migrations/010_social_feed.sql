-- 010_social_feed.sql
-- True Carry — Strava-style social activity feed.
-- Adds friend discovery (search + invite codes), reciprocal friendship creation,
-- and the read policy needed so friends can see each other's comments.
--
-- profiles RLS only exposes a user's own row (003_rls_policies.sql), so all
-- cross-user reads go through SECURITY DEFINER RPCs that return a minimal,
-- non-sensitive projection (display name + home course + avatar path).

-- ── Comments: allow reading comments on posts you can see ───────────────────────
-- 003 only granted "manage own" on feed_comments, so friends could never read
-- each other's comments. Mirror the reactions read policy.
create policy "users read comments on visible posts"
    on feed_comments for select using (
        exists (select 1 from feed_posts p where p.id = post_id
                and (p.visibility = 'everyone' or p.user_id = auth.uid()
                     or (p.visibility = 'friends' and public.is_friend(auth.uid(), p.user_id))))
    );

-- ── Invite codes ────────────────────────────────────────────────────────────────
create table if not exists invite_codes (
    code       text primary key,
    user_id    uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now()
);

alter table invite_codes enable row level security;

create policy "users manage own invite codes"
    on invite_codes for all using (auth.uid() = user_id);

-- ── Friend search ───────────────────────────────────────────────────────────────
-- Case-insensitive name search across all profiles, excluding the caller.
create or replace function public.search_users(q text)
returns table (
    user_id uuid,
    display_name text,
    home_course_name text,
    profile_image_path text
)
language sql security definer set search_path = public as $$
    select p.user_id, p.display_name, p.home_course_name, p.profile_image_path
    from profiles p
    where p.user_id <> auth.uid()
      and length(coalesce(q, '')) >= 2
      and p.display_name ilike '%' || q || '%'
    order by p.display_name
    limit 20;
$$;

-- ── Friends list (names for the people you're connected to) ─────────────────────
create or replace function public.list_friends()
returns table (
    user_id uuid,
    display_name text,
    home_course_name text,
    profile_image_path text
)
language sql security definer set search_path = public as $$
    select p.user_id, p.display_name, p.home_course_name, p.profile_image_path
    from friendships f
    join profiles p on p.user_id = f.friend_id
    where f.user_id = auth.uid()
    order by p.display_name;
$$;

-- ── Incoming friend requests (with requester name) ──────────────────────────────
create or replace function public.list_incoming_requests()
returns table (
    request_id uuid,
    from_user_id uuid,
    display_name text,
    sent_at timestamptz
)
language sql security definer set search_path = public as $$
    select r.id, r.from_user_id, p.display_name, r.sent_at
    from friend_requests r
    join profiles p on p.user_id = r.from_user_id
    where r.to_user_id = auth.uid()
      and r.status = 'pending'
    order by r.sent_at desc;
$$;

-- ── Accept a friend request → create reciprocal friendships ─────────────────────
create or replace function public.accept_friend_request(req_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
    r friend_requests%rowtype;
begin
    select * into r from friend_requests where id = req_id;
    if not found then
        raise exception 'Friend request not found';
    end if;
    if r.to_user_id <> auth.uid() then
        raise exception 'Not authorized to accept this request';
    end if;

    update friend_requests
       set status = 'accepted', resolved_at = now()
     where id = req_id;

    insert into friendships (user_id, friend_id) values (r.from_user_id, r.to_user_id)
        on conflict (user_id, friend_id) do nothing;
    insert into friendships (user_id, friend_id) values (r.to_user_id, r.from_user_id)
        on conflict (user_id, friend_id) do nothing;
end;
$$;

-- ── Redeem an invite code → create reciprocal friendships ───────────────────────
create or replace function public.redeem_invite(p_code text)
returns void
language plpgsql security definer set search_path = public as $$
declare
    owner uuid;
begin
    select user_id into owner from invite_codes where code = p_code;
    if not found then
        raise exception 'Invite code not found';
    end if;
    if owner = auth.uid() then
        return; -- can't friend yourself; treat as no-op
    end if;

    insert into friendships (user_id, friend_id) values (owner, auth.uid())
        on conflict (user_id, friend_id) do nothing;
    insert into friendships (user_id, friend_id) values (auth.uid(), owner)
        on conflict (user_id, friend_id) do nothing;
end;
$$;

-- Allow authenticated users to call the RPCs.
grant execute on function public.search_users(text)        to authenticated;
grant execute on function public.list_friends()            to authenticated;
grant execute on function public.list_incoming_requests()  to authenticated;
grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.redeem_invite(text)       to authenticated;
