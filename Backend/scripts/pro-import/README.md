# Professional course-data import

Ingests licensed course data (18Birdies-grade) into Supabase. The feed ships four tables:
`clubs`, `courses`, `tees`, `coordinates` (per-hole POIs). This importer:

1. Upserts them into normalized `pro_clubs / pro_courses / pro_tees / pro_hole_pois` (full fidelity:
   men+women pars, handicap/match/split indexes, every tee with per-hole lengths, all POIs).
2. Derives the app-facing `course_geometries` GolfCourse JSON so the iOS app needs no rework.
   POIs map onto the app's GolfHole geometry (green F/C/B, tee, bunkers, water, doglegs); a green
   polygon is synthesized from green front/center/back.

## Run

```bash
npm install
# Validate without writing:
node import.mjs --dir ./samples --dry-run --emit /tmp/out.ndjson
# Real ingestion (service-role key bypasses RLS on the pro_* tables):
SUPABASE_URL=https://<ref>.supabase.co SUPABASE_KEY=<service-role-key> node import.mjs --dir /path/to/feed
```

## When the feed is a REST API (not CSV)

Replace `loadCsvTables()` with a fetch adapter returning the same `{clubs, courses, tees, coords}`
row arrays — all downstream mapping/conversion is reused.

## Schema

See `Backend/supabase/migrations/013_pro_course_data.sql`. `pro_*` tables are public-read,
service-role-write. `course_geometries` (the app read-model) is public-read of `accepted` rows.
