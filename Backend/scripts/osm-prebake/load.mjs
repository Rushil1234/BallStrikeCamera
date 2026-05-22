#!/usr/bin/env node
// load.mjs — upsert already-baked NDJSON (from prebake.mjs --emit-all) into course_geometries.
// Dedupes holes by number and caps to 1–18, then upserts in batches via supabase-js.
//
// Usage: SUPABASE_URL=... SUPABASE_KEY=... node load.mjs <input.ndjson> [batchSize=25]

import fs from "node:fs";
import { createClient } from "@supabase/supabase-js";

const [input, batchArg] = process.argv.slice(2);
const URL = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_KEY;
if (!input || !URL || !KEY) {
  console.error("usage: SUPABASE_URL=.. SUPABASE_KEY=.. node load.mjs <input.ndjson> [batchSize]");
  process.exit(1);
}
const BATCH = batchArg ? parseInt(batchArg, 10) : 25;
const supabase = createClient(URL, KEY, { auth: { persistSession: false } });

function dedupeHoles(course) {
  const byNum = new Map();
  const hasPoly = (c) => !!(c.green_polygon && c.green_polygon.coordinates?.length >= 3);
  for (const h of course.holes) {
    if (!(h.number >= 1 && h.number <= 18)) continue;
    const e = byNum.get(h.number);
    if (!e || (!hasPoly(e) && hasPoly(h))) byNum.set(h.number, h);
  }
  course.holes = [...byNum.values()].sort((a, b) => a.number - b.number);
  return course;
}

function toRow(c) {
  dedupeHoles(c);
  return {
    course_id: c.id,
    course_name: c.name,
    city: c.city || "",
    state: c.state || "",
    source: "osm",
    geometry_state: "accepted",
    confidence: c.geometry_metadata?.confidence ?? 0.85,
    schema_version: 3,
    generated_by: "osm_prebake",
    validation_errors: [],
    latitude: c.latitude ?? null,
    longitude: c.longitude ?? null,
    payload: c,
    updated_at: new Date().toISOString(),
  };
}

const lines = fs.readFileSync(input, "utf8").split("\n").filter(Boolean);
const rows = lines.map((l) => toRow(JSON.parse(l)));
console.log(`loading ${rows.length} courses in batches of ${BATCH} …`);

let ok = 0;
for (let i = 0; i < rows.length; i += BATCH) {
  const chunk = rows.slice(i, i + BATCH);
  const { error } = await supabase
    .from("course_geometries")
    .upsert(chunk, { onConflict: "course_id" });
  if (error) {
    console.error(`batch ${i / BATCH | 0} failed: ${error.message}`);
    process.exit(1);
  }
  ok += chunk.length;
  console.log(`  upserted ${ok}/${rows.length}`);
}
console.log(`done. upserted ${ok} courses.`);
