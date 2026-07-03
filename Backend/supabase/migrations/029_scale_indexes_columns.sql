-- 029_scale_indexes_columns.sql
-- Make the transactional tables perform at 1M users / 20M+ shots.
--
-- Two problems this fixes:
--   1) Postgres does NOT auto-index foreign keys. Every "load my shots/rounds",
--      friend lookup, and feed fan-out was a scan without these. Add covering
--      btree indexes on (user_id, <time>) and the FK columns.
--   2) Shot/round metrics live inside a JSONB `payload` (camelCase keys, written
--      by the app's payload encoder). Aggregate analytics over JSONB is slow, so
--      expose the hot fields as STORED generated columns + index them. A safe
--      immutable cast returns NULL instead of erroring on any legacy/dirty row,
--      so ADD COLUMN can't fail mid-rewrite.
--
-- NOTE: the generated columns rewrite the shots/course_rounds tables once. On a
-- large existing table run during low traffic (see SCALE_AND_SECURITY.md). Index
-- creation uses plain CREATE INDEX here for transactional apply; for a hot prod
-- table, create them CONCURRENTLY out-of-band instead.

-- ── Safe numeric cast for generated columns ────────────────────────────────────
create or replace function public.to_double_safe(t text)
returns double precision
language plpgsql
immutable
parallel safe
as $$
begin
    return t::double precision;
exception when others then
    return null;
end;
$$;

-- ── Foreign-key / query indexes ────────────────────────────────────────────────
create index if not exists shots_user_ts_idx          on shots (user_id, "timestamp" desc);
create index if not exists course_rounds_user_ts_idx  on course_rounds (user_id, started_at desc);
create index if not exists range_sessions_user_ts_idx on range_sessions (user_id, started_at desc);
create index if not exists sim_sessions_user_ts_idx   on sim_sessions (user_id, started_at desc);

create index if not exists feed_posts_user_ts_idx     on feed_posts (user_id, "timestamp" desc);
create index if not exists feed_posts_vis_ts_idx      on feed_posts (visibility, "timestamp" desc);
create index if not exists feed_reactions_post_idx    on feed_reactions (post_id);
create index if not exists feed_reactions_user_idx    on feed_reactions (user_id);
create index if not exists feed_comments_post_idx     on feed_comments (post_id);
create index if not exists feed_comments_user_idx     on feed_comments (user_id);

create index if not exists friendships_friend_idx     on friendships (friend_id);
create index if not exists friend_requests_to_idx     on friend_requests (to_user_id, status);
create index if not exists friend_requests_from_idx   on friend_requests (from_user_id);

create index if not exists clubs_user_idx             on clubs (user_id);
create index if not exists usage_counters_user_date   on usage_counters (user_id, date desc);
create index if not exists user_devices_user_idx      on user_devices (user_id);
create index if not exists round_attestations_round_idx on round_attestations (round_id);

-- ── Shots: hot metric columns from JSONB payload (camelCase keys) ──────────────
alter table shots add column if not exists club_name  text
    generated always as (payload->>'clubName') stored;
alter table shots add column if not exists shot_source text
    generated always as (payload->>'source') stored;
alter table shots add column if not exists carry_yards double precision
    generated always as (public.to_double_safe(payload->'metrics'->>'carryYards')) stored;
alter table shots add column if not exists total_yards double precision
    generated always as (public.to_double_safe(payload->'metrics'->>'totalYards')) stored;
alter table shots add column if not exists ball_speed_mph double precision
    generated always as (public.to_double_safe(payload->'metrics'->>'ballSpeedMph')) stored;
alter table shots add column if not exists club_speed_mph double precision
    generated always as (public.to_double_safe(payload->'metrics'->>'clubSpeedMph')) stored;

create index if not exists shots_club_idx        on shots (club_name);
create index if not exists shots_user_club_idx   on shots (user_id, club_name);
create index if not exists shots_carry_idx       on shots (carry_yards);

-- ── Course rounds: score/course columns for handicap & leaderboards ────────────
alter table course_rounds add column if not exists course_name text
    generated always as (payload->>'courseName') stored;
alter table course_rounds add column if not exists total_score int
    generated always as (public.to_double_safe(payload->'scoreSummary'->>'totalScore')::int) stored;
alter table course_rounds add column if not exists total_par int
    generated always as (public.to_double_safe(payload->'scoreSummary'->>'totalPar')::int) stored;

create index if not exists course_rounds_course_idx on course_rounds (course_name);
