-- 011_social_feed_revoke_anon.sql
-- Restrict the social RPCs added in 010 to signed-in users only.
-- Postgres grants EXECUTE to PUBLIC by default (which includes the `anon`
-- role); the explicit grants in 010 were additive, so revoke the rest.

revoke execute on function public.search_users(text)          from public, anon;
revoke execute on function public.list_friends()              from public, anon;
revoke execute on function public.list_incoming_requests()    from public, anon;
revoke execute on function public.accept_friend_request(uuid) from public, anon;
revoke execute on function public.redeem_invite(text)         from public, anon;
