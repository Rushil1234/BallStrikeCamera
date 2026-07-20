-- ============================================================================
-- 043_live_sim_state_hardening.sql   (APPLIED 2026-07-19)
--
-- VULNERABILITY (confirmed by test): live_sim_state RLS granted anon
--   SELECT USING (true)  and  UPDATE USING (true)
-- so anyone holding the PUBLIC anon key could dump EVERY live-sim session
-- (codes + full round state) and overwrite any of them. The 9-digit
-- crypto-random pairing code was irrelevant, because the codes themselves were
-- readable — no guessing required.
--
-- This migration narrows the blast radius WITHOUT breaking the shipped iOS
-- client (which reads/writes the table directly, filtered by code).
-- The complete fix — code-scoped SECURITY DEFINER RPCs (get/update by code) and
-- removing direct table access — requires a coordinated app release.
-- ============================================================================

-- 1) Purge stale sessions and legacy/test rows whose codes predate the
--    6-10 digit format check (e.g. 'ZZ9', 'POLLTEST1', 'VERIFYX').
delete from public.live_sim_state
where updated_at < now() - interval '24 hours'
   or code !~ '^[0-9]{6,10}$';

-- 2) Guard trigger: the pairing code is immutable (an attacker can't re-point
--    an existing row at a different code), and every write refreshes
--    updated_at so an in-progress round always stays inside the active window.
create or replace function public.tg_live_sim_guard()
returns trigger
language plpgsql
as $$
begin
  if NEW.code is distinct from OLD.code then
    raise exception 'live_sim_state.code is immutable';
  end if;
  NEW.updated_at := now();
  return NEW;
end;
$$;

drop trigger if exists trg_live_sim_guard on public.live_sim_state;
create trigger trg_live_sim_guard
  before update on public.live_sim_state
  for each row execute function public.tg_live_sim_guard();

-- 3) Narrow RLS from "any row, forever" to "currently-active sessions only".
--    A round runs ~4-5h; 12h is a safe margin and (2) keeps live rows fresh.
drop policy if exists "live sim state read" on public.live_sim_state;
create policy "live sim state read" on public.live_sim_state
  for select
  using (updated_at > now() - interval '12 hours');

drop policy if exists "live sim state update" on public.live_sim_state;
create policy "live sim state update" on public.live_sim_state
  for update
  using (updated_at > now() - interval '12 hours')
  with check (code ~ '^[0-9]{6,10}$');

-- Verified after apply: anon SELECT returns 0 rows; anon UPDATE affects 0 rows.
