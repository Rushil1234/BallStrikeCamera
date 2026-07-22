-- Fix 055: the `revoke execute ... from anon` statements were no-ops. Postgres grants
-- EXECUTE to PUBLIC by default at function creation, and `anon` is a member of PUBLIC, so
-- to actually remove anon's access you must revoke from PUBLIC (not from anon directly).
-- authenticated + service_role keep their EXPLICIT grants from migrations 053/054, so the
-- iOS app is unaffected.
--
-- Only the pure client RPCs (require auth.uid(), never referenced inside an RLS policy) are
-- revoked here. is_follower / is_friend / profile_is_private / shares_home_course /
-- golfers_at_home_course are deliberately left on PUBLIC because the feed_posts / shots RLS
-- policies evaluate them AS the querying role, including anonymous web reads.

revoke execute on function public.follow_user(uuid) from public;
revoke execute on function public.unfollow_user(uuid) from public;
revoke execute on function public.follow_list(uuid, boolean) from public;
revoke execute on function public.incoming_follow_requests() from public;
revoke execute on function public.profile_social(uuid) from public;
revoke execute on function public.set_profile_privacy(boolean) from public;
revoke execute on function public.respond_follow_request(uuid, boolean) from public;

-- Re-assert the intended grants (idempotent; guards against the revoke above removing a
-- grant these roles rely on).
grant execute on function public.follow_user(uuid) to authenticated, service_role;
grant execute on function public.unfollow_user(uuid) to authenticated, service_role;
grant execute on function public.follow_list(uuid, boolean) to authenticated, service_role;
grant execute on function public.incoming_follow_requests() to authenticated, service_role;
grant execute on function public.profile_social(uuid) to authenticated, service_role;
grant execute on function public.set_profile_privacy(boolean) to authenticated, service_role;
grant execute on function public.respond_follow_request(uuid, boolean) to authenticated, service_role;
