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
