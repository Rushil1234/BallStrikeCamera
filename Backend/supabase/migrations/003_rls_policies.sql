-- 003_rls_policies.sql
-- True Carry — Row Level Security

-- Enable RLS on all user-owned tables
alter table profiles          enable row level security;
alter table clubs             enable row level security;
alter table shots             enable row level security;
alter table range_sessions    enable row level security;
alter table sim_sessions      enable row level security;
alter table course_rounds     enable row level security;
alter table feed_posts        enable row level security;
alter table feed_reactions    enable row level security;
alter table feed_comments     enable row level security;
alter table friend_requests   enable row level security;
alter table friendships       enable row level security;
alter table user_entitlements enable row level security;
alter table usage_counters    enable row level security;
alter table user_devices      enable row level security;

-- ── Helper: is_friend ─────────────────────────────────────────────────────────
create or replace function public.is_friend(a uuid, b uuid)
returns boolean language sql security definer as $$
    select exists (
        select 1 from friendships where user_id = a and friend_id = b
    );
$$;

-- ── Profiles ──────────────────────────────────────────────────────────────────
create policy "users can read own profile"
    on profiles for select using (auth.uid() = user_id);
create policy "users can insert own profile"
    on profiles for insert with check (auth.uid() = user_id);
create policy "users can update own profile"
    on profiles for update using (auth.uid() = user_id);

-- ── Clubs ─────────────────────────────────────────────────────────────────────
create policy "users manage own clubs"
    on clubs for all using (auth.uid() = user_id);

-- ── Shots ─────────────────────────────────────────────────────────────────────
create policy "users manage own shots"
    on shots for all using (auth.uid() = user_id);

-- ── Range Sessions ────────────────────────────────────────────────────────────
create policy "users manage own range sessions"
    on range_sessions for all using (auth.uid() = user_id);

-- ── Sim Sessions ──────────────────────────────────────────────────────────────
create policy "users manage own sim sessions"
    on sim_sessions for all using (auth.uid() = user_id);

-- ── Course Rounds ─────────────────────────────────────────────────────────────
create policy "users manage own rounds"
    on course_rounds for all using (auth.uid() = user_id);

-- ── Feed Posts ────────────────────────────────────────────────────────────────
create policy "users manage own feed posts"
    on feed_posts for all using (auth.uid() = user_id);
create policy "friends can read feed posts"
    on feed_posts for select using (
        visibility = 'everyone'
        or auth.uid() = user_id
        or (visibility = 'friends' and public.is_friend(auth.uid(), user_id))
    );

-- ── Reactions & Comments ──────────────────────────────────────────────────────
create policy "users manage own reactions"
    on feed_reactions for all using (auth.uid() = user_id);
create policy "users read reactions on visible posts"
    on feed_reactions for select using (
        exists (select 1 from feed_posts p where p.id = post_id
                and (p.visibility = 'everyone' or p.user_id = auth.uid()
                     or (p.visibility = 'friends' and public.is_friend(auth.uid(), p.user_id))))
    );

create policy "users manage own comments"
    on feed_comments for all using (auth.uid() = user_id);

-- ── Friend Requests & Friendships ─────────────────────────────────────────────
create policy "users see own friend requests"
    on friend_requests for select using (auth.uid() = from_user_id or auth.uid() = to_user_id);
create policy "users send friend requests"
    on friend_requests for insert with check (auth.uid() = from_user_id);
create policy "users resolve own received requests"
    on friend_requests for update using (auth.uid() = to_user_id);

create policy "users see own friendships"
    on friendships for select using (auth.uid() = user_id or auth.uid() = friend_id);
create policy "users manage own friendships"
    on friendships for all using (auth.uid() = user_id);

-- ── Entitlements (read only by owner; written only by service role via Stripe webhook) ──
create policy "users read own entitlement"
    on user_entitlements for select using (auth.uid() = user_id);

-- ── Usage Counters ────────────────────────────────────────────────────────────
create policy "users read own usage"
    on usage_counters for select using (auth.uid() = user_id);

-- ── Devices ───────────────────────────────────────────────────────────────────
create policy "users manage own devices"
    on user_devices for all using (auth.uid() = user_id);
