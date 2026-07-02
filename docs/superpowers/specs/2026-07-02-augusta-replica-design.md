# Augusta National Replica for the Browser Sim — Design

**Date:** 2026-07-02
**Status:** Approved by default (user AFK; request was "copy the real one into the sim, make sure it works and is accurate")

## Goal

Add an accurate, playable replica of Augusta National's 18 championship holes to the
live browser sim (`Website/public/sim/`), following the same pattern as the existing
Pebble Beach replica ("Cypress Coast Links").

## Naming

Public site → no official marks (same policy as the Pebble replica). Course ships as
**"Magnolia Hills"** with plant-themed hole names that echo but do not copy the real ones
("Amen Corner" is an ANGC trademark; avoided). Switching to the real name later is a
one-string change in `local-courses.js` / `augusta-private.js`.

## Data sources (accuracy)

- **Hole centerlines, fairway/green/bunker/tee/water polygons:** OpenStreetMap via
  Overpass (ODbL, attributed in generated file). Verified coverage: 18 championship
  `golf=hole` centerlines, 33 fairways, 69 bunkers, 44 greens, Rae's Creek +
  ponds as `golf=lateral_water_hazard` / water polygons. The property also contains
  the Par-3 course (duplicate hole refs 1–9, short lengths, NE corner) — excluded by
  picking the longer way per ref and validating length against the scorecard.
- **Pars & card yardages:** official Masters scorecard (par 72, 7,555 y):
  445/585/350/240/495/180/450/570/460 out (par 36), 495/520/155/545/440/550/170/440/465 in (par 36).
- **Elevation:** USGS EPQS point-query grid (same generator approach as Pebble);
  Augusta has ~30 m of real relief clubhouse → Rae's Creek.

## Architecture

New generated data modules in `TrueCarry_Sim/js/` (dev copy), mirrored to
`Website/public/sim/js/` (live):

- `augusta-private.js` — `AUGUSTA_PRIVATE_HOLES` (18 holes: real centerline `path`,
  `cardYards`, ellipse-fit `green`, `pin`, ellipse-fit `bunkers`, `water`
  channels/ponds) + `AUGUSTA_PRIVATE_WORLD` (prepositioned, boundsMargin, no coastline).
- `augusta-osm.js` — `AUGUSTA_OSM_BY_HOLE` per-hole surface polygons (fairways,
  greens, tees, bunkers) in the same shape `terrain.js` already consumes.
- `augusta-elevation.js` — `AUGUSTA_ELEVATION` grid (width/height/worldBounds/values/base/scale).

Generators in `TrueCarry_Sim/tools/`:

- `generate-augusta-course.mjs` — Overpass JSON → the two course modules.
  Local projection: equirectangular around course centroid (same `project()` as Pebble
  tools). Green/bunker ellipses fit via centroid + PCA axes. Water: creek ways →
  `channel`, closed pond polygons → `pond` ellipses. Holes matched to surfaces by
  distance to centerline corridor.
- `generate-augusta-elevation.mjs` — EPQS grid fetch (cached), Augusta bbox.

Wiring:

- `local-courses.js` — third `LOCAL_COURSES` entry (`courseId: 'magnolia-hills'`),
  world `{ profile: 'coastal', prepositioned: true, elevation: AUGUSTA_ELEVATION }`.
  `profile: 'coastal'` is the sim's "real-world data" profile: it enables the DEM;
  with no `coastline` supplied, `hasOcean` is false and no ocean renders (inland course).
- `tools/test.sh` — add the three new files to the headless JSC bundle.
- `tools/bot-test.js` — add course to `TEST_COURSES` (guarded `typeof`, like Pebble);
  Augusta-specific assertions: tee/pin never classified water; Rae's Creek water present
  near holes 12/13/15/16; hole path length within tolerance of card yards.

## Error handling

Generators are offline build-time tools: they fail loudly (non-zero exit) on missing
holes, unmatched greens, or a hole count ≠ 18. The sim itself gets only static data —
no new runtime failure modes.

## Testing

`TrueCarry_Sim/tools/test.sh` (bot plays every hole through real terrain + physics)
must pass for all three courses. Manual accuracy spot-check: centerline length vs card
yards; Amen Corner water layout.

## Out of scope

Cart paths / visualZones realism layer (Pebble's `pebble-world-data.js` extras),
Supabase `sim_courses` upload, the diverged `sim-app` / `course-sim` copies.
