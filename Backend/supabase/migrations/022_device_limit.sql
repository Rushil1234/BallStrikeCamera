-- 022_device_limit.sql
-- Cap each account at 2 active devices to deter login sharing.
--
-- Enforcement lives in register_device() (SECURITY DEFINER): it is the ONLY way
-- to add a device row. Direct INSERT is removed from the users' RLS so the cap
-- can't be bypassed by writing to the table directly. Users can still read and
-- DELETE their own device rows (removing one frees a slot).

-- One row per (user, device) so re-registration updates instead of duplicating,
-- and dupes can't inflate the active-device count.
create unique index if not exists user_devices_user_token_uniq
    on user_devices (user_id, device_token);

alter table user_devices enable row level security;

-- Replace the broad "for all" policy (which allowed direct INSERT) with granular
-- read / update / delete policies. No INSERT policy: inserts go through the RPC.
drop policy if exists "users manage own devices" on user_devices;

create policy "users read own devices"
    on user_devices for select to authenticated
    using ((select auth.uid()) = user_id);

create policy "users update own devices"
    on user_devices for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

create policy "users delete own devices"
    on user_devices for delete to authenticated
    using ((select auth.uid()) = user_id);

-- Register (or refresh) the caller's device, enforcing a 2-device cap.
-- Returns { allowed, device_count, max_devices }. allowed=false means the
-- account is already at its limit and the device was NOT added.
create or replace function public.register_device(
    p_device_token text,
    p_device_name  text default '',
    p_platform     text default 'iOS',
    p_app_version  text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    uid uuid := auth.uid();
    max_devices constant int := 2;
    existing_id uuid;
    active_count int;
begin
    if uid is null then
        raise exception 'register_device requires an authenticated user';
    end if;
    if coalesce(p_device_token, '') = '' then
        raise exception 'register_device requires a device token';
    end if;

    -- Known device → refresh it (always allowed).
    select id into existing_id
    from user_devices
    where user_id = uid and device_token = p_device_token;

    if existing_id is not null then
        update user_devices
        set last_seen_at = now(),
            is_active    = true,
            device_name  = coalesce(nullif(p_device_name, ''), device_name),
            app_version  = coalesce(nullif(p_app_version, ''), app_version),
            platform     = coalesce(nullif(p_platform, ''), platform)
        where id = existing_id;

        select count(*) into active_count from user_devices where user_id = uid and is_active;
        return jsonb_build_object('allowed', true, 'device_count', active_count, 'max_devices', max_devices);
    end if;

    -- New device → only if under the cap.
    select count(*) into active_count from user_devices where user_id = uid and is_active;
    if active_count >= max_devices then
        return jsonb_build_object('allowed', false, 'device_count', active_count, 'max_devices', max_devices);
    end if;

    insert into user_devices (user_id, device_token, device_name, platform, app_version, is_active)
    values (uid, p_device_token, coalesce(p_device_name, ''),
            coalesce(nullif(p_platform, ''), 'iOS'), coalesce(p_app_version, ''), true);

    return jsonb_build_object('allowed', true, 'device_count', active_count + 1, 'max_devices', max_devices);
end;
$$;

revoke execute on function public.register_device(text, text, text, text) from public, anon;
grant  execute on function public.register_device(text, text, text, text) to authenticated;
