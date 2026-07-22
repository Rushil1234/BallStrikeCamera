-- Security hardening from the Supabase linter (2026-07-21). Safe, no behavior change:
--
-- 1. Pin search_path on two functions that had a mutable one (search-path injection
--    hardening). ALTER only — function bodies are untouched.
-- 2. Revoke EXECUTE from PUBLIC on the trigger functions. Trigger functions fire as
--    the table owner when their trigger fires REGARDLESS of EXECUTE grants, so this
--    does NOT affect any trigger — it only removes the ability for anon/authenticated
--    to invoke them directly over `/rest/v1/rpc/...`, which was never intended.
-- 3. Revoke anon EXECUTE on the follow-graph client RPCs. These are iOS-only, require
--    auth.uid(), and are never referenced inside an RLS policy (unlike is_follower /
--    is_friend / profile_is_private, which the feed policy evaluates as the querying
--    role and are therefore deliberately left alone so anonymous web reads don't break).

-- 1. Mutable search_path -> pinned
alter function public.search_courses(q text, lat double precision, lon double precision, only_geometry boolean, lim integer)
  set search_path = public;
alter function public.tg_live_sim_guard() set search_path = public;

-- 2. Trigger functions must not be directly callable as RPCs
revoke execute on function public.tg_live_sim_guard() from public;
revoke execute on function public.tg_audit_delete() from public;
revoke execute on function public.tg_audit_entitlement() from public;
revoke execute on function public.tg_rate_limit() from public;
revoke execute on function public.tg_rate_limit_analytics() from public;
revoke execute on function public.tg_rate_limit_livesim() from public;
revoke execute on function public.tg_rate_limit_storage() from public;

-- 3. Follow-graph client RPCs: keep authenticated, drop anon
revoke execute on function public.follow_user(uuid) from anon;
revoke execute on function public.unfollow_user(uuid) from anon;
revoke execute on function public.follow_list(uuid, boolean) from anon;
revoke execute on function public.incoming_follow_requests() from anon;
revoke execute on function public.profile_social(uuid) from anon;
revoke execute on function public.set_profile_privacy(boolean) from anon;
revoke execute on function public.respond_follow_request(uuid, boolean) from anon;
