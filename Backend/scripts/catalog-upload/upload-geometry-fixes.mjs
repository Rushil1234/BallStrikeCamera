#!/usr/bin/env node
// upload-geometry-fixes.mjs — push pre-built GolfCourse JSON fixes (corrected coordinates) into
// the live backend. Each input file is `<course_id>.json.gz`, already in v3 GolfCourse shape.
//
// Two passes, both idempotent (safe to re-run):
//   1. Storage: upsert <course_id>.json.gz into the `course-geometry` bucket (overwrites bad blob).
//   2. Catalog: UPDATE courses.latitude/longitude (+ data_tier='gps_ready') from each file's
//      top-level coords so proximity/search ranking matches the fixed geometry.
//
// Usage:
//   SUPABASE_URL=.. SUPABASE_KEY=<service-role> node upload-geometry-fixes.mjs <dir> [flags]
// Flags:
//   --dry-run        parse + validate every file, touch nothing remote
//   --bucket-only    only pass 1 (Storage)
//   --catalog-only   only pass 2 (courses table)
// Env:
//   CONCURRENCY=32   parallel operations per pass

import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { createClient } from "@supabase/supabase-js";

const DIR = process.argv[2];
const DRY = process.argv.includes("--dry-run");
const BUCKET_ONLY = process.argv.includes("--bucket-only");
const CATALOG_ONLY = process.argv.includes("--catalog-only");
const DO_BUCKET = !CATALOG_ONLY;
const DO_CATALOG = !BUCKET_ONLY;
const BUCKET = "course-geometry";
const CONCURRENCY = parseInt(process.env.CONCURRENCY || "32", 10);

if (!DIR) { console.error("usage: node upload-geometry-fixes.mjs <dir> [--dry-run|--bucket-only|--catalog-only]"); process.exit(1); }
if (!fs.existsSync(DIR)) { console.error(`dir not found: ${DIR}`); process.exit(1); }

let supabase = null;
if (!DRY) {
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_KEY) {
    console.error("SUPABASE_URL and SUPABASE_KEY (service-role) required (or pass --dry-run)");
    process.exit(1);
  }
  supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY, { auth: { persistSession: false } });
}

const files = fs.readdirSync(DIR).filter((f) => f.endsWith(".json.gz"));
console.log(`found ${files.length} .json.gz files in ${DIR}`);
console.log(`passes: ${DO_BUCKET ? "bucket " : ""}${DO_CATALOG ? "catalog" : ""}${DRY ? "  (DRY RUN)" : ""}\n`);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Read a fix file → { key, gz, id, latitude, longitude }. Validates id matches filename.
function readFix(file) {
  const gz = fs.readFileSync(path.join(DIR, file));
  const json = JSON.parse(zlib.gunzipSync(gz).toString("utf8"));
  const id = json.id;
  const fileId = file.replace(/\.json\.gz$/, "");
  if (id !== fileId) throw new Error(`id mismatch: file ${fileId} vs payload ${id}`);
  if (json.latitude == null || json.longitude == null) throw new Error(`missing top-level lat/lon for ${id}`);
  return { key: file, gz, id, latitude: json.latitude, longitude: json.longitude };
}

async function uploadBucket(fix, tries = 4) {
  for (let a = 1; a <= tries; a++) {
    const { error } = await supabase.storage.from(BUCKET).upload(fix.key, fix.gz, {
      contentType: "application/json", contentEncoding: "gzip", upsert: true,
    });
    if (!error) return true;
    if (a === tries) { console.warn(`  bucket FAILED ${fix.key}: ${error.message}`); return false; }
    await sleep(800 * a);
  }
}

async function updateCatalog(fix, tries = 4) {
  for (let a = 1; a <= tries; a++) {
    const { error, count } = await supabase
      .from("courses")
      .update({ latitude: fix.latitude, longitude: fix.longitude, data_tier: "gps_ready", updated_at: new Date().toISOString() }, { count: "exact" })
      .eq("id", fix.id);
    if (!error) return count === 0 ? "missing" : "ok";
    if (a === tries) { console.warn(`  catalog FAILED ${fix.id}: ${error.message}`); return "failed"; }
    await sleep(800 * a);
  }
}

// Bounded-concurrency pool over files.
async function runPass(label, worker) {
  let done = 0, ok = 0, fail = 0, missing = 0, parseErr = 0;
  const inflight = new Set();
  for (const file of files) {
    const p = (async () => {
      let fix; try { fix = readFix(file); } catch (e) { parseErr++; console.warn(`  parse ${file}: ${e.message}`); return; }
      if (DRY) { ok++; return; }
      const r = await worker(fix);
      if (r === "missing") missing++; else if (r === true || r === "ok") ok++; else fail++;
    })().then(() => {
      done++;
      if (done % 500 === 0) console.log(`  [${label}] ${done}/${files.length}  ok=${ok} fail=${fail}${missing ? ` missing=${missing}` : ""}`);
      inflight.delete(p);
    });
    inflight.add(p);
    if (inflight.size >= CONCURRENCY) await Promise.race(inflight);
  }
  await Promise.allSettled(inflight);
  console.log(`[${label}] done: ok=${ok} fail=${fail} missing=${missing} parseErr=${parseErr}\n`);
  return { ok, fail, missing, parseErr };
}

if (DO_BUCKET)  await runPass("bucket",  uploadBucket);
if (DO_CATALOG) await runPass("catalog", updateCatalog);
console.log(DRY ? "dry run complete — nothing written." : "complete.");
