-- ============================================================================
-- 045_activation_funnel_v2.sql   (APPLIED 2026-07-19)
--
-- v1 of the funnel was misleading in two ways:
--   1. It counted synthetic @example.com test accounts as "signups" that never
--      activated, inflating the drop-off.
--   2. It jumped straight from "Signed up" to "Onboarded", which hid WHERE the
--      loss happens.
--
-- v2 excludes test accounts and splits out "Signed in" vs "Opened the app".
-- A user who signs up on the WEB and never launches the iOS app has zero
-- user_devices rows AND zero analytics_events (not even app_open) — that is a
-- completely different problem from someone abandoning onboarding.
--
-- First run of v2 (2026-07-19), 4 real users:
--   Signed up 4 (100%) -> Signed in 4 (100%) -> Opened the app 2 (50%)
--   -> Onboarded 2 -> Took a shot 2 -> Played a round 2 -> Paid/comped 2
-- i.e. ONE leak: everyone signs in, half never open the app, and 100% of those
-- who do open it convert all the way through. Corroborates the iOS Google
-- sign-in bug (see [[live-sim-pairing-security]] sibling note in memory).
-- ============================================================================
create or replace function public.founder_activation_funnel()
returns table(step text, ord int, users bigint, pct numeric)
language sql
security definer
set search_path = public, auth
as $$
  with real_users as (
    select id from auth.users where email not like '%@example.com'
  ),
  total as (select greatest(count(*),1)::numeric as n from real_users),
  steps as (
    select 'Signed up' as step, 1 as ord, (select count(*) from real_users) as users
    union all
    select 'Signed in', 2, (
      select count(*) from auth.users u join real_users r on r.id = u.id
      where u.last_sign_in_at is not null)
    union all
    select 'Opened the app', 3, (
      select count(*) from real_users r
      where exists (select 1 from user_devices d where d.user_id = r.id)
         or exists (select 1 from analytics_events e where e.user_id = r.id))
    union all
    select 'Onboarded', 4, (
      select count(*) from profiles p join real_users r on r.id = p.user_id
      where p.onboarding_completed)
    union all
    select 'Took a shot', 5, (
      select count(distinct s.user_id) from shots s join real_users r on r.id = s.user_id)
    union all
    select 'Played a round', 6, (
      select count(distinct c.user_id) from course_rounds c join real_users r on r.id = c.user_id)
    union all
    select 'Paid or comped', 7, (
      select count(*) from user_entitlements e join real_users r on r.id = e.user_id
      where (e.payment_status in ('active','trialing') and e.tier <> 'free')
         or e.comp_pro_until > now())
  )
  select s.step, s.ord, s.users::bigint,
         round(s.users * 100.0 / (select n from total), 1) as pct
  from steps s order by s.ord;
$$;

revoke all on function public.founder_activation_funnel() from public, anon, authenticated;
grant execute on function public.founder_activation_funnel() to service_role;
