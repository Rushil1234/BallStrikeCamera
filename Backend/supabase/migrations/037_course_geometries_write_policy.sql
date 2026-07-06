-- 037: allow signed-in players to write course geometry snapshots
--
-- The app's round write-through (saveCourseGeometry) upserts the enriched course into
-- course_geometries, but the table only had a SELECT policy — every save 403'd
-- ("new row violates row-level security"). Upsert needs INSERT + UPDATE.
-- Crowdsourced by design: any authenticated player refreshes the shared snapshot
-- (submitted_by records who). Reads stay limited to accepted rows via the existing policy.

create policy "authenticated can insert course geometry"
    on public.course_geometries for insert
    to authenticated
    with check (true);

create policy "authenticated can update course geometry"
    on public.course_geometries for update
    to authenticated
    using (true)
    with check (true);
