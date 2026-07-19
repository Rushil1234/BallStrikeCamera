-- ============================================================================
-- 046_live_sim_code_scoped_rpcs.sql   (APPLIED 2026-07-19) — PHASE A
--
-- Completes the fix started in 043. ADDITIVE ONLY: existing table policies are
-- untouched, so the shipped iOS app (which reads/writes live_sim_state
-- directly) keeps working. Phase B (047) revokes direct anon table access once
-- both clients call these RPCs.
--
-- Why RPCs are required: RLS cannot express "you may read this row only if you
-- already know its code" — the client's WHERE filter is invisible to the
-- policy, which is why `USING (true)` let anyone dump every code. A SECURITY
-- DEFINER function CAN enforce it, because the code is a function argument.
--
-- Verified after apply (as anon, with only the public key):
--   live_sim_get('<correct code>')  -> 1 row      (pairing still works)
--   live_sim_get('<wrong code>')    -> 0 rows     (must know the code)
--   live_sim_update('<correct>',{}) -> row updated
-- ============================================================================

create or replace function public.live_sim_get(p_code text)
returns setof public.live_sim_state
language sql
security definer
set search_path = public
as $$
  select * from public.live_sim_state
  where code = p_code
    and updated_at > now() - interval '12 hours';
$$;

create or replace function public.live_sim_update(p_code text, p_patch jsonb)
returns setof public.live_sim_state
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_code !~ '^[0-9]{6,10}$' then
    raise exception 'invalid pairing code';
  end if;

  return query
  update public.live_sim_state s set
    hole                  = coalesce((p_patch->>'hole')::int, s.hole),
    par                   = coalesce((p_patch->>'par')::int, s.par),
    yards                 = coalesce((p_patch->>'yards')::int, s.yards),
    hole_name             = coalesce(p_patch->>'hole_name', s.hole_name),
    stroke                = coalesce((p_patch->>'stroke')::int, s.stroke),
    to_par                = coalesce((p_patch->>'to_par')::int, s.to_par),
    distance_to_pin_yards = coalesce((p_patch->>'distance_to_pin_yards')::numeric, s.distance_to_pin_yards),
    last_shot             = coalesce(p_patch->'last_shot', s.last_shot),
    sim_state             = coalesce(p_patch->>'sim_state', s.sim_state),
    last_ack_seq          = coalesce((p_patch->>'last_ack_seq')::bigint, s.last_ack_seq),
    round_summary         = coalesce(p_patch->'round_summary', s.round_summary),
    match                 = coalesce(p_patch->'match', s.match),
    updated_at            = now()
  where s.code = p_code
    and s.updated_at > now() - interval '12 hours'
  returning s.*;
end;
$$;

-- Anonymous pairing is the product's design, so anon may CALL these — but every
-- call is scoped to one known code instead of the entire table.
revoke all on function public.live_sim_get(text) from public;
revoke all on function public.live_sim_update(text, jsonb) from public;
grant execute on function public.live_sim_get(text) to anon, authenticated, service_role;
grant execute on function public.live_sim_update(text, jsonb) to anon, authenticated, service_role;
