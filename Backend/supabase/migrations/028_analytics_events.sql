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
