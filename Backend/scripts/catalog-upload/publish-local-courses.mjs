#!/usr/bin/env node
// publish-local-courses.mjs — publish a hand-labeled course (label-editor.html export)
// to the Supabase catalog: gzip a full-geometry GolfCourse blob -> course-geometry/<id>.json.gz
// and upsert the searchable `courses` row. Keeps fairway/green/bunker/water POLYGONS (unlike
// import-world-gps.mjs, whose source feed had none) — the app's CatalogGeometry decoder reads them.
//
// Usage:
//   node publish-local-courses.mjs [--dry-run]            # validate + write local .gz, no network
//   SUPABASE_URL=.. SUPABASE_KEY=<service-role> node publish-local-courses.mjs   # publish
//
// The catalog id is a deterministic UUIDv5 of the slug (same NS as upload-courses.mjs) so re-runs
// are idempotent.

import fs from "node:fs";
import zlib from "node:zlib";
import crypto from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dir = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(__dir, "../../..");
const OUTDIR = "/private/tmp/claude-501/-Users-noahtobias-Downloads-BallStrikeCamera/b0b5f29a-6b67-436d-a092-c2d10e6d5d28/scratchpad";
const DRY = process.argv.includes("--dry-run") || !(process.env.SUPABASE_URL && process.env.SUPABASE_KEY);
const BUCKET = "course-geometry";

// --- one entry per bundled course: the resource + the scorecard facts the editor can't hold ---
const SPECS = [
  {
    // Reuse the course's existing catalog slug so this upgrades the canonical row in place
    // (uuidv5 -> b08b6a52…) instead of creating a duplicate search result.
    slug: "us-lake-lackawanna-golf-course",
    labelFile: path.join(REPO, "BallStrikeCamera/Resources/Courses/lake_lackawanna.json"),
    name: "Lake Lackawanna Golf Course",
    city: "Byram Township", state: "NJ",
    attribution: "Hand-labeled from aerial imagery (NJOGIS / Esri)",
    tee: { id: "White", name: "White", color: "White", totalYards: 2240,
           rating: 33.1, slope: 79, womens_rating: 34.9, womens_slope: 83 },
  },
];

const NS = "6f9619ff-8b86-d011-b42d-00cf4fc964ff";
function uuidv5(name, ns = NS) {
  const nsBytes = Buffer.from(ns.replace(/-/g, ""), "hex");
  const hash = crypto.createHash("sha1").update(Buffer.concat([nsBytes, Buffer.from(name)])).digest();
  const b = Buffer.from(hash.subarray(0, 16));
  b[6] = (b[6] & 0x0f) | 0x50;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = b.toString("hex");
  return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;
}

const isCoord = (p) => p && p.latitude != null && p.longitude != null;

function build(spec) {
  const label = JSON.parse(fs.readFileSync(spec.labelFile, "utf8"));
  const id = uuidv5(spec.slug);
  const now = new Date().toISOString();
  const center = label.center || {};

  const holes = (label.holes || []).map((h) => {
    const o = {
      id: `${id}-hole-${h.number}`, courseId: id,
      number: h.number, par: h.par || 4,
      teeYardsByTeeBox: h.teeYardsByTeeBox || {},
    };
    if (h.handicap != null) o.handicap = h.handicap;
    if (isCoord(h.teeCoordinate)) o.teeCoordinate = h.teeCoordinate;
    if (h.teeCoordinateByTeeBox) o.teeCoordinateByTeeBox = h.teeCoordinateByTeeBox;
    if (isCoord(h.greenFrontCoordinate)) o.greenFrontCoordinate = h.greenFrontCoordinate;
    if (isCoord(h.greenCenterCoordinate)) o.greenCenterCoordinate = h.greenCenterCoordinate;
    if (isCoord(h.greenBackCoordinate)) o.greenBackCoordinate = h.greenBackCoordinate;
    // Par 4/5 need a tee->green route for the GPS-map tier; straight line when none was drawn.
    let path = h.pathCoordinates;
    if ((!path || !path.length) && o.par >= 4 && isCoord(h.teeCoordinate) && isCoord(h.greenCenterCoordinate)) {
      path = [h.teeCoordinate, h.greenCenterCoordinate];
    }
    if (path && path.length) o.pathCoordinates = path;
    if (h.greenPolygon) o.greenPolygon = h.greenPolygon;
    if (h.fairwayPolygon) o.fairwayPolygon = h.fairwayPolygon;
    if (h.bunkerPolygons && h.bunkerPolygons.length) o.bunkerPolygons = h.bunkerPolygons;
    if (h.waterPolygons && h.waterPolygons.length) o.waterPolygons = h.waterPolygons;
    return o;
  });

  const blob = {
    id, name: spec.name,
    city: spec.city || label.city || "", state: spec.state || label.state || "", country: "US",
    latitude: center.latitude ?? null, longitude: center.longitude ?? null,
    source: "merged", cached_at: now,
    tee_boxes: [spec.tee],
    holes,
    geometry_metadata: {
      state: "accepted", confidence: 1.0, source: "manual_label", schema_version: 3,
      generated_by: "label-editor", validation_errors: [], updated_at: now,
    },
  };

  const row = {
    id, source_system: "manual", source_id: spec.slug, slug: spec.slug,
    name: spec.name, normalized_name: spec.name.toLowerCase().trim(),
    city: spec.city, state: spec.state, country: "US",
    latitude: center.latitude ?? null, longitude: center.longitude ?? null,
    hole_count: holes.filter((h) => h.number > 0).length,
    status: "active", data_tier: "gps_ready", geometry_quality: "good",
    attribution: spec.attribution, updated_at: now,
  };

  return { id, blob, row };
}

let supabase = null;
if (!DRY) {
  const { createClient } = await import("@supabase/supabase-js");
  supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY, { auth: { persistSession: false } });
}

for (const spec of SPECS) {
  const { id, blob, row } = build(spec);
  const gz = zlib.gzipSync(Buffer.from(JSON.stringify(blob)));
  // sanity: round-trips
  JSON.parse(zlib.gunzipSync(gz).toString());
  const localGz = path.join(OUTDIR, `${spec.slug}.${id}.json.gz`);
  fs.writeFileSync(localGz, gz);

  console.log(`\n=== ${spec.name} ===`);
  console.log(`  slug:        ${spec.slug}`);
  console.log(`  catalog id:  ${id}`);
  console.log(`  holes:       ${blob.holes.length}  (fairway polys: ${blob.holes.filter(h=>h.fairwayPolygon).length}, green polys: ${blob.holes.filter(h=>h.greenPolygon).length}, water: ${blob.holes.reduce((n,h)=>n+(h.waterPolygons?.length||0),0)})`);
  console.log(`  tee:         ${spec.tee.name} ${spec.tee.totalYards}y  rating ${spec.tee.rating}/slope ${spec.tee.slope}`);
  console.log(`  gz size:     ${gz.length} bytes  -> ${localGz}`);
  console.log(`  bucket key:  ${BUCKET}/${id}.json.gz`);

  if (DRY) { console.log("  [dry-run] no upload."); continue; }

  const up = await supabase.storage.from(BUCKET).upload(`${id}.json.gz`, gz, {
    contentType: "application/json", contentEncoding: "gzip", upsert: true,
  });
  if (up.error) { console.error(`  bucket upload FAILED: ${up.error.message}`); process.exit(1); }
  console.log("  ✓ geometry uploaded");

  const { error: rowErr } = await supabase.from("courses").upsert([row], { onConflict: "id" });
  if (rowErr) { console.error(`  courses upsert FAILED: ${rowErr.message}`); process.exit(1); }
  console.log("  ✓ catalog row upserted");

  // verify: re-fetch the row + confirm the object exists
  const { data: check } = await supabase.from("courses").select("id,name,data_tier,latitude").eq("id", id).single();
  console.log(`  ✓ verified row: ${check?.name} · ${check?.data_tier}`);
}

console.log(`\n${DRY ? "DRY RUN complete — set SUPABASE_URL + SUPABASE_KEY (service-role) to publish." : "PUBLISHED."}`);
