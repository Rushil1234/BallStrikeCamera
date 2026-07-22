-- Tighten the crowdsourced course_geometries write policies (linter: rls_policy_always_true).
--
-- course_geometries is crowdsourced BY DESIGN (migration 037): any authenticated player
-- refreshes the shared snapshot, and `submitted_by` records who. But the old policies used
-- WITH CHECK (true), so a client could write rows attributed to SOMEONE ELSE (spoof
-- submitted_by). The iOS app already stamps submitted_by = the current user on every save
-- (SupabaseBackendService.saveCourseGeometry / *Verified), so requiring
--   submitted_by = auth.uid()
-- is non-breaking for the real app path and closes the spoofing hole.
--
-- UPDATE keeps USING (true) so the crowdsourced refresh still works (you may refresh a row
-- someone else first submitted), but WITH CHECK forces you to honestly stamp yourself as the
-- new submitter. INSERT now requires you to own the row you create.

drop policy if exists "authenticated can insert course geometry" on public.course_geometries;
create policy "authenticated can insert course geometry"
    on public.course_geometries for insert
    to authenticated
    with check (submitted_by = (select auth.uid()));

drop policy if exists "authenticated can update course geometry" on public.course_geometries;
create policy "authenticated can update course geometry"
    on public.course_geometries for update
    to authenticated
    using (true)
    with check (submitted_by = (select auth.uid()));
