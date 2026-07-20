-- ============================================================================
-- 042_founder_dashboard_metrics.sql
-- Read-only aggregate functions powering the internal Founders' Dashboard
-- (separate app: truecarry-founders-dashboard). All are SECURITY DEFINER so
-- they can read auth.users + all users' rows, and are locked to service_role
-- ONLY — EXECUTE is revoked from public/anon/authenticated (this project's
-- default privileges auto-grant EXECUTE to anon, so the revokes are required).
-- Nothing here writes data.
-- ============================================================================

-- ---- Top-line KPIs (single JSON blob) --------------------------------------
create or replace function public.founder_kpis()
returns json
language sql
security definer
set search_path = public, auth
as $$
  select json_build_object(
    'total_users',          (select count(*) from auth.users),
    'new_users_7d',         (select count(*) from auth.users where created_at >= now() - interval '7 days'),
    'new_users_prev_7d',    (select count(*) from auth.users where created_at >= now() - interval '14 days' and created_at < now() - interval '7 days'),
    'new_users_30d',        (select count(*) from auth.users where created_at >= now() - interval '30 days'),
    'onboarded',            (select count(*) from profiles where onboarding_completed),
    'paid_active',          (select count(*) from user_entitlements where payment_status = 'active' and tier <> 'free'),
    'comp_pro_active',      (select count(*) from user_entitlements where comp_pro_until > now()),
    'cancel_at_period_end', (select count(*) from user_entitlements where cancel_at_period_end),
    'past_due',             (select count(*) from user_entitlements where payment_status in ('past_due','unpaid','incomplete')),
    'total_shots',          (select count(*) from shots),
    'total_rounds',         (select count(*) from course_rounds),
    'total_range_sessions', (select count(*) from range_sessions),
    'total_sim_sessions',   (select count(*) from sim_sessions),
    'total_referrals',      (select count(*) from referrals),
    'invite_codes',         (select count(*) from invite_codes),
    'friendships',          (select count(*) from friendships),
    'feed_posts',           (select count(*) from feed_posts),
    'challenge_entries',    (select count(*) from challenge_entries),
    'attestations',         (select count(*) from round_attestations),
    'dau',                  (select count(distinct user_id) from analytics_events where created_at >= now() - interval '1 day'  and user_id is not null),
    'wau',                  (select count(distinct user_id) from analytics_events where created_at >= now() - interval '7 days' and user_id is not null),
    'mau',                  (select count(distinct user_id) from analytics_events where created_at >= now() - interval '30 days' and user_id is not null),
    'events_24h',           (select count(*) from analytics_events where created_at >= now() - interval '1 day'),
    'crashes_24h',          (select count(*) from analytics_events where event = 'client_crash' and created_at >= now() - interval '1 day'),
    'crashes_7d',           (select count(*) from analytics_events where event = 'client_crash' and created_at >= now() - interval '7 days')
  );
$$;

-- ---- Signups per day (fills gaps) ------------------------------------------
create or replace function public.founder_signups_by_day(p_days int default 30)
returns table(day date, signups bigint)
language sql
security definer
set search_path = public, auth
as $$
  select d::date as day, count(u.id) as signups
  from generate_series(current_date - (least(p_days,180) - 1), current_date, interval '1 day') d
  left join auth.users u on u.created_at::date = d::date
  group by d order by d;
$$;

-- ---- All users, with joined stats (search + paginate) ----------------------
create or replace function public.founder_users(
  p_search text default null,
  p_limit  int  default 100,
  p_offset int  default 0
)
returns table(
  user_id uuid, email text, display_name text, username text,
  tier text, payment_status text, comp_pro_until timestamptz,
  cancel_at_period_end boolean, created_at timestamptz, onboarding_completed boolean,
  last_seen_at timestamptz, platform text, app_version text,
  device_count bigint, shots bigint, rounds bigint
)
language sql
security definer
set search_path = public, auth
as $$
  select u.id, u.email::text, p.display_name, p.username,
    e.tier, e.payment_status, e.comp_pro_until, e.cancel_at_period_end,
    u.created_at, p.onboarding_completed,
    d.last_seen_at, d.platform, d.app_version, coalesce(d.device_count, 0),
    coalesce(s.c, 0), coalesce(r.c, 0)
  from auth.users u
  left join profiles p on p.user_id = u.id
  left join user_entitlements e on e.user_id = u.id
  left join lateral (
    select count(*) as device_count, max(last_seen_at) as last_seen_at,
      (array_agg(platform order by last_seen_at desc))[1] as platform,
      (array_agg(app_version order by last_seen_at desc))[1] as app_version
    from user_devices ud where ud.user_id = u.id
  ) d on true
  left join lateral (select count(*) c from shots where user_id = u.id) s on true
  left join lateral (select count(*) c from course_rounds where user_id = u.id) r on true
  where p_search is null or p_search = ''
     or u.email ilike '%' || p_search || '%'
     or p.display_name ilike '%' || p_search || '%'
     or p.username ilike '%' || p_search || '%'
  order by u.created_at desc
  limit least(p_limit, 500) offset greatest(p_offset, 0);
$$;

create or replace function public.founder_users_count(p_search text default null)
returns bigint
language sql
security definer
set search_path = public, auth
as $$
  select count(*)
  from auth.users u
  left join profiles p on p.user_id = u.id
  where p_search is null or p_search = ''
     or u.email ilike '%' || p_search || '%'
     or p.display_name ilike '%' || p_search || '%'
     or p.username ilike '%' || p_search || '%';
$$;

-- ---- One user, everything (drill-down) -------------------------------------
create or replace function public.founder_user_detail(p_uid uuid)
returns json
language sql
security definer
set search_path = public, auth
as $$
  select json_build_object(
    'user', (select json_build_object('id', u.id, 'email', u.email,
        'created_at', u.created_at, 'last_sign_in_at', u.last_sign_in_at,
        'email_confirmed_at', u.email_confirmed_at)
      from auth.users u where u.id = p_uid),
    'profile', (select to_json(p) from profiles p where p.user_id = p_uid),
    'entitlement', (select to_json(e) from user_entitlements e where e.user_id = p_uid),
    'devices', (select coalesce(json_agg(to_json(d) order by d.last_seen_at desc), '[]')
      from user_devices d where d.user_id = p_uid),
    'counts', json_build_object(
      'shots',             (select count(*) from shots where user_id = p_uid),
      'rounds',            (select count(*) from course_rounds where user_id = p_uid),
      'range_sessions',    (select count(*) from range_sessions where user_id = p_uid),
      'sim_sessions',      (select count(*) from sim_sessions where user_id = p_uid),
      'challenge_entries', (select count(*) from challenge_entries where user_id = p_uid),
      'friends',           (select count(*) from friendships where user_id = p_uid),
      'clubs',             (select count(*) from clubs where user_id = p_uid and is_active)
    ),
    'referrals_made', (select count(*) from referrals where referrer_id = p_uid),
    'referred_by', (select json_build_object('code', code, 'created_at', created_at)
      from referrals where referee_id = p_uid),
    'invite_code', (select code from invite_codes where user_id = p_uid limit 1),
    'recent_shots', (select coalesce(json_agg(json_build_object(
        'club', club_name, 'carry', carry_yards, 'ts', ts) order by ts desc), '[]')
      from (select club_name, carry_yards, "timestamp" as ts from shots
            where user_id = p_uid order by "timestamp" desc limit 15) sx),
    'audit', (select coalesce(json_agg(json_build_object(
        'action', action, 'detail', detail, 'at', occurred_at) order by occurred_at desc), '[]')
      from (select action, detail, occurred_at from audit_log
            where actor_id = p_uid or entity_id = p_uid::text
            order by occurred_at desc limit 25) ax)
  );
$$;

-- ---- Subscription tier / status distribution -------------------------------
create or replace function public.founder_tier_distribution()
returns table(tier text, payment_status text, count bigint)
language sql
security definer
set search_path = public
as $$
  select tier, payment_status, count(*)::bigint
  from user_entitlements group by tier, payment_status order by count(*) desc;
$$;

-- ---- Referrals -------------------------------------------------------------
create or replace function public.founder_top_referrers(p_limit int default 25)
returns table(referrer_id uuid, email text, display_name text,
  referrals bigint, reward_days_total bigint, last_referral timestamptz)
language sql
security definer
set search_path = public, auth
as $$
  select r.referrer_id, u.email::text, p.display_name,
    count(*)::bigint, sum(r.reward_days)::bigint, max(r.created_at)
  from referrals r
  left join auth.users u on u.id = r.referrer_id
  left join profiles p on p.user_id = r.referrer_id
  group by r.referrer_id, u.email, p.display_name
  order by count(*) desc limit p_limit;
$$;

create or replace function public.founder_referrals_by_day(p_days int default 30)
returns table(day date, referrals bigint)
language sql
security definer
set search_path = public
as $$
  select d::date as day, count(r.id) as referrals
  from generate_series(current_date - (least(p_days,180) - 1), current_date, interval '1 day') d
  left join referrals r on r.created_at::date = d::date
  group by d order by d;
$$;

-- ---- Engagement ------------------------------------------------------------
create or replace function public.founder_shots_by_day(p_days int default 30)
returns table(day date, shots bigint)
language sql
security definer
set search_path = public
as $$
  select d::date as day, count(s.id) as shots
  from generate_series(current_date - (least(p_days,180) - 1), current_date, interval '1 day') d
  left join shots s on s."timestamp"::date = d::date
  group by d order by d;
$$;

create or replace function public.founder_top_clubs(p_limit int default 12)
returns table(club text, shots bigint, avg_carry numeric)
language sql
security definer
set search_path = public
as $$
  select coalesce(nullif(club_name, ''), 'Unknown') as club,
    count(*)::bigint, round(avg(carry_yards)::numeric, 1)
  from shots
  group by coalesce(nullif(club_name, ''), 'Unknown')
  order by count(*) desc limit p_limit;
$$;

create or replace function public.founder_shot_source_mix()
returns table(source text, shots bigint)
language sql
security definer
set search_path = public
as $$
  select coalesce(nullif(shot_source, ''), 'unknown') as source, count(*)::bigint
  from shots group by coalesce(nullif(shot_source, ''), 'unknown') order by count(*) desc;
$$;

create or replace function public.founder_challenge_participation(p_weeks int default 8)
returns table(week_start date, participants bigint, entries bigint)
language sql
security definer
set search_path = public
as $$
  select week_start, count(distinct user_id)::bigint, count(*)::bigint
  from challenge_entries
  where week_start >= current_date - (least(p_weeks,52) * 7)
  group by week_start order by week_start;
$$;

-- ---- Observability ---------------------------------------------------------
create or replace function public.founder_events_by_day(p_days int default 14)
returns table(day date, event text, count bigint)
language sql
security definer
set search_path = public
as $$
  select created_at::date as day, event, count(*)::bigint
  from analytics_events
  where created_at >= current_date - (least(p_days,90) - 1)
  group by created_at::date, event order by day;
$$;

create or replace function public.founder_event_totals(p_days int default 30)
returns table(event text, count bigint)
language sql
security definer
set search_path = public
as $$
  select event, count(*)::bigint from analytics_events
  where created_at >= now() - (least(p_days,365) || ' days')::interval
  group by event order by count(*) desc;
$$;

create or replace function public.founder_crashes_by_version(p_days int default 30)
returns table(app_version text, platform text, crashes bigint)
language sql
security definer
set search_path = public
as $$
  select coalesce(nullif(app_version, ''), 'unknown'), platform, count(*)::bigint
  from analytics_events
  where event = 'client_crash' and created_at >= now() - (least(p_days,365) || ' days')::interval
  group by coalesce(nullif(app_version, ''), 'unknown'), platform
  order by count(*) desc;
$$;

create or replace function public.founder_version_adoption()
returns table(app_version text, platform text, devices bigint, last_seen timestamptz)
language sql
security definer
set search_path = public
as $$
  select coalesce(nullif(app_version, ''), 'unknown'), platform,
    count(*)::bigint, max(last_seen_at)
  from user_devices where is_active
  group by coalesce(nullif(app_version, ''), 'unknown'), platform
  order by count(*) desc;
$$;

create or replace function public.founder_platform_mix(p_days int default 30)
returns table(platform text, events bigint, users bigint)
language sql
security definer
set search_path = public
as $$
  select platform, count(*)::bigint, count(distinct user_id)::bigint
  from analytics_events
  where created_at >= now() - (least(p_days,365) || ' days')::interval
  group by platform order by count(*) desc;
$$;

create or replace function public.founder_audit_recent(p_limit int default 60)
returns table(occurred_at timestamptz, actor_id uuid, actor_email text,
  action text, entity text, entity_id text, detail jsonb)
language sql
security definer
set search_path = public, auth
as $$
  select a.occurred_at, a.actor_id, u.email::text, a.action, a.entity, a.entity_id, a.detail
  from audit_log a
  left join auth.users u on u.id = a.actor_id
  order by a.occurred_at desc limit least(p_limit, 300);
$$;

create or replace function public.founder_rate_limit_hotspots()
returns table(action text, users bigint, total bigint)
language sql
security definer
set search_path = public
as $$
  select action, count(distinct user_id)::bigint, sum(count)::bigint
  from rate_limits group by action order by sum(count) desc;
$$;

-- ---- Lock everything down to service_role only -----------------------------
do $$
declare fn text;
begin
  for fn in
    select p.oid::regprocedure::text
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'founder\_%'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', fn);
    execute format('grant execute on function %s to service_role', fn);
  end loop;
end $$;
