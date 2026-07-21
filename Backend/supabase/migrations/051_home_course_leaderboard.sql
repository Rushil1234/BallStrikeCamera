-- ============================================================================
-- 051_home_course_leaderboard.sql
-- Ranks players by best (lowest) saved round score at a given course, matching
-- on the base course name (before the " ~ tee" suffix) so all tees group together.
-- Excludes private rounds and unscored (0) rounds. SECURITY DEFINER so the
-- leaderboard can read across users; returns only name + score (no sensitive data).
-- ============================================================================
create or replace function public.home_course_leaderboard(p_course text, p_limit int default 25)
returns table(
  user_id uuid,
  display_name text,
  best_score int,
  best_par int,
  rounds_played int,
  last_played timestamptz
)
language sql
security definer
set search_path = public
as $$
  with scoped as (
    select cr.user_id, cr.total_score, cr.total_par, cr.started_at
    from public.course_rounds cr
    where cr.is_saved
      and cr.total_score is not null and cr.total_score > 0
      and cr.total_par is not null and cr.total_par > 0
      and coalesce(cr.visibility, 'friends') <> 'private'
      and lower(trim(split_part(cr.course_name, ' ~ ', 1))) = lower(trim(split_part(p_course, ' ~ ', 1)))
  ),
  best as (
    select user_id,
           min(total_score) as best_score,
           count(*)::int     as rounds_played,
           max(started_at)   as last_played
    from scoped
    group by user_id
  )
  select b.user_id,
         coalesce(p.display_name, 'Golfer') as display_name,
         b.best_score,
         (select s.total_par from scoped s
            where s.user_id = b.user_id and s.total_score = b.best_score
            order by s.started_at desc limit 1) as best_par,
         b.rounds_played,
         b.last_played
  from best b
  left join public.profiles p on p.user_id = b.user_id
  order by b.best_score asc, b.last_played desc
  limit least(p_limit, 100);
$$;
revoke all on function public.home_course_leaderboard(text, int) from public, anon;
grant execute on function public.home_course_leaderboard(text, int) to authenticated, service_role;
