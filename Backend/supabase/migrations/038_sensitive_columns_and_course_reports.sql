-- 038_sensitive_columns_and_course_reports.sql
-- Fixes the 06 Jul 2026 Supabase security email.
--
-- 1) sensitive_columns_exposed: pro_clubs carries club business contact data
--    (email, telephone, address) and migration 013 gave it a blanket public
--    read policy. The iOS app never queries pro_clubs (the importer derives
--    course_geometries server-side), so public read goes away entirely.
--    pro_courses / pro_tees / pro_hole_pois keep their public read policies —
--    they hold only pars, yardages, and hole coordinates.
--
-- 2) rls_disabled_in_public: the course-data pipeline tables (course_holes,
--    course_tee_sets, course_hole_tee_yardages, course_source_records,
--    course_import_batches, course_osm_matches, course_data_requests) were
--    created ad-hoc in the SQL editor. RLS was confirmed enabled on all of
--    them on 2026-07-08 (`pg_tables.rowsecurity = true`, no policies = deny
--    all for anon/authenticated; service-role ingestion bypasses RLS). The
--    idempotent enables below keep this migration authoritative for a fresh
--    database.

drop policy if exists "public read pro_clubs" on pro_clubs;

alter table if exists public.course_holes             enable row level security;
alter table if exists public.course_tee_sets          enable row level security;
alter table if exists public.course_hole_tee_yardages enable row level security;
alter table if exists public.course_source_records    enable row level security;
alter table if exists public.course_import_batches    enable row level security;
alter table if exists public.course_osm_matches       enable row level security;
alter table if exists public.course_data_requests     enable row level security;

-- In-app "Report course issue" button: signed-in users may file a report
-- about a course; they never read the queue back (tools drain it with the
-- service role).
drop policy if exists "users can report course issues" on course_data_requests;
create policy "users can report course issues"
    on course_data_requests for insert to authenticated
    with check (submitted_by = auth.uid());
