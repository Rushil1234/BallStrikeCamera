-- 026_rate_limiting.sql
-- App-level rate limiting, enforced in the DB so it can't be bypassed by a
-- modified client hitting PostgREST/Storage directly.
--
-- Model: fixed-window counters keyed by (user, action, window_start). A
-- SECURITY DEFINER function bumps the counter and raises SQLSTATE 'P0001' with a
-- 'rate_limit_exceeded' message when the ceiling is passed. BEFORE INSERT triggers
-- on the high-volume tables (and storage.objects) call it, so limits apply to
-- shots, feed posts/comments, rounds, sessions, and video/frame uploads.
--
-- Auth endpoints (login, signup, OTP, password reset) are throttled separately by
-- the Supabase platform — tune those in supabase/config.toml ([auth.rate_limit]).

create table if not exists rate_limits (
    user_id      uuid        not null,
    action       text        not null,
    window_start timestamptz not null,
    count        integer     not null default 0,
    primary key (user_id, action, window_start)
);
alter table rate_limits enable row level security;
-- No policies: only the SECURITY DEFINER function below (and service role) touch this.

-- Bump the caller's counter for `action`; raise if it exceeds p_max within p_window_secs.
create or replace function public.enforce_rate_limit(
    p_action      text,
    p_max         integer,
    p_window_secs integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    uid uuid := auth.uid();
    w   timestamptz;
    c   integer;
begin
    -- Service-role / trusted server contexts have no auth.uid(); don't throttle them.
    if uid is null then
        return;
    end if;

    w := to_timestamp(floor(extract(epoch from now()) / p_window_secs) * p_window_secs);

    insert into rate_limits (user_id, action, window_start, count)
    values (uid, p_action, w, 1)
    on conflict (user_id, action, window_start)
        do update set count = rate_limits.count + 1
    returning count into c;

    if c > p_max then
        raise exception 'rate_limit_exceeded: % (limit % per %s)', p_action, p_max, p_window_secs
            using errcode = 'P0001',
                  hint = 'Slow down and retry shortly.';
    end if;
end;
$$;

revoke execute on function public.enforce_rate_limit(text, integer, integer) from public, anon;
grant  execute on function public.enforce_rate_limit(text, integer, integer) to authenticated;

-- ── Generic trigger: BEFORE INSERT rate guard, configured per-table via args ────
-- TG_ARGV[0]=action label, [1]=max, [2]=window seconds.
create or replace function public.tg_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    perform public.enforce_rate_limit(TG_ARGV[0], TG_ARGV[1]::int, TG_ARGV[2]::int);
    return new;
end;
$$;

-- Per-table insert limits (per user, per minute). Generous enough for real use,
-- tight enough to stop scripted abuse / quota exhaustion.
drop trigger if exists rl_shots on shots;
create trigger rl_shots before insert on shots
    for each row execute function public.tg_rate_limit('shot_insert', '120', '60');

drop trigger if exists rl_course_rounds on course_rounds;
create trigger rl_course_rounds before insert on course_rounds
    for each row execute function public.tg_rate_limit('round_insert', '30', '60');

drop trigger if exists rl_range_sessions on range_sessions;
create trigger rl_range_sessions before insert on range_sessions
    for each row execute function public.tg_rate_limit('range_session_insert', '30', '60');

drop trigger if exists rl_sim_sessions on sim_sessions;
create trigger rl_sim_sessions before insert on sim_sessions
    for each row execute function public.tg_rate_limit('sim_session_insert', '30', '60');

drop trigger if exists rl_feed_posts on feed_posts;
create trigger rl_feed_posts before insert on feed_posts
    for each row execute function public.tg_rate_limit('feed_post_insert', '20', '60');

drop trigger if exists rl_feed_comments on feed_comments;
create trigger rl_feed_comments before insert on feed_comments
    for each row execute function public.tg_rate_limit('feed_comment_insert', '40', '60');

drop trigger if exists rl_friend_requests on friend_requests;
create trigger rl_friend_requests before insert on friend_requests
    for each row execute function public.tg_rate_limit('friend_request_insert', '30', '60');

-- ── Storage upload limits (video / frame) ──────────────────────────────────────
-- Enforced on storage.objects so a client can't spray uploads even with a valid JWT.
create or replace function public.tg_rate_limit_storage()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
begin
    if new.bucket_id = 'shot-videos' then
        perform public.enforce_rate_limit('video_upload', 30, 60);
    elsif new.bucket_id = 'shot-frames' then
        perform public.enforce_rate_limit('frame_upload', 600, 60);   -- ~one shot's burst of frames
    elsif new.bucket_id = 'profile-images' then
        perform public.enforce_rate_limit('avatar_upload', 10, 60);
    end if;
    return new;
end;
$$;

drop trigger if exists rl_storage_objects on storage.objects;
create trigger rl_storage_objects before insert on storage.objects
    for each row execute function public.tg_rate_limit_storage();

-- ── Housekeeping ───────────────────────────────────────────────────────────────
-- Old windows are dead weight. Purge anything older than a day. Schedule with
-- pg_cron (see SCALE_AND_SECURITY.md) or call periodically from an edge cron.
create or replace function public.purge_rate_limits()
returns void
language sql
security definer
set search_path = public
as $$
    delete from rate_limits where window_start < now() - interval '1 day';
$$;
revoke execute on function public.purge_rate_limits() from public, anon, authenticated;
