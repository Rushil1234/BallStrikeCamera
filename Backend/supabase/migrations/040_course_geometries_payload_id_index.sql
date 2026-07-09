-- 040_course_geometries_payload_id_index.sql
-- course_geometries rows are keyed by an external course_id, so lookups by the
-- CATALOG uuid go through payload->>'id' (the GolfCourse JSON id). Without an
-- expression index that filter seq-scans ~36k large jsonb rows and hits the
-- statement timeout (57014) — found during the R&A ratings merge.
-- Applied live 2026-07-08.
create index if not exists course_geometries_payload_id_idx
    on public.course_geometries ((payload->>'id'));
