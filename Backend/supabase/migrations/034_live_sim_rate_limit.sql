-- Rate-limit live_sim_state writes. The rl_* triggers cover authenticated
-- tables; live-sim rows are written by anon (sim + phone), so this keys the
-- shared rate_limits table on a uuid derived from the pairing code. Cap:
-- 400 writes/code/minute (legit traffic ~60/min).
create or replace function public.tg_rate_limit_livesim()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  k uuid := md5('livesim:' || new.code)::uuid;
  win timestamptz := date_trunc('minute', now());
  n int;
begin
  insert into public.rate_limits (user_id, action, window_start, count)
  values (k, 'livesim_write', win, 1)
  on conflict (user_id, action, window_start)
  do update set count = public.rate_limits.count + 1
  returning count into n;
  if n > 400 then
    raise exception 'rate limit exceeded for live sim session' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke execute on function public.tg_rate_limit_livesim() from anon, authenticated;

drop trigger if exists rl_live_sim_state on public.live_sim_state;
create trigger rl_live_sim_state
  before insert or update on public.live_sim_state
  for each row execute function public.tg_rate_limit_livesim();
