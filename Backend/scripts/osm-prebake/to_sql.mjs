#!/usr/bin/env node
// to_sql.mjs — convert baked NDJSON (from `prebake.mjs --emit-all`) into chunked upsert SQL
// files for `course_geometries`, so they can be applied via the Supabase MCP tools (which write
// with elevated rights, no service-role key in the script).
//
// Usage: node to_sql.mjs <input.ndjson> <outDir> [batchSize=12]

import fs from "node:fs";
import path from "node:path";

const [input, outDir, batchArg] = process.argv.slice(2);
if (!input || !outDir) {
  console.error("usage: node to_sql.mjs <input.ndjson> <outDir> [batchSize]");
  process.exit(1);
}
const BATCH = batchArg ? parseInt(batchArg, 10) : 12;
fs.mkdirSync(outDir, { recursive: true });

const q = (s) => "'" + String(s ?? "").replace(/'/g, "''") + "'";
const jb = (obj) => "'" + JSON.stringify(obj).replace(/'/g, "''") + "'::jsonb";
const num = (n) => (n == null || Number.isNaN(n) ? "null" : String(n));

// Dedupe holes by number (multi-nine facilities tag repeated refs / extra greens), preferring a
// hole that has a real traced green polygon, then cap to 1–18 so rounds aren't malformed.
function dedupeHoles(course) {
  const byNum = new Map();
  for (const h of course.holes) {
    if (!(h.number >= 1 && h.number <= 18)) continue;
    const existing = byNum.get(h.number);
    const hasPoly = (c) => !!(c.green_polygon && c.green_polygon.coordinates?.length >= 3);
    if (!existing || (!hasPoly(existing) && hasPoly(h))) byNum.set(h.number, h);
  }
  course.holes = [...byNum.values()].sort((a, b) => a.number - b.number);
  return course;
}

const lines = fs.readFileSync(input, "utf8").split("\n").filter(Boolean);
let batchIdx = 0;
let total = 0;
for (let i = 0; i < lines.length; i += BATCH) {
  const rows = lines.slice(i, i + BATCH).map((l) => {
    const c = dedupeHoles(JSON.parse(l));
    return `(${q(c.id)}, ${q(c.name)}, ${q(c.city)}, ${q(c.state)}, 'osm', 'accepted', ${num(
      c.geometry_metadata?.confidence
    )}, 3, 'osm_prebake', '[]'::jsonb, ${num(c.latitude)}, ${num(c.longitude)}, ${jb(c)}, now())`;
  });
  const sql =
    `insert into course_geometries\n` +
    `  (course_id, course_name, city, state, source, geometry_state, confidence, schema_version, generated_by, validation_errors, latitude, longitude, payload, updated_at)\n` +
    `values\n  ${rows.join(",\n  ")}\n` +
    `on conflict (course_id) do update set\n` +
    `  course_name = excluded.course_name, city = excluded.city, state = excluded.state,\n` +
    `  payload = excluded.payload, latitude = excluded.latitude, longitude = excluded.longitude,\n` +
    `  geometry_state = 'accepted', confidence = excluded.confidence, updated_at = now();\n`;
  const file = path.join(outDir, `batch_${String(batchIdx).padStart(3, "0")}.sql`);
  fs.writeFileSync(file, sql);
  total += rows.length;
  batchIdx++;
}
console.log(`wrote ${batchIdx} batch files, ${total} courses, to ${outDir}`);
