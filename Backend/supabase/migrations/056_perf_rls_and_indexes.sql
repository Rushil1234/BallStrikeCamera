-- Performance pass from the Supabase linter (2026-07-21). No behavior change.
--
-- 1. auth_rls_initplan: 9 RLS policies called auth.uid() directly, which Postgres
--    re-evaluates for EVERY row. Wrapping it as (select auth.uid()) makes it an
--    InitPlan evaluated ONCE per query. Logic is identical — same USING/WITH CHECK,
--    same roles, same command — only the evaluation count changes.
-- 2. duplicate_index: 7 tables carried two identical indexes (an older `_idx` name
--    and a newer `idx_` name). Keep one, drop the redundant copy — halves the write
--    cost on those columns with no read-path change.

-- 1. RLS init-plan fixes (drop + recreate each with (select auth.uid()))

drop policy if exists "clients insert own events" on public.analytics_events;
create policy "clients insert own events" on public.analytics_events
  for insert to anon, authenticated
  with check ((user_id is null) or (user_id = (select auth.uid())));

drop policy if exists "course_bookmarks_own" on public.course_bookmarks;
create policy "course_bookmarks_own" on public.course_bookmarks
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "users can report course issues" on public.course_data_requests;
create policy "users can report course issues" on public.course_data_requests
  for insert to authenticated
  with check (submitted_by = (select auth.uid()));

drop policy if exists "course_ratings_write" on public.course_ratings;
create policy "course_ratings_write" on public.course_ratings
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "read own or visible shots" on public.shots;
create policy "read own or visible shots" on public.shots
  for select to public
  using (
    (user_id = (select auth.uid()))
    or (visibility = 'public'::text)
    or ((visibility = 'friends'::text)
        and (is_friend((select auth.uid()), user_id) or shares_home_course((select auth.uid()), user_id)))
  );

drop policy if exists "requester inserts own" on public.round_attestations;
create policy "requester inserts own" on public.round_attestations
  for insert to public
  with check ((select auth.uid()) = requester_id);

drop policy if exists "requester reads own" on public.round_attestations;
create policy "requester reads own" on public.round_attestations
  for select to public
  using ((select auth.uid()) = requester_id);

drop policy if exists "attester reads" on public.round_attestations;
create policy "attester reads" on public.round_attestations
  for select to public
  using ((select auth.uid()) = attester_id);

drop policy if exists "attester responds" on public.round_attestations;
create policy "attester responds" on public.round_attestations
  for update to public
  using ((select auth.uid()) = attester_id);

-- 2. Drop duplicate indexes (keep the `_idx` copy, drop the `idx_` duplicate)

drop index if exists public.idx_clubs_user_id;
drop index if exists public.idx_feed_comments_post_id;
drop index if exists public.idx_feed_comments_user_id;
drop index if exists public.idx_feed_reactions_user_id;
drop index if exists public.idx_friend_requests_from_user;
drop index if exists public.idx_friendships_friend_id;
drop index if exists public.idx_user_devices_user_id;
