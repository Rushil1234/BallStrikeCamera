-- ============================================================================
-- 044_founder_reconciliation_and_funnel.sql   (APPLIED 2026-07-19)
-- Two more read-only founders'-dashboard RPCs. Same rules as 042: SECURITY
-- DEFINER, EXECUTE revoked from anon/authenticated, granted only to service_role.
-- ============================================================================

-- Active/comped entitlements, for reconciling against live Stripe subscriptions
-- (surfaces "charged but not unlocked" and "entitled with no Stripe sub").
create or replace function public.founder_active_entitlements()
returns table(
  user_id uuid, email text, tier text, payment_status text,
  stripe_customer_id text, stripe_subscription_id text,
  comp_pro_until timestamptz, current_period_end timestamptz
)
language sql
security definer
set search_path = public, auth
as $$
  select e.user_id, u.email::text, e.tier, e.payment_status,
    e.stripe_customer_id, e.stripe_subscription_id, e.comp_pro_until, e.current_period_end
  from user_entitlements e
  left join auth.users u on u.id = e.user_id
  where (e.payment_status in ('active','trialing') and e.tier <> 'free')
     or e.comp_pro_until > now();
$$;

-- Activation funnel: signup -> onboarded -> first shot -> first round -> paid.
create or replace function public.founder_activation_funnel()
returns table(step text, ord int, users bigint, pct numeric)
language sql
security definer
set search_path = public, auth
as $$
  with total as (select greatest(count(*),1)::numeric as n from auth.users),
  steps as (
    select 'Signed up'      as step, 1 as ord, (select count(*) from auth.users) as users
    union all
    select 'Onboarded',      2, (select count(*) from profiles where onboarding_completed)
    union all
    select 'Took a shot',    3, (select count(distinct user_id) from shots)
    union all
    select 'Played a round', 4, (select count(distinct user_id) from course_rounds)
    union all
    select 'Paid or comped', 5, (select count(*) from user_entitlements
                                  where (payment_status in ('active','trialing') and tier <> 'free')
                                     or comp_pro_until > now())
  )
  select s.step, s.ord, s.users::bigint,
         round(s.users * 100.0 / (select n from total), 1) as pct
  from steps s order by s.ord;
$$;

revoke all on function public.founder_active_entitlements() from public, anon, authenticated;
grant execute on function public.founder_active_entitlements() to service_role;
revoke all on function public.founder_activation_funnel() from public, anon, authenticated;
grant execute on function public.founder_activation_funnel() to service_role;
