-- 012_course_geometry_coords.sql
-- Adds latitude/longitude columns to course_geometries so the app can fall back to a
-- name + proximity lookup when the exact course_id misses.
--
-- The app keys shared geometry by the MapKit synthetic id ("<name>-<lat*1000>-<lon*1000>"),
-- which drifts when Apple Maps and OSM disagree on a course's name or coordinate. The bulk
-- OSM pre-bake can't always reproduce that exact id, so we also match fuzzily: bounding-box
-- by these columns server-side, then best name+distance match on the client.

alter table course_geometries
    add column if not exists latitude  double precision,
    add column if not exists longitude double precision;

-- Backfill from the existing JSON payload where present.
update course_geometries
set latitude  = coalesce(latitude,  (payload->>'latitude')::double precision),
    longitude = coalesce(longitude, (payload->>'longitude')::double precision)
where latitude is null or longitude is null;

create index if not exists course_geometries_coords_idx
    on course_geometries (latitude, longitude);
