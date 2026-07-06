-- ============================================================================
-- True Carry — apply migrations 026–034 in one shot.
-- Paste this whole file into Supabase Dashboard → SQL Editor → Run.
-- Idempotent & transactional-safe; re-runnable. Generated from migrations/.
-- ============================================================================


-- ####################################################################
-- ## 026_rate_limiting.sql
-- ####################################################################
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


-- ####################################################################
-- ## 027_audit_log.sql
-- ####################################################################
-- 027_audit_log.sql
-- Security/audit trail for the events that matter when something goes wrong or a
-- dispute/chargeback/abuse report comes in: subscription changes, deletions of
-- user content, and account deletions. Append-only; readable only by service role.
--
-- Auth events (failed logins, password resets, signups) are already captured in
-- Supabase's auth audit log — this table covers the *application* layer.

create table if not exists audit_log (
    id          bigint generated always as identity primary key,
    occurred_at timestamptz not null default now(),
    actor_id    uuid,                    -- auth.uid() of whoever caused it (null for system/service)
    action      text not null,           -- e.g. 'entitlement.changed', 'round.deleted', 'account.deleted'
    entity      text,                    -- table/domain the action touched
    entity_id   text,                    -- pk of the affected row
    detail      jsonb not null default '{}'::jsonb
);

create index if not exists audit_log_occurred_idx on audit_log (occurred_at desc);
create index if not exists audit_log_action_idx   on audit_log (action, occurred_at desc);
create index if not exists audit_log_actor_idx    on audit_log (actor_id, occurred_at desc);

alter table audit_log enable row level security;
-- No policies → no anon/authenticated access. Only service role (dashboards, admin
-- tooling, edge functions) and SECURITY DEFINER writers below can touch it.

-- Central writer. SECURITY DEFINER so triggers running as an unprivileged user can
-- still append. Callable by authenticated users so edge functions / RPCs can log
-- app-level events (e.g. account deletion), but they can only WRITE, never read.
create or replace function public.write_audit(
    p_action    text,
    p_entity    text default null,
    p_entity_id text default null,
    p_detail    jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into audit_log (actor_id, action, entity, entity_id, detail)
    values (auth.uid(), p_action, p_entity, p_entity_id, coalesce(p_detail, '{}'::jsonb));
end;
$$;
revoke execute on function public.write_audit(text, text, text, jsonb) from public, anon;
grant  execute on function public.write_audit(text, text, text, jsonb) to authenticated;

-- ── Subscription changes ───────────────────────────────────────────────────────
-- The Stripe webhook writes entitlements as service role; capture every change so
-- tier/payment_status transitions are reconstructable for support & chargebacks.
create or replace function public.tg_audit_entitlement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if TG_OP = 'UPDATE'
       and new.tier = old.tier
       and new.payment_status = old.payment_status
       and coalesce(new.cancel_at_period_end,false) = coalesce(old.cancel_at_period_end,false) then
        return new;  -- nothing meaningful changed (e.g. period bump), skip noise
    end if;
    insert into audit_log (actor_id, action, entity, entity_id, detail)
    values (
        auth.uid(),
        'entitlement.' || lower(TG_OP),
        'user_entitlements',
        new.user_id::text,
        jsonb_build_object(
            'old_tier',   (case when TG_OP='UPDATE' then old.tier else null end),
            'new_tier',   new.tier,
            'old_status', (case when TG_OP='UPDATE' then old.payment_status else null end),
            'new_status', new.payment_status,
            'cancel_at_period_end', new.cancel_at_period_end,
            'stripe_subscription_id', new.stripe_subscription_id
        )
    );
    return new;
end;
$$;

drop trigger if exists audit_entitlement on user_entitlements;
create trigger audit_entitlement after insert or update on user_entitlements
    for each row execute function public.tg_audit_entitlement();

-- ── Content deletions ──────────────────────────────────────────────────────────
-- Log deletions of rounds & shots so accidental/abusive bulk wipes are traceable.
create or replace function public.tg_audit_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into audit_log (actor_id, action, entity, entity_id, detail)
    values (auth.uid(), TG_ARGV[0], TG_TABLE_NAME, old.id::text,
            jsonb_build_object('owner', old.user_id));
    return old;
end;
$$;

drop trigger if exists audit_round_delete on course_rounds;
create trigger audit_round_delete after delete on course_rounds
    for each row execute function public.tg_audit_delete('round.deleted');

drop trigger if exists audit_shot_delete on shots;
create trigger audit_shot_delete after delete on shots
    for each row execute function public.tg_audit_delete('shot.deleted');


-- ####################################################################
-- ## 028_analytics_events.sql
-- ####################################################################
-- 028_analytics_events.sql
-- Product telemetry pipeline: clients append lightweight events (app_open,
-- shot_saved, round_completed, camera_failure, sim_connected, ...) with a small
-- JSONB `properties` bag. Powers retention, most-used-club, camera-quality, and
-- session dashboards without bloating the transactional tables.
--
-- Scale design:
--   • RANGE-partitioned by month so old telemetry is cheap to drop/archive and
--     queries prune to a few partitions (built for 100M+ rows).
--   • Clients can INSERT their own events but never SELECT — analytics is read via
--     service-role dashboards / the aggregate RPCs below. Keeps it privacy-safe.

create table if not exists analytics_events (
    id          bigint generated always as identity,
    user_id     uuid,                       -- nullable: pre-auth / guest events allowed
    event       text        not null,
    properties  jsonb       not null default '{}'::jsonb,
    session_id  uuid,
    app_version text,
    platform    text        not null default 'iOS',
    created_at  timestamptz not null default now(),
    primary key (id, created_at)
) partition by range (created_at);

-- Helper: ensure a month partition exists (id-safe, idempotent). Call from a
-- monthly pg_cron job; also invoked here to seed the current + next month.
create or replace function public.ensure_analytics_partition(p_month date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    start_d date := date_trunc('month', p_month)::date;
    end_d   date := (date_trunc('month', p_month) + interval '1 month')::date;
    pname   text := 'analytics_events_' || to_char(start_d, 'YYYYMM');
begin
    if not exists (select 1 from pg_class where relname = pname) then
        execute format(
            'create table %I partition of analytics_events for values from (%L) to (%L)',
            pname, start_d, end_d);
        execute format('create index if not exists %I on %I (event, created_at)',
            pname || '_event_idx', pname);
        execute format('create index if not exists %I on %I (user_id, created_at)',
            pname || '_user_idx', pname);
    end if;
end;
$$;
revoke execute on function public.ensure_analytics_partition(date) from public, anon, authenticated;

select public.ensure_analytics_partition(current_date);
select public.ensure_analytics_partition((current_date + interval '1 month')::date);

alter table analytics_events enable row level security;

-- Clients insert their own events (or anonymous events with null user_id).
-- No SELECT policy → the app can never read the telemetry firehose.
drop policy if exists "clients insert own events" on analytics_events;
create policy "clients insert own events" on analytics_events
    for insert to authenticated, anon
    with check (user_id is null or user_id = auth.uid());

-- Guard against event spam (per user, per minute) reusing the rate limiter.
create or replace function public.tg_rate_limit_analytics()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    perform public.enforce_rate_limit('analytics_event', 600, 60);
    return new;
end;
$$;
drop trigger if exists rl_analytics_events on analytics_events;
create trigger rl_analytics_events before insert on analytics_events
    for each row execute function public.tg_rate_limit_analytics();

-- ── Aggregate read models (service-role / admin dashboards) ─────────────────────
-- Daily active users + new users, last N days.
create or replace function public.analytics_retention(p_days int default 30)
returns table (day date, active_users bigint, events bigint)
language sql
security definer
set search_path = public
as $$
    select date_trunc('day', created_at)::date as day,
           count(distinct user_id)              as active_users,
           count(*)                             as events
    from analytics_events
    where created_at >= now() - make_interval(days => p_days)
    group by 1 order by 1;
$$;

-- Most-used clubs across the base (from shot_saved events' properties.club).
create or replace function public.analytics_top_clubs(p_days int default 30)
returns table (club text, shots bigint)
language sql
security definer
set search_path = public
as $$
    select properties->>'club' as club, count(*) as shots
    from analytics_events
    where event = 'shot_saved'
      and created_at >= now() - make_interval(days => p_days)
      and properties ? 'club'
    group by 1 order by 2 desc;
$$;

revoke execute on function public.analytics_retention(int)  from public, anon, authenticated;
revoke execute on function public.analytics_top_clubs(int)  from public, anon, authenticated;


-- ####################################################################
-- ## 029_scale_indexes_columns.sql
-- ####################################################################
-- 029_scale_indexes_columns.sql
-- Make the transactional tables perform at 1M users / 20M+ shots.
--
-- Two problems this fixes:
--   1) Postgres does NOT auto-index foreign keys. Every "load my shots/rounds",
--      friend lookup, and feed fan-out was a scan without these. Add covering
--      btree indexes on (user_id, <time>) and the FK columns.
--   2) Shot/round metrics live inside a JSONB `payload` (camelCase keys, written
--      by the app's payload encoder). Aggregate analytics over JSONB is slow, so
--      expose the hot fields as STORED generated columns + index them. A safe
--      immutable cast returns NULL instead of erroring on any legacy/dirty row,
--      so ADD COLUMN can't fail mid-rewrite.
--
-- NOTE: the generated columns rewrite the shots/course_rounds tables once. On a
-- large existing table run during low traffic (see SCALE_AND_SECURITY.md). Index
-- creation uses plain CREATE INDEX here for transactional apply; for a hot prod
-- table, create them CONCURRENTLY out-of-band instead.

-- ── Safe numeric cast for generated columns ────────────────────────────────────
create or replace function public.to_double_safe(t text)
returns double precision
language plpgsql
immutable
parallel safe
as $$
begin
    return t::double precision;
exception when others then
    return null;
end;
$$;

-- ── Foreign-key / query indexes ────────────────────────────────────────────────
create index if not exists shots_user_ts_idx          on shots (user_id, "timestamp" desc);
create index if not exists course_rounds_user_ts_idx  on course_rounds (user_id, started_at desc);
create index if not exists range_sessions_user_ts_idx on range_sessions (user_id, started_at desc);
create index if not exists sim_sessions_user_ts_idx   on sim_sessions (user_id, started_at desc);

create index if not exists feed_posts_user_ts_idx     on feed_posts (user_id, "timestamp" desc);
create index if not exists feed_posts_vis_ts_idx      on feed_posts (visibility, "timestamp" desc);
create index if not exists feed_reactions_post_idx    on feed_reactions (post_id);
create index if not exists feed_reactions_user_idx    on feed_reactions (user_id);
create index if not exists feed_comments_post_idx     on feed_comments (post_id);
create index if not exists feed_comments_user_idx     on feed_comments (user_id);

create index if not exists friendships_friend_idx     on friendships (friend_id);
create index if not exists friend_requests_to_idx     on friend_requests (to_user_id, status);
create index if not exists friend_requests_from_idx   on friend_requests (from_user_id);

create index if not exists clubs_user_idx             on clubs (user_id);
create index if not exists usage_counters_user_date   on usage_counters (user_id, date desc);
create index if not exists user_devices_user_idx      on user_devices (user_id);
create index if not exists round_attestations_round_idx on round_attestations (round_id);

-- ── Shots: hot metric columns from JSONB payload (camelCase keys) ──────────────
alter table shots add column if not exists club_name  text
    generated always as (payload->>'clubName') stored;
alter table shots add column if not exists shot_source text
    generated always as (payload->>'source') stored;
alter table shots add column if not exists carry_yards double precision
    generated always as (public.to_double_safe(payload->'metrics'->>'carryYards')) stored;
alter table shots add column if not exists total_yards double precision
    generated always as (public.to_double_safe(payload->'metrics'->>'totalYards')) stored;
alter table shots add column if not exists ball_speed_mph double precision
    generated always as (public.to_double_safe(payload->'metrics'->>'ballSpeedMph')) stored;
alter table shots add column if not exists club_speed_mph double precision
    generated always as (public.to_double_safe(payload->'metrics'->>'clubSpeedMph')) stored;

create index if not exists shots_club_idx        on shots (club_name);
create index if not exists shots_user_club_idx   on shots (user_id, club_name);
create index if not exists shots_carry_idx       on shots (carry_yards);

-- ── Course rounds: score/course columns for handicap & leaderboards ────────────
alter table course_rounds add column if not exists course_name text
    generated always as (payload->>'courseName') stored;
alter table course_rounds add column if not exists total_score int
    generated always as (public.to_double_safe(payload->'scoreSummary'->>'totalScore')::int) stored;
alter table course_rounds add column if not exists total_par int
    generated always as (public.to_double_safe(payload->'scoreSummary'->>'totalPar')::int) stored;

create index if not exists course_rounds_course_idx on course_rounds (course_name);


-- ####################################################################
-- ## 030_data_export.sql
-- ####################################################################
-- 030_data_export.sql
-- GDPR/CCPA "Export My Data": one RPC that returns the caller's complete data as a
-- single JSON document. Scoped strictly to auth.uid() so it can never leak another
-- user's data even though it's SECURITY DEFINER. The app calls this via PostgREST
-- RPC and offers the result as a downloadable/shareable file.

create or replace function public.export_my_data()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    uid uuid := auth.uid();
    result jsonb;
begin
    if uid is null then
        raise exception 'export_my_data requires an authenticated user';
    end if;

    -- Log the request (right-to-access is an auditable event).
    insert into audit_log (actor_id, action, entity, entity_id)
    values (uid, 'account.data_exported', 'auth.users', uid::text);

    select jsonb_build_object(
        'exported_at', now(),
        'user_id',     uid,
        'profile',     (select to_jsonb(p) from profiles p where p.user_id = uid),
        'entitlement', (select jsonb_build_object('tier', e.tier, 'payment_status', e.payment_status,
                                                  'current_period_end', e.current_period_end,
                                                  'cancel_at_period_end', e.cancel_at_period_end)
                        from user_entitlements e where e.user_id = uid),
        'clubs',       coalesce((select jsonb_agg(to_jsonb(c) order by c.sort_order) from clubs c where c.user_id = uid), '[]'::jsonb),
        'shots',       coalesce((select jsonb_agg(s.payload order by s."timestamp") from shots s where s.user_id = uid), '[]'::jsonb),
        'course_rounds', coalesce((select jsonb_agg(r.payload order by r.started_at) from course_rounds r where r.user_id = uid), '[]'::jsonb),
        'range_sessions', coalesce((select jsonb_agg(rs.payload order by rs.started_at) from range_sessions rs where rs.user_id = uid), '[]'::jsonb),
        'sim_sessions',   coalesce((select jsonb_agg(ss.payload order by ss.started_at) from sim_sessions ss where ss.user_id = uid), '[]'::jsonb),
        'feed_posts',  coalesce((select jsonb_agg(fp.payload order by fp."timestamp") from feed_posts fp where fp.user_id = uid), '[]'::jsonb),
        'devices',     coalesce((select jsonb_agg(to_jsonb(d)) from user_devices d where d.user_id = uid), '[]'::jsonb)
    ) into result;

    return result;
end;
$$;

revoke execute on function public.export_my_data() from public, anon;
grant  execute on function public.export_my_data() to authenticated;



-- ####################################################################
-- ## 031_live_sim_ack.sql
-- ####################################################################
-- Live-sim delivery guarantees: the sim records the highest shot sequence it
-- has received; the phone polls this to prune/resend unacknowledged shots.
alter table public.live_sim_state
  add column if not exists last_ack_seq bigint;


-- ####################################################################
-- ## 032_live_sim_round_summary.sql  (already applied via MCP 2026-07-04)
-- ####################################################################
alter table public.live_sim_state
  add column if not exists round_summary jsonb;


-- #### 033_security_hardening.sql (already applied via MCP 2026-07-05) ####
-- Security hardening from advisor sweep (2026-07-05).
-- Threat model note: live-sim pairing codes are 9-digit crypto-random and
-- displayed only on the host screen (Chromecast model). Enumeration is dead;
-- these policies harden storage hygiene, not the pairing model itself.

-- 1. ERROR: analytics partitions created without RLS (parent has it).
alter table if exists public.analytics_events_202607 enable row level security;
alter table if exists public.analytics_events_202608 enable row level security;

-- 2. Trigger functions must not be callable through PostgREST RPC.
revoke execute on function public.tg_audit_delete() from anon, authenticated;
revoke execute on function public.tg_audit_entitlement() from anon, authenticated;
revoke execute on function public.tg_rate_limit() from anon, authenticated;
revoke execute on function public.tg_rate_limit_analytics() from anon, authenticated;
revoke execute on function public.tg_rate_limit_storage() from anon, authenticated;

-- 3. live_sim_state: replace always-true INSERT/UPDATE with code-shape checks
--    and stamp freshness so the TTL sweep is trustworthy.
drop policy if exists "live sim state insert" on public.live_sim_state;
drop policy if exists "live sim state update" on public.live_sim_state;
create policy "live sim state insert" on public.live_sim_state
  for insert with check (code ~ '^[0-9]{6,10}$');
create policy "live sim state update" on public.live_sim_state
  for update using (true) with check (code ~ '^[0-9]{6,10}$');

-- 4. Pin the mutable search_path the linter flagged.
alter function public.to_double_safe(text) set search_path = '';

-- 5. TTL: pairing-state rows are ephemeral by design; sweep after 48h.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'live-sim-state-ttl',
      '17 * * * *',
      $sweep$ delete from public.live_sim_state where updated_at < now() - interval '48 hours' $sweep$
    );
  end if;
end $$;


-- #### 034_live_sim_rate_limit.sql (already applied via MCP 2026-07-06) ####
-- Rate-limit live_sim_state writes. The rl_* triggers cover authenticated
-- tables; live-sim rows are written by anon (sim + phone), so this keys the
-- shared rate_limits table on a uuid derived from the pairing code. Cap:
-- 400 writes/code/minute (legit traffic ~60/min).
create or replace function public.tg_rate_limit_livesim()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  k uuid := md5('livesim:' || new.code)::uuid;
  win timestamptz := date_trunc('minute', now());
  n int;
begin
  insert into public.rate_limits (user_id, action, window_start, count)
  values (k, 'livesim_write', win, 1)
  on conflict (user_id, action, window_start)
  do update set count = public.rate_limits.count + 1
  returning count into n;
  if n > 400 then
    raise exception 'rate limit exceeded for live sim session' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.tg_rate_limit_livesim() from anon, authenticated;

drop trigger if exists rl_live_sim_state on public.live_sim_state;
create trigger rl_live_sim_state
  before insert or update on public.live_sim_state
  for each row execute function public.tg_rate_limit_livesim();
