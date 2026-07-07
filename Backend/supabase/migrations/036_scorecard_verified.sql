-- 036: scorecard_verified flag on course_geometries
--
-- Marks rows whose payload was built with GolfCourseAPI scorecard data merged in
-- (authoritative tees + ratings + gendered handicaps). The app prefers these rows
-- over the storage-bucket blob AND skips GolfCourseAPI entirely when set — the
-- path to weaning off the third-party API one played course at a time.

alter table public.course_geometries
    add column if not exists scorecard_verified boolean not null default false;

-- Partial index: the app's read path only ever looks for verified rows.
create index if not exists idx_course_geometries_scorecard_verified
    on public.course_geometries (course_id)
    where scorecard_verified;
