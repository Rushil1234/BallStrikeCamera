-- 041_weekly_challenges.sql
-- True Carry — camera-verified weekly challenges (v1: Longest Verified Carry).
--
-- The differentiator: entries come from the app's camera-tracked shot pipeline
-- (ShotSource.live), not self-reported numbers. The client is the trust
-- boundary for "camera-tracked" in v1; the server adds sanity bounds, a
-- keep-best-per-week upsert, and RPC-only writes so rows can't be forged with
-- arbitrary values via PostgREST table access.

create table if not exists challenge_entries (
    id             uuid primary key default gen_random_uuid(),
    user_id        uuid not null references auth.users(id) on delete cascade,
    week_start     date not null,                              -- Monday (UTC)
    challenge_type text not null default 'longest_carry',
    carry_yards    numeric not null,
    ball_speed_mph numeric,
    club_name      text not null default '',
    shot_id        uuid,                                       -- SavedShot id for provenance
    created_at     timestamptz not null default now(),
    unique (user_id, week_start, challenge_type)
);

create index if not exists challenge_entries_week_idx
    on challenge_entries (challenge_type, week_start, carry_yards desc);

alter table challenge_entries enable row level security;

-- Users can read their own entries directly; all writes go through the RPC.
-- (select auth.uid()) is the initplan-optimized form this project standardized on.
create policy "users read own challenge entries"
    on challenge_entries for select using ((select auth.uid()) = user_id);

-- ── Submit (keep-best upsert with sanity bounds) ────────────────────────────────
create or replace function public.submit_challenge_entry(
    p_carry_yards    numeric,
    p_ball_speed_mph numeric default null,
    p_club_name      text    default '',
    p_shot_id        uuid    default null
)
returns void
language plpgsql security definer set search_path = public as $$
declare
    v_week date := date_trunc('week', now() at time zone 'utc')::date;
    -- club_name is echoed to every leaderboard viewer; clamp so a hostile
    -- client can't store megabytes of text through the RPC.
    v_club text := left(coalesce(p_club_name, ''), 40);
begin
    if auth.uid() is null then
        raise exception 'not authenticated';
    end if;
    -- Sanity bounds: outside plausible golf physics = rejected, not clamped.
    if p_carry_yards is null or p_carry_yards < 25 or p_carry_yards > 450 then
        raise exception 'carry out of range';
    end if;
    if p_ball_speed_mph is not null and (p_ball_speed_mph < 0 or p_ball_speed_mph > 250) then
        raise exception 'ball speed out of range';
    end if;

    insert into challenge_entries (user_id, week_start, challenge_type, carry_yards, ball_speed_mph, club_name, shot_id)
    values (auth.uid(), v_week, 'longest_carry', p_carry_yards, p_ball_speed_mph, v_club, p_shot_id)
    on conflict (user_id, week_start, challenge_type) do update
        set carry_yards    = excluded.carry_yards,
            ball_speed_mph = excluded.ball_speed_mph,
            club_name      = excluded.club_name,
            shot_id        = excluded.shot_id,
            created_at     = now()
        where excluded.carry_yards > challenge_entries.carry_yards;  -- keep best
end;
$$;

-- This project's default privileges auto-grant EXECUTE to anon on new
-- functions, so revoke anon explicitly (revoking public alone is not enough).
revoke execute on function public.submit_challenge_entry(numeric, numeric, text, uuid) from public, anon;
grant  execute on function public.submit_challenge_entry(numeric, numeric, text, uuid) to authenticated;

-- ── Leaderboard (top 50 this week, minimal profile projection) ──────────────────
create or replace function public.weekly_challenge_leaderboard()
returns table (
    user_id        uuid,
    display_name   text,
    carry_yards    numeric,
    ball_speed_mph numeric,
    club_name      text,
    created_at     timestamptz
)
language sql security definer set search_path = public stable as $$
    select e.user_id,
           coalesce(p.display_name, 'Golfer'),
           e.carry_yards,
           e.ball_speed_mph,
           e.club_name,
           e.created_at
    from challenge_entries e
    left join profiles p on p.user_id = e.user_id
    where e.challenge_type = 'longest_carry'
      and e.week_start = date_trunc('week', now() at time zone 'utc')::date
    order by e.carry_yards desc, e.created_at asc
    limit 50;
$$;

revoke execute on function public.weekly_challenge_leaderboard() from public, anon;
grant  execute on function public.weekly_challenge_leaderboard() to authenticated;
