# tools/ — course-data pipeline

Operational scripts for the self-hosted course catalog (Supabase project
`aoxturoezgecwceudeef`). All are resumable (progress in `artifacts/*.jsonl`),
all destructive DB changes are logged as SQL in `fix_sql/`, and every
rewritten storage blob is backed up under `artifacts/*_backup/` first.

## Layout

| Path | What |
|---|---|
| `*.py` | Pipeline scripts (below) |
| `artifacts/` | Generated outputs: progress logs, reports, blob backups, OSM dump. Regenerable or restorable; git-ignored. |
| `fix_sql/` | Executed SQL, kept as the audit trail of every catalog change |
| `rescrape_worklist.csv` / `rescrape_worklist_2.csv` | Courses needing geometry re-scrape (see `RESCRAPE_INSTRUCTIONS.md`) |
| `quarantined_ids.json` | Blob ids quarantined by the 2026-07-07 audit |
| `randa_slope_tees_FINAL.csv` | R&A ratings source data (merged 2026-07-08) |

## Scripts by pipeline stage

**Audit / integrity**
- `course_audit.py` — geometry blobs vs catalog: location mismatches, fingerprint duplicates
- `blob_completeness_audit.py` — per-blob completeness (holes, tees, slope/rating/handicap coverage)
- `arbitrate_shared_geometry.py` — decides which course owns a shared/stolen map (independent geocode ≤3 km of blob centroid)

**Cleanup / repair**
- `dedupe_tees.py` — collapses caps-twin tee entries ("GOLD"+"Gold") in blobs
- `fix_tee_totals.py` — recomputes missing tee totalYards from per-hole yardages
- `randa_merge.py` — merges R&A ratings/tees into blobs + `course_geometries` payloads, inserts new courses

**Locations (courses with no lat/lon)**
- `geolocate_courses.py` — batch pass: Nominatim golf-course matches (strict; ambiguity-safe)
- `osm_dump_match.py` — second pass: local fuzzy match against the full US OSM golf dump
- `locate_gui.py` — manual pass: native macOS dialogs over the leftovers
- `locate_courses.py` — terminal variant of the manual pass; `--worklist` exports the remaining set
- `address_geolocate.py` — GolfCourseAPI address → maps.co geocode (low yield; kept for reference)

**Scorecards**
- `golfcourseapi_backfill.py` — GolfCourseAPI scorecard verification into `course_geometries`
- `build_rescrape_worklist.py` — builds the re-scrape worklist from audit output

## Hard-won rules (read before writing new scripts)

- PostgREST pagination MUST use `order=id.asc` — bare limit/offset returns overlapping pages.
- Catalog lat/lon is NOT location evidence for shared-geometry groups (it often descends from the blob itself). Geocode the name independently.
- `course_geometries` joins to the catalog via `payload->>'id'` (indexed, migration 040); `internal_course_id` is empty.
- `courses.status` check allows: active, closed, duplicate, inactive, needs_review, unknown. `course_geometries.geometry_state`: auto_draft, accepted, rejected.
- Never overwrite a non-null rating/slope; fill only.
