-- Live-sim delivery guarantees: the sim records the highest shot sequence it
-- has received; the phone polls this to prune/resend unacknowledged shots.
alter table public.live_sim_state
  add column if not exists last_ack_seq bigint;
