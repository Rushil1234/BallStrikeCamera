-- 020_security_hardening.sql
-- Security hardening. Idempotent.
--
-- 1) increment_usage() trusted a caller-supplied p_user_id and (because EXECUTE
--    defaults to PUBLIC) was callable by anon. Combined with search_users()
--    leaking other users' UUIDs, an attacker could inflate any victim's daily
--    usage counters (IDOR / quota exhaustion). Pin all writes to auth.uid() and
--    restrict execution to authenticated users.
-- 2) The profiles UPDATE policy had no WITH CHECK, so a row could be updated to
--    set user_id to another value. Add a matching WITH CHECK.

-- ── 1) Harden increment_usage ───────────────────────────────────────────────────
-- Keep the (p_user_id, p_action) signature so the existing PostgREST RPC call
-- from the app keeps working, but ignore p_user_id and act only on the caller.
create or replace function public.increment_usage(
    p_user_id uuid,
    p_action  text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    uid uuid := auth.uid();
begin
    -- Anonymous callers (no JWT) must not be able to touch any counters.
    if uid is null then
        raise exception 'increment_usage requires an authenticated user';
    end if;

    insert into public.usage_counters (user_id, date)
    values (uid, current_date)
    on conflict (user_id, date) do nothing;

    if p_action = 'range_shot' then
        update public.usage_counters
        set range_shots = range_shots + 1
        where user_id = uid and date = current_date;
    elsif p_action = 'sim_shot' then
        update public.usage_counters
        set sim_shots = sim_shots + 1
        where user_id = uid and date = current_date;
    elsif p_action = 'course_round' then
        update public.usage_counters
        set course_rounds = course_rounds + 1
        where user_id = uid and date = current_date;
    else
        raise exception 'increment_usage: unknown action %', p_action;
    end if;
end;
$$;

revoke execute on function public.increment_usage(uuid, text) from public, anon;
grant  execute on function public.increment_usage(uuid, text) to authenticated;

-- ── 2) Add WITH CHECK to the profiles UPDATE policy ─────────────────────────────
drop policy if exists "users can update own profile" on profiles;
create policy "users can update own profile"
    on profiles for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);
