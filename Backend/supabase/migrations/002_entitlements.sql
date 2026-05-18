-- 002_entitlements.sql
-- True Carry — subscription entitlements & usage tracking

-- ── User Entitlements ─────────────────────────────────────────────────────────
create table if not exists user_entitlements (
    id                      uuid primary key default uuid_generate_v4(),
    user_id                 uuid not null references auth.users(id) on delete cascade,
    tier                    text not null default 'free',     -- free|basic|pro|unlimited
    payment_status          text not null default 'inactive', -- inactive|trialing|active|past_due|canceled|unpaid|incomplete
    stripe_customer_id      text,
    stripe_subscription_id  text,
    current_period_start    timestamptz,
    current_period_end      timestamptz,
    cancel_at_period_end    boolean not null default false,
    updated_at              timestamptz not null default now(),
    unique(user_id)
);

-- Insert free-tier entitlement on new user signup (trigger)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
    insert into public.user_entitlements (user_id, tier, payment_status)
    values (new.id, 'free', 'inactive')
    on conflict (user_id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_user();

-- ── Usage Counters ────────────────────────────────────────────────────────────
create table if not exists usage_counters (
    id           uuid primary key default uuid_generate_v4(),
    user_id      uuid not null references auth.users(id) on delete cascade,
    date         date not null default current_date,
    range_shots  int  not null default 0,
    sim_shots    int  not null default 0,
    course_rounds int not null default 0,
    unique(user_id, date)
);

-- ── Increment Usage RPC ───────────────────────────────────────────────────────
create or replace function public.increment_usage(
    p_user_id uuid,
    p_action  text
)
returns void language plpgsql security definer as $$
begin
    insert into public.usage_counters (user_id, date)
    values (p_user_id, current_date)
    on conflict (user_id, date) do nothing;

    if p_action = 'range_shot' then
        update public.usage_counters
        set range_shots = range_shots + 1
        where user_id = p_user_id and date = current_date;
    elsif p_action = 'sim_shot' then
        update public.usage_counters
        set sim_shots = sim_shots + 1
        where user_id = p_user_id and date = current_date;
    elsif p_action = 'course_round' then
        update public.usage_counters
        set course_rounds = course_rounds + 1
        where user_id = p_user_id and date = current_date;
    end if;
end;
$$;

-- ── Device Registrations ──────────────────────────────────────────────────────
create table if not exists user_devices (
    id            uuid primary key default uuid_generate_v4(),
    user_id       uuid not null references auth.users(id) on delete cascade,
    device_token  text not null,     -- identifierForVendor
    device_name   text not null,
    platform      text not null default 'iOS',
    app_version   text not null default '',
    registered_at timestamptz not null default now(),
    last_seen_at  timestamptz not null default now(),
    is_active     boolean not null default true
);
