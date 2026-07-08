# Re-scrape worklist — instructions for the course parser/scraper agent

**Input:** `tools/rescrape_worklist.csv` (1,729 rows). Every row is a course that WAS
`gps_ready` but got demoted in the 2026-07-07 audit because its geometry blob did not
belong to it. The old script's "18 greens/tees present" check passed on all of these —
the geometry was *complete*, just **someone else's course**. Completeness checks can't
catch that; only location cross-checks do (see Acceptance below).

## Columns

| column | meaning |
|---|---|
| `course_id` | catalog UUID — reuse it; upload target is `course-geometry/<course_id>.json.gz` |
| `course_name`, `city`, `state`, `country` | catalog identity of the course we NEED |
| `catalog_lat/lon` | where the catalog says it is. **Caution:** for `suspect_phantom=true` rows these came from the stolen blob, so they are NOT independent evidence |
| `issue` | `STOLEN_GEOMETRY` = wore a provably-owned course's map (owner in `geometry_belongs_to_*`) · `WRONG_LOCATION_MERGE` = map sits >3 km from catalog position (`geometry_belongs_to_*` = best guess at the true owner near the map) · `SHARED_GEOMETRY_UNRESOLVED` = several clubs shared one map and none proved ownership |
| `geometry_belongs_to_id/name` | the course we already HAVE correctly — do NOT re-scrape it; it tells you which club's data the bad blob really was |
| `wrong_geometry_centroid` | where the wrong map actually sits (useful to identify the true owner) |
| `suspect_phantom` | `true` = likely not a real distinct facility (Cozy Acres pattern — an alias/derived listing wearing a neighbor's map). **Verify existence before scraping**; if it doesn't exist, add to the removal list instead |
| `quarantined_blob` | old bad blob, renamed in the bucket — reference only, never restore |

## What to do per row

1. **`suspect_phantom=true` (672 rows):** first verify the facility exists independently
   (Grint/USGA NCRDB/Google). If it does not exist as a distinct course → leave demoted and
   record it; `tools/fix_sql/remove_fakes.sql` (pre-written, NOT executed) marks all
   suspects inactive — prune the verified-real ones from that file before running it.
2. **Real courses:** re-acquire geometry from the correct source, keyed by NAME + CITY/STATE
   (never by proximity to `catalog_lat/lon` alone, and never matching bare club names across
   states — that's exactly the bug that created these). The Knoll East fix is the template:
   Grint course id for hole geometry + USGA NCRDB for tee totals/ratings, gendered tees split
   M/F, `geometry_metadata.notes` documenting sources.
3. **Upload:** gzip JSON to `course-geometry/<course_id>.json.gz` (service key, `x-upsert: true`),
   then `update courses set data_tier='gps_ready', latitude=<real>, longitude=<real> where id=...`.
4. **Scorecard verify:** `python3 tools/golfcourseapi_backfill.py --course-id <course_id>`
   (only works while a GolfCourseAPI key is active — batch these before any plan downgrade).

## Acceptance checks (add BOTH to the scraper's validator)

- **Location:** tee-coordinate centroid within 3 km of an independently-geocoded position for
  the course's name+city (not the catalog row).
- **Uniqueness:** hole-coordinate fingerprint (sorted tee coords rounded to 4 decimals) must not
  equal any existing blob's fingerprint — `tools/course_audit.py` computes these; rerun it after
  any batch upload and require zero new MISMATCH/DUPLICATE flags.
