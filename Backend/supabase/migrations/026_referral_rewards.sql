-- 026_referral_rewards.sql
-- Reward both sides with free Pro time when a new user redeems an invite code.
--
-- Comp Pro is ADDITIVE to Stripe: effective premium = active Stripe tier OR
-- comp_pro_until > now(). The Stripe webhook never touches comp_pro_until, so the
-- two never collide; when comp time lapses the user reverts automatically.

alter table user_entitlements
    add column if not exists comp_pro_until timestamptz;

-- Referral ledger. Each user can be a referee at most once (unique referee_id).
create table if not exists referrals (
    id           uuid primary key default gen_random_uuid(),
    referrer_id  uuid not null references auth.users(id) on delete cascade,
    referee_id   uuid not null references auth.users(id) on delete cascade,
    code         text not null,
    reward_days  int  not null default 14,
    created_at   timestamptz not null default now(),
    unique (referee_id)
);
create index if not exists referrals_referrer_idx on referrals (referrer_id);

alter table referrals enable row level security;
drop policy if exists "users read own referrals" on referrals;
create policy "users read own referrals" on referrals for select to authenticated
    using ((select auth.uid()) = referrer_id or (select auth.uid()) = referee_id);
-- No INSERT policy: rows are written only by redeem_invite() (SECURITY DEFINER).

-- redeem_invite now returns jsonb (reward result), so drop the void version first.
drop function if exists public.redeem_invite(text);

create function public.redeem_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_uid         uuid := auth.uid();
    v_owner       uuid;
    v_reward_days constant int := 14;
    v_referrer_cap constant int := 5;   -- max rewarded referrals per referrer
    v_already_referred boolean;
    v_referrer_count   int;
    v_reward_referrer  boolean := false;
begin
    if v_uid is null then
        raise exception 'redeem_invite requires an authenticated user';
    end if;

    select user_id into v_owner from invite_codes where code = p_code;
    if not found then
        raise exception 'Invite code not found';
    end if;
    if v_owner = v_uid then
        return jsonb_build_object('granted', false, 'reason', 'self', 'reward_days', 0);
    end if;

    -- Reciprocal friendship (original behavior, idempotent).
    insert into friendships (user_id, friend_id) values (v_owner, v_uid)
        on conflict (user_id, friend_id) do nothing;
    insert into friendships (user_id, friend_id) values (v_uid, v_owner)
        on conflict (user_id, friend_id) do nothing;

    -- Reward only the first time this user is referred.
    select exists(select 1 from referrals where referee_id = v_uid) into v_already_referred;
    if v_already_referred then
        return jsonb_build_object('granted', false, 'reason', 'already_referred', 'reward_days', 0);
    end if;

    insert into referrals (referrer_id, referee_id, code, reward_days)
    values (v_owner, v_uid, p_code, v_reward_days);

    -- Grant comp Pro to the new user (always) via upsert on their entitlement.
    insert into user_entitlements (user_id, comp_pro_until)
    values (v_uid, now() + make_interval(days => v_reward_days))
    on conflict (user_id) do update
        set comp_pro_until = greatest(coalesce(user_entitlements.comp_pro_until, now()), now())
                             + make_interval(days => v_reward_days);

    -- Reward the referrer too, up to the cap.
    select count(*) into v_referrer_count from referrals where referrer_id = v_owner;
    v_reward_referrer := v_referrer_count <= v_referrer_cap;
    if v_reward_referrer then
        insert into user_entitlements (user_id, comp_pro_until)
        values (v_owner, now() + make_interval(days => v_reward_days))
        on conflict (user_id) do update
            set comp_pro_until = greatest(coalesce(user_entitlements.comp_pro_until, now()), now())
                                 + make_interval(days => v_reward_days);
    end if;

    return jsonb_build_object(
        'granted', true,
        'reward_days', v_reward_days,
        'referrer_rewarded', v_reward_referrer
    );
end;
$$;

revoke execute on function public.redeem_invite(text) from public, anon;
grant  execute on function public.redeem_invite(text) to authenticated;
