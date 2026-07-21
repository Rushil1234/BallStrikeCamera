-- ============================================================================
-- 052_course_ratings_and_bookmarks.sql
-- Course ratings (1-5) + reviews, and private course bookmarks. Keyed on the BASE
-- course name (tees grouped). Users manage only their own rows via RLS; the
-- cross-user rating average comes from a SECURITY DEFINER RPC.
-- ============================================================================
create table if not exists public.course_ratings (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  course_name text not null,
  rating      int  not null check (rating between 1 and 5),
  review      text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, course_name),
  constraint course_rating_review_len check (review is null or char_length(review) <= 500)
);
create index if not exists course_ratings_course_idx on public.course_ratings (lower(course_name));

create table if not exists public.course_bookmarks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  course_name text not null,
  created_at  timestamptz not null default now(),
  unique (user_id, course_name)
);
create index if not exists course_bookmarks_user_idx on public.course_bookmarks (user_id, created_at desc);

alter table public.course_ratings   enable row level security;
alter table public.course_bookmarks enable row level security;

drop policy if exists course_ratings_read on public.course_ratings;
create policy course_ratings_read on public.course_ratings
  for select to authenticated using (true);
drop policy if exists course_ratings_write on public.course_ratings;
create policy course_ratings_write on public.course_ratings
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists course_bookmarks_own on public.course_bookmarks;
create policy course_bookmarks_own on public.course_bookmarks
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop function if exists public.course_rating_summary(text);
create or replace function public.course_rating_summary(p_course text)
returns table(avg_rating double precision, rating_count int, my_rating int)
language sql
security definer
set search_path = public
as $$
  with base as (select lower(trim(split_part(p_course, ' ~ ', 1))) as c)
  select
    round(avg(r.rating)::numeric, 1)::float8 as avg_rating,
    count(*)::int                    as rating_count,
    max(r.rating) filter (where r.user_id = auth.uid()) as my_rating
  from public.course_ratings r, base
  where lower(trim(split_part(r.course_name, ' ~ ', 1))) = base.c;
$$;
revoke all on function public.course_rating_summary(text) from public, anon;
grant execute on function public.course_rating_summary(text) to authenticated, service_role;
