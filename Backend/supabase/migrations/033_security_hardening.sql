-- Security hardening from advisor sweep (2026-07-05).
-- Threat model note: live-sim pairing codes are 9-digit crypto-random and
-- displayed only on the host screen (Chromecast model). Enumeration is dead;
-- these policies harden storage hygiene, not the pairing model itself.

-- 1. ERROR: analytics partitions created without RLS (parent has it).
alter table if exists public.analytics_events_202607 enable row level security;
alter table if exists public.analytics_events_202608 enable row level security;

-- 2. Trigger functions must not be callable through PostgREST RPC.
revoke execute on function public.tg_audit_delete() from anon, authenticated;
revoke execute on function public.tg_audit_entitlement() from anon, authenticated;
revoke execute on function public.tg_rate_limit() from anon, authenticated;
revoke execute on function public.tg_rate_limit_analytics() from anon, authenticated;
revoke execute on function public.tg_rate_limit_storage() from anon, authenticated;

-- 3. live_sim_state: replace always-true INSERT/UPDATE with code-shape checks
--    and stamp freshness so the TTL sweep is trustworthy.
drop policy if exists "live sim state insert" on public.live_sim_state;
drop policy if exists "live sim state update" on public.live_sim_state;
create policy "live sim state insert" on public.live_sim_state
  for insert with check (code ~ '^[0-9]{6,10}$');
create policy "live sim state update" on public.live_sim_state
  for update using (true) with check (code ~ '^[0-9]{6,10}$');

-- 4. Pin the mutable search_path the linter flagged.
alter function public.to_double_safe(text) set search_path = '';

-- 5. TTL: pairing-state rows are ephemeral by design; sweep after 48h.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'live-sim-state-ttl',
      '17 * * * *',
      $sweep$ delete from public.live_sim_state where updated_at < now() - interval '48 hours' $sweep$
    );
  end if;
end $$;
