# OSM course-geometry pre-bake

Bulk-populates Supabase `course_geometries` with **free, non-proprietary** golf geometry from
OpenStreetMap (ODbL) plus optional GolfCourseAPI scorecards. The iOS app reads `accepted` rows
from this table first (`CourseDataAggregator.loadSharedGeometry`), so any course baked here plays
in rangefinder/full-GPS mode without a live Overpass call.

## Why this exists

OSM is the only free, openly-licensed source of golf-course vector geometry. Live per-course
Overpass calls are flaky and rate-limited, and most courses aren't fully traced. Baking the data
once into Supabase gives reliable coverage and lets us curate the best-mapped ~5000 US courses.

## Setup

```bash
cd Backend/scripts/osm-prebake
npm install
```

Apply migration `012_course_geometry_coords.sql` first (adds the `latitude`/`longitude` columns
the app's fuzzy fallback queries).

## Run

```bash
# Dry run — no DB writes, prints what it would bake:
node prebake.mjs --state "Delaware" --limit 10 --dry-run

# Real run for one state:
SUPABASE_URL=https://<ref>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=<service-role-key> \
GOLFCOURSEAPI_KEY=<optional-key> \
  node prebake.mjs --state "Pennsylvania"
```

Flags:
- `--state "<US state name>"` — Overpass admin-boundary area to enumerate. Or `--bbox "s,w,n,e"`.
- `--limit N` — stop after N baked courses (use for testing).
- `--min-greens N` — minimum traced greens to accept a course (default 9).
- `--dry-run` — skip Supabase writes.

Env:
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` — required for writes (service role bypasses RLS).
- `GOLFCOURSEAPI_KEY` — optional; when set, attaches par/handicap/yardage + named tee boxes.
- `OVERPASS_URL` — override the Overpass mirror (default overpass-api.de).

## How it matches the app

- Geometry inference (`geometry.mjs`) mirrors the iOS `HoleInference` / `GolfGeometry` logic, so
  baked greens/centers/synthesized polygons look like what the app would infer live.
- The payload is written in **snake_case** to match the app's `JSONDecoder`
  (`keyDecodingStrategy = .convertFromSnakeCase`). Tee-box ids avoid underscores on purpose so the
  per-tee yardage dictionary keys survive snake_case conversion.
- `course_id` uses an OSM-derived id; the app finds rows by the new **name + proximity** fuzzy
  fallback (`findCourseGeometryNear`), so the MapKit-vs-OSM id mismatch doesn't matter.

## Attribution

OSM data is ODbL — surface "© OpenStreetMap contributors" wherever this course data is shown.

## Scaling to ~5000 US courses

Run state-by-state. Be polite to Overpass (the script throttles ~1.5s/request); for large states
consider a self-hosted Overpass or a Geofabrik US extract. Check coverage with:

```sql
select count(*) from course_geometries where source = 'osm';
```
