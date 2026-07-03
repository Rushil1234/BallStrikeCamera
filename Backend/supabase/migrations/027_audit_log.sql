-- 027_audit_log.sql
-- Security/audit trail for the events that matter when something goes wrong or a
-- dispute/chargeback/abuse report comes in: subscription changes, deletions of
-- user content, and account deletions. Append-only; readable only by service role.
--
-- Auth events (failed logins, password resets, signups) are already captured in
-- Supabase's auth audit log — this table covers the *application* layer.

create table if not exists audit_log (
    id          bigint generated always as identity primary key,
    occurred_at timestamptz not null default now(),
    actor_id    uuid,                    -- auth.uid() of whoever caused it (null for system/service)
    action      text not null,           -- e.g. 'entitlement.changed', 'round.deleted', 'account.deleted'
    entity      text,                    -- table/domain the action touched
    entity_id   text,                    -- pk of the affected row
    detail      jsonb not null default '{}'::jsonb
);

create index if not exists audit_log_occurred_idx on audit_log (occurred_at desc);
create index if not exists audit_log_action_idx   on audit_log (action, occurred_at desc);
create index if not exists audit_log_actor_idx    on audit_log (actor_id, occurred_at desc);

alter table audit_log enable row level security;
-- No policies → no anon/authenticated access. Only service role (dashboards, admin
-- tooling, edge functions) and SECURITY DEFINER writers below can touch it.

-- Central writer. SECURITY DEFINER so triggers running as an unprivileged user can
-- still append. Callable by authenticated users so edge functions / RPCs can log
-- app-level events (e.g. account deletion), but they can only WRITE, never read.
create or replace function public.write_audit(
    p_action    text,
    p_entity    text default null,
    p_entity_id text default null,
    p_detail    jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into audit_log (actor_id, action, entity, entity_id, detail)
    values (auth.uid(), p_action, p_entity, p_entity_id, coalesce(p_detail, '{}'::jsonb));
end;
$$;
revoke execute on function public.write_audit(text, text, text, jsonb) from public, anon;
grant  execute on function public.write_audit(text, text, text, jsonb) to authenticated;

-- ── Subscription changes ───────────────────────────────────────────────────────
-- The Stripe webhook writes entitlements as service role; capture every change so
-- tier/payment_status transitions are reconstructable for support & chargebacks.
create or replace function public.tg_audit_entitlement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if TG_OP = 'UPDATE'
       and new.tier = old.tier
       and new.payment_status = old.payment_status
       and coalesce(new.cancel_at_period_end,false) = coalesce(old.cancel_at_period_end,false) then
        return new;  -- nothing meaningful changed (e.g. period bump), skip noise
    end if;
    insert into audit_log (actor_id, action, entity, entity_id, detail)
    values (
        auth.uid(),
        'entitlement.' || lower(TG_OP),
        'user_entitlements',
        new.user_id::text,
        jsonb_build_object(
            'old_tier',   (case when TG_OP='UPDATE' then old.tier else null end),
            'new_tier',   new.tier,
            'old_status', (case when TG_OP='UPDATE' then old.payment_status else null end),
            'new_status', new.payment_status,
            'cancel_at_period_end', new.cancel_at_period_end,
            'stripe_subscription_id', new.stripe_subscription_id
        )
    );
    return new;
end;
$$;

drop trigger if exists audit_entitlement on user_entitlements;
create trigger audit_entitlement after insert or update on user_entitlements
    for each row execute function public.tg_audit_entitlement();

-- ── Content deletions ──────────────────────────────────────────────────────────
-- Log deletions of rounds & shots so accidental/abusive bulk wipes are traceable.
create or replace function public.tg_audit_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into audit_log (actor_id, action, entity, entity_id, detail)
    values (auth.uid(), TG_ARGV[0], TG_TABLE_NAME, old.id::text,
            jsonb_build_object('owner', old.user_id));
    return old;
end;
$$;

drop trigger if exists audit_round_delete on course_rounds;
create trigger audit_round_delete after delete on course_rounds
    for each row execute function public.tg_audit_delete('round.deleted');

drop trigger if exists audit_shot_delete on shots;
create trigger audit_shot_delete after delete on shots
    for each row execute function public.tg_audit_delete('shot.deleted');
