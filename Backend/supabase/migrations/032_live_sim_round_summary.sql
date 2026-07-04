-- Round-results sync: the sim publishes a compact end-of-round summary the
-- phone reads to enrich the saved session (course, per-hole scores, total).
alter table public.live_sim_state
  add column if not exists round_summary jsonb;
