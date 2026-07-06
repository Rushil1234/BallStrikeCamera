-- Spectator leaderboard: the sim publishes live multi-player standings the
-- watch page renders (name, strokes, holes played, to-par, whose turn).
alter table public.live_sim_state
  add column if not exists match jsonb;
