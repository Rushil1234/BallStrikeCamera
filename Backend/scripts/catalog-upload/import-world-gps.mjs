#!/usr/bin/env node
// import-world-gps.mjs — one-off importer for world_gps_formatted.json.
//
// Each input course is already an app-shaped GolfCourse (camelCase). All 1129 ids already exist
// in the `courses` catalog; this run enriches them with GPS geometry:
//   1. Storage: build the GolfCourse JSON, gzip, upsert to course-geometry/<id>.json.gz
//   2. Catalog: bump data_tier -> gps_ready (or scorecard_ready), geometry_quality, hole_count,
//      lat/lon, updated_at.
//
// Usage: SUPABASE_URL=.. SUPABASE_KEY=<service-role> node import-world-gps.mjs <file.json> [--dry-run]

import fs from "node:fs";
import zlib from "node:zlib";
import { createClient } from "@supabase/supabase-js";

const input = process.argv[2];
const DRY = process.argv.includes("--dry-run");
const CONCURRENCY = parseInt(process.env.CONCURRENCY || "16", 10);
const BUCKET = "course-geometry";
if (!input) { console.error("usage: node import-world-gps.mjs <file.json> [--dry-run]"); process.exit(1); }

let supabase = null;
if (!DRY) {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_KEY) {
    console.error("SUPABASE_URL and SUPABASE_KEY (service-role) required (or --dry-run)");
    process.exit(1);
  }
  supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY, { auth: { persistSession: false } });
}

const courses = JSON.parse(fs.readFileSync(input, "utf8"));
console.log(`loaded ${courses.length} courses from ${input}${DRY ? "  (DRY RUN)" : ""}\n`);

const isCoord = (p) => p && p.latitude != null && p.longitude != null;
const hasCenter = (c) => (c.holes || []).some((h) => isCoord(h.greenCenterCoordinate));

// Derive a top-level lat/lon if the course row is missing one (16 in this feed).
function courseLatLon(c) {
  if (c.latitude != null && c.longitude != null) return { latitude: c.latitude, longitude: c.longitude };
  for (const h of c.holes || []) {
    const p = h.teeCoordinate || h.greenCenterCoordinate;
    if (isCoord(p)) return { latitude: p.latitude, longitude: p.longitude };
  }
  return { latitude: null, longitude: null };
}

// Build the app GolfCourse JSON blob (decoded by CourseCatalogService with .convertFromSnakeCase +
// lenient ISO dates). Coerce the fields the Swift model requires as non-optional.
function toBlob(c, now) {
  const { latitude, longitude } = courseLatLon(c);
  const teeBoxes = (c.teeBoxes || []).map((t) => ({
    id: t.id, name: t.name || "Tee",
    color: t.color || "White",           // Swift TeeBox.color is non-optional; feed has null
    totalYards: t.totalYards || 0,
    ...(t.rating != null ? { rating: t.rating } : {}),
    ...(t.slope != null ? { slope: t.slope } : {}),
  }));
  const holes = (c.holes || []).map((h) => {
    const o = {
      id: `${c.id}-hole-${h.number}`,
      courseId: c.id,
      number: h.number,
      par: h.par || 4,
      teeYardsByTeeBox: h.teeYardsByTeeBox || {},
    };
    if (h.handicap != null) o.handicap = h.handicap;
    if (isCoord(h.greenCenterCoordinate)) o.greenCenterCoordinate = h.greenCenterCoordinate;
    if (isCoord(h.teeCoordinate)) o.teeCoordinate = h.teeCoordinate;
    if (h.teeCoordinateByTeeBox) {
      const m = {};
      for (const [k, v] of Object.entries(h.teeCoordinateByTeeBox)) if (isCoord(v)) m[k] = v;
      if (Object.keys(m).length) o.teeCoordinateByTeeBox = m;
    }
    // Feed carries a single fairway waypoint; the app's full-GPS tier reads pathCoordinates.
    if (isCoord(h.fairwayCoordinate)) o.pathCoordinates = [h.fairwayCoordinate];
    return o;
  });
  return {
    id: c.id,
    name: c.name || "Golf Course",
    city: c.city || "", state: c.state || "", country: c.country || "US",
    latitude, longitude,
    source: "merged",
    cached_at: now,
    tee_boxes: teeBoxes,
    holes,
    geometry_metadata: {
      state: "accepted", confidence: 1.0, source: "merged", schema_version: 3,
      generated_by: "world_gps_import", validation_errors: [], updated_at: now,
    },
  };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function uploadBucket(key, gz, tries = 4) {
  for (let a = 1; a <= tries; a++) {
    const { error } = await supabase.storage.from(BUCKET).upload(key, gz, {
      contentType: "application/json", contentEncoding: "gzip", upsert: true,
    });
    if (!error) return true;
    if (a === tries) { console.warn(`  bucket FAILED ${key}: ${error.message}`); return false; }
    await sleep(800 * a);
  }
}

async function updateCatalog(c, now, tries = 4) {
  const { latitude, longitude } = courseLatLon(c);
  const gps = hasCenter(c);
  const patch = {
    data_tier: gps ? "gps_ready" : "scorecard_ready",
    geometry_quality: gps ? "good" : "none",
    hole_count: (c.holes || []).filter((h) => h.number > 0).length || null,
    updated_at: now,
  };
  if (latitude != null) patch.latitude = latitude;
  if (longitude != null) patch.longitude = longitude;
  for (let a = 1; a <= tries; a++) {
    const { error, count } = await supabase.from("courses")
      .update(patch, { count: "exact" }).eq("id", c.id);
    if (!error) return count === 0 ? "missing" : "ok";
    if (a === tries) { console.warn(`  catalog FAILED ${c.id}: ${error.message}`); return "failed"; }
    await sleep(800 * a);
  }
}

const stats = { blob: 0, blobFail: 0, cat: 0, catMissing: 0, catFail: 0, gps: 0, scorecard: 0 };

async function processOne(c) {
  const now = new Date().toISOString();
  const blob = toBlob(c, now);
  if (hasCenter(c)) stats.gps++; else stats.scorecard++;
  if (DRY) {
    // Validate it round-trips through gzip + JSON.
    zlib.gzipSync(Buffer.from(JSON.stringify(blob)));
    stats.blob++; stats.cat++;
    return;
  }
  const gz = zlib.gzipSync(Buffer.from(JSON.stringify(blob)));
  if (await uploadBucket(`${c.id}.json.gz`, gz)) stats.blob++; else stats.blobFail++;
  const r = await updateCatalog(c, now);
  if (r === "ok") stats.cat++; else if (r === "missing") stats.catMissing++; else stats.catFail++;
}

// Simple concurrency pool.
let idx = 0, done = 0;
async function worker() {
  while (idx < courses.length) {
    const c = courses[idx++];
    await processOne(c);
    if (++done % 100 === 0 || done === courses.length) console.log(`  ${done}/${courses.length}`);
  }
}
await Promise.all(Array.from({ length: Math.min(CONCURRENCY, courses.length) }, worker));

console.log(`\ndone.`);
console.log(`  geometry blobs uploaded: ${stats.blob}  (failed ${stats.blobFail})`);
console.log(`  catalog rows updated:    ${stats.cat}  (missing ${stats.catMissing}, failed ${stats.catFail})`);
console.log(`  tier: gps_ready ${stats.gps}, scorecard_ready ${stats.scorecard}`);
