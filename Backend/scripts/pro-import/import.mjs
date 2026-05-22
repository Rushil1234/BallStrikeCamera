#!/usr/bin/env node
// import.mjs — ingest licensed professional course data into Supabase.
//
// Reads the four feed tables (clubs, courses, tees, coordinates) as CSV, upserts them into the
// normalized pro_* tables (full fidelity), then derives the app-facing `course_geometries`
// GolfCourse JSON so the iOS app needs no rework. POIs (green F/C/B, tees, bunkers, water, doglegs)
// map onto the app's existing GolfHole geometry; a green polygon is synthesized from green F/C/B.
//
// Usage:
//   node import.mjs --dir ./samples [--dry-run] [--emit out.ndjson]
//   SUPABASE_URL=.. SUPABASE_KEY=<service-role> node import.mjs --dir /path/to/feed
//
// When the real feed is a REST API instead of CSV, replace loadCsvTables() with a fetch adapter
// that returns the same {clubs, courses, tees, coords} row arrays — everything downstream is reused.

import fs from "node:fs";
import path from "node:path";
import { createClient } from "@supabase/supabase-js";

const args = parseArgs(process.argv.slice(2));
const DIR = args.dir || "./samples";
const DRY = !!args["dry-run"];
const EMIT = args.emit;
const M_TO_Y = 1.0936133;

const supabase =
  !DRY && process.env.SUPABASE_URL && process.env.SUPABASE_KEY
    ? createClient(process.env.SUPABASE_URL, process.env.SUPABASE_KEY, { auth: { persistSession: false } })
    : null;
if (!DRY && !supabase) fail("SUPABASE_URL and SUPABASE_KEY required (or use --dry-run).");

main().catch((e) => fail(e.stack || String(e)));

async function main() {
  const { clubs, courses, tees, coords } = loadCsvTables(DIR);
  console.log(`[pro-import] clubs=${clubs.length} courses=${courses.length} tees=${tees.length} pois=${coords.length}`);

  const clubsById = index(clubs, "ClubID");
  const teesByCourse = group(tees, "CourseID");
  const poisByCourse = group(coords, "CourseID");

  // 1) Normalized pro_* tables (full fidelity).
  if (supabase) {
    await upsert("pro_clubs", clubs.map(clubRow), "club_id");
    await upsert("pro_courses", courses.map(courseRow), "course_id");
    await upsert("pro_tees", tees.map(teeRow), "tee_id");
    // POIs: replace per course to stay idempotent.
    for (const c of courses) {
      const rows = (poisByCourse[c.CourseID] || []).map((p) => poiRow(c.CourseID, p));
      if (!rows.length) continue;
      await supabase.from("pro_hole_pois").delete().eq("course_id", c.CourseID);
      await upsert("pro_hole_pois", rows, null);
    }
    console.log("[pro-import] normalized pro_* tables upserted");
  }

  // 2) App-facing course_geometries (GolfCourse JSON).
  const rows = [];
  for (const c of courses) {
    const club = clubsById[c.ClubID];
    const payload = buildGolfCourse(c, club, teesByCourse[c.CourseID] || [], poisByCourse[c.CourseID] || []);
    if (!payload) continue;
    if (EMIT) fs.appendFileSync(EMIT, JSON.stringify(payload) + "\n");
    rows.push(geometryRow(payload));
  }
  if (supabase && rows.length) {
    await upsert("course_geometries", rows, "course_id");
    console.log(`[pro-import] course_geometries upserted: ${rows.length}`);
  }
  console.log(`[pro-import] done. courses processed: ${rows.length}${DRY ? " (dry-run)" : ""}`);
}

// ── CSV loading ────────────────────────────────────────────────────────────

function loadCsvTables(dir) {
  return {
    clubs: parseCsv(read(dir, "clubs.csv")),
    courses: parseCsv(read(dir, "courses.csv")),
    tees: parseCsv(read(dir, "tees.csv")),
    coords: parseCsv(read(dir, "coordinates.csv")),
  };
}
function read(dir, name) {
  const p = path.join(dir, name);
  if (!fs.existsSync(p)) fail(`missing ${p}`);
  return fs.readFileSync(p, "utf8");
}

// Quote-aware CSV parser → array of header-keyed objects.
function parseCsv(text) {
  const rows = [];
  const lines = text.split(/\r?\n/);
  const header = splitCsvLine(lines[0]);
  for (let i = 1; i < lines.length; i++) {
    if (!lines[i]) continue;
    const cells = splitCsvLine(lines[i]);
    const obj = {};
    header.forEach((h, j) => (obj[h] = cells[j] ?? ""));
    rows.push(obj);
  }
  return rows;
}
function splitCsvLine(line) {
  const out = [];
  let cur = "";
  let inQ = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inQ) {
      if (ch === '"' && line[i + 1] === '"') { cur += '"'; i++; }
      else if (ch === '"') inQ = false;
      else cur += ch;
    } else if (ch === '"') inQ = true;
    else if (ch === ",") { out.push(cur); cur = ""; }
    else cur += ch;
  }
  out.push(cur);
  return out;
}

// ── Normalized row mappers ──────────────────────────────────────────────────

function clubRow(c) {
  return {
    club_id: c.ClubID, name: c.ClubName, address: c.Address, city: c.City,
    postal_code: c.PostalCode, state: c.State, country: c.Country, continent: c.Continent,
    latitude: numOrNull(c.Latitude), longitude: numOrNull(c.Longitude),
    website: c.Website || null, email: c.Email || null, telephone: c.Telephone || null,
    updated_at: new Date().toISOString(),
  };
}
function courseRow(c) {
  const arr = (prefix) => Array.from({ length: 18 }, (_, i) => intOr0(c[`${prefix}${i + 1}`]));
  return {
    course_id: c.CourseID, club_id: c.ClubID, long_course_id: c.LongCourseID || null,
    name: c.CourseName, num_holes: intOr0(c.NumHoles) || 18, measure_meters: c.MeasureMeters === "1",
    par_men: arr("Par"), par_women: arr("ParW"), hcp_men: arr("Hcp"), hcp_women: arr("HcpW"),
    match_index: arr("MatchIndex"), split_index: arr("SplitIndex"),
    source_updated: c.TimestampUpdated ? Number(c.TimestampUpdated) : null,
    updated_at: new Date().toISOString(),
  };
}
function teeRow(t) {
  return {
    tee_id: t.TeeID, course_id: t.CourseID, name: t.TeeName, color: t.TeeColor || null,
    measure_unit: (t.MeasureUnit || "y").toLowerCase(),
    slope: numOrNull(t.Slope), slope_front9: numOrNull(t.SlopeFront9), slope_back9: numOrNull(t.SlopeBack9),
    cr: numOrNull(t.CR), cr_front9: numOrNull(t.CRFront9), cr_back9: numOrNull(t.CRBack9),
    slope_women: numOrNull(t.SlopeWomen),
    slope_women_front9: numOrNull(t.SlopeWomenFront9),
    slope_women_back9: numOrNull(t.SlopeWomenBack ?? t.SlopeWomenBack9),
    cr_women: numOrNull(t.CRWomen),
    cr_women_front9: numOrNull(t.CRWomenFront9), cr_women_back9: numOrNull(t.CRWomenBack9),
    lengths: Array.from({ length: 18 }, (_, i) => intOr0(t[`Length${i + 1}`])),
    updated_at: new Date().toISOString(),
  };
}
function poiRow(courseId, p) {
  return {
    course_id: courseId, hole: intOr0(p.Hole), poi: p.POI, location: p.Location || null,
    side: p.SideOfFairway || null, latitude: numOrNull(p.Latitude), longitude: numOrNull(p.Longitude),
  };
}

// ── App-facing GolfCourse JSON ──────────────────────────────────────────────

function buildGolfCourse(course, club, tees, pois) {
  const courseId = course.CourseID;
  const numHoles = intOr0(course.NumHoles) || 18;
  const par = (n) => intOr0(course[`Par${n}`]);
  const hcp = (n) => intOr0(course[`Hcp${n}`]);

  // Group POIs by hole.
  const byHole = {};
  for (const p of pois) {
    const h = intOr0(p.Hole);
    (byHole[h] ||= []).push(p);
  }
  const findPOI = (list, poi, loc) =>
    list.find((p) => p.POI === poi && (loc == null || p.Location === loc));

  // Tee boxes (convert lengths to yards for the app).
  const teeBoxes = tees.map((t) => {
    const unit = (t.MeasureUnit || "y").toLowerCase();
    const k = unit === "m" ? M_TO_Y : 1;
    const total = Array.from({ length: numHoles }, (_, i) => intOr0(t[`Length${i + 1}`]))
      .reduce((s, v) => s + v, 0);
    return {
      id: `t${t.TeeID}`, name: t.TeeName || "Tee", color: hexToName(t.TeeColor),
      total_yards: Math.round(total * k),
      rating: numOrNull(t.CR), slope: numOrNull(t.Slope),
    };
  });
  const teeUnitFactor = (t) => ((t.MeasureUnit || "y").toLowerCase() === "m" ? M_TO_Y : 1);

  const holes = [];
  for (let n = 1; n <= numHoles; n++) {
    const list = byHole[n] || [];
    const gC = findPOI(list, "Green", "C");
    const gF = findPOI(list, "Green", "F");
    const gB = findPOI(list, "Green", "B");
    const teeBack = findPOI(list, "Tee Back") || findPOI(list, "Tee Front");
    if (!gC) continue; // need at least a green center to be playable
    const center = coord(gC);
    const front = gF ? coord(gF) : null;
    const back = gB ? coord(gB) : null;
    const tee = teeBack ? coord(teeBack) : null;
    const green = greenPolygon(front, center, back, tee);

    // Per-tee yardage + tee coordinate (one tee POI per hole → same coord for all tees).
    const teeYards = {};
    const teeCoordByBox = {};
    for (const t of tees) {
      const len = intOr0(t[`Length${n}`]);
      if (len > 0) teeYards[`t${t.TeeID}`] = Math.round(len * teeUnitFactor(t));
      if (tee) teeCoordByBox[`t${t.TeeID}`] = tee;
    }

    // Hazards / extra POIs.
    const hazards = [];
    for (const p of list) {
      const type = hazardType(p.POI);
      if (!type) continue;
      hazards.push({ id: `${courseId}-${n}-${p.POI}-${p.Location}-${p.SideOfFairway}`.replace(/\s+/g, "_"),
        type, name: p.POI, coordinate: coord(p) });
    }
    const dogleg = findPOI(list, "Dogleg");

    holes.push(clean({
      id: `${courseId}-hole-${n}`,
      course_id: courseId,
      number: n,
      par: par(n) || 4,
      handicap: hcp(n) || null,
      tee_yards_by_tee_box: teeYards,
      green_front_coordinate: front,
      green_center_coordinate: center,
      green_back_coordinate: back,
      tee_coordinate_by_tee_box: tee ? teeCoordByBox : null,
      path_coordinates: tee ? (dogleg ? [tee, coord(dogleg), center] : [tee, center]) : [center],
      hazards,
      tee_coordinate: tee,
      green_polygon: green ? { coordinates: green } : null,
      fairway_polygon: null,
      bunker_polygons: [],
      water_polygons: [],
    }));
  }
  if (!holes.length) return null;

  const lat = numOrNull(club?.Latitude) ?? center0(holes)?.lat ?? null;
  const lon = numOrNull(club?.Longitude) ?? center0(holes)?.lon ?? null;
  const now = new Date().toISOString();
  return {
    id: courseId,
    name: course.CourseName || club?.ClubName || "Golf Course",
    city: club?.City || "",
    state: club?.State || "",
    country: club?.Country || "",
    latitude: lat,
    longitude: lon,
    holes,
    tee_boxes: teeBoxes.length ? teeBoxes : [{ id: "gps", name: "Course GPS", color: "Gray", total_yards: 0 }],
    source: "merged",
    cached_at: now,
    course_polygon: null,
    geometry_metadata: {
      state: "accepted", confidence: 1.0, source: "pro_feed", schema_version: 3,
      generated_by: "pro_import", validation_errors: [], imagery_source: null, updated_at: now,
    },
  };
}

function geometryRow(p) {
  return {
    course_id: p.id, course_name: p.name, city: p.city, state: p.state,
    source: "pro", geometry_state: "accepted", confidence: 1.0, schema_version: 3,
    generated_by: "pro_import", validation_errors: [],
    latitude: p.latitude, longitude: p.longitude, payload: p, updated_at: new Date().toISOString(),
  };
}

// Build a green polygon from front/center/back, oriented along the green's long axis.
function greenPolygon(front, center, back, tee) {
  if (!center) return null;
  const f = front || center;
  const b = back || center;
  // Long axis bearing (front→back); fall back to tee→center.
  const axis = (front && back) ? bearing(f, b) : (tee ? bearing(tee, center) : 0);
  const halfWidth = Math.max(7, dist(f, b) * 0.35); // meters
  const left = project(center, axis - 90, halfWidth);
  const right = project(center, axis + 90, halfWidth);
  return [f, right, b, left, f];
}

// ── geo helpers ─────────────────────────────────────────────────────────────
function coord(p) { return { latitude: numOrNull(p.Latitude), longitude: numOrNull(p.Longitude) }; }
function center0(holes) { const c = holes[0]?.green_center_coordinate; return c ? { lat: c.latitude, lon: c.longitude } : null; }
function dist(a, b) {
  const R = 6371000, dLat = ((b.latitude - a.latitude) * Math.PI) / 180, dLon = ((b.longitude - a.longitude) * Math.PI) / 180;
  const la1 = (a.latitude * Math.PI) / 180, la2 = (b.latitude * Math.PI) / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(la1) * Math.cos(la2) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}
function bearing(a, b) {
  const la1 = (a.latitude * Math.PI) / 180, la2 = (b.latitude * Math.PI) / 180;
  const dLon = ((b.longitude - a.longitude) * Math.PI) / 180;
  const y = Math.sin(dLon) * Math.cos(la2);
  const x = Math.cos(la1) * Math.sin(la2) - Math.sin(la1) * Math.cos(la2) * Math.cos(dLon);
  return (Math.atan2(y, x) * 180) / Math.PI;
}
function project(c, brgDeg, m) {
  const R = 6371000, brg = (brgDeg * Math.PI) / 180, la1 = (c.latitude * Math.PI) / 180, lo1 = (c.longitude * Math.PI) / 180, ad = m / R;
  const la2 = Math.asin(Math.sin(la1) * Math.cos(ad) + Math.cos(la1) * Math.sin(ad) * Math.cos(brg));
  const lo2 = lo1 + Math.atan2(Math.sin(brg) * Math.sin(ad) * Math.cos(la1), Math.cos(ad) - Math.sin(la1) * Math.sin(la2));
  return { latitude: (la2 * 180) / Math.PI, longitude: (lo2 * 180) / Math.PI };
}

// ── misc ────────────────────────────────────────────────────────────────────
function hazardType(poi) {
  if (poi.includes("Bunker")) return "bunker";
  if (poi === "Water") return "water";
  if (poi === "Trees") return "trees";
  return null; // Green/Tee/Dogleg/Marker handled elsewhere
}
function hexToName(hex) {
  const map = { "#FFFFFF": "White", "#FFFF00": "Yellow", "#00CCFF": "Blue", "#FF5050": "Red",
    "#66FF66": "Green", "#CCCC00": "Gold", "#999999": "Black" };
  return map[(hex || "").toUpperCase()] || "White";
}
async function upsert(table, rows, onConflict) {
  for (let i = 0; i < rows.length; i += 200) {
    const chunk = rows.slice(i, i + 200);
    const opts = onConflict ? { onConflict } : undefined;
    const { error } = await supabase.from(table).upsert(chunk, opts);
    if (error) fail(`${table} upsert: ${error.message}`);
  }
}
function index(rows, key) { const m = {}; for (const r of rows) m[r[key]] = r; return m; }
function group(rows, key) { const m = {}; for (const r of rows) (m[r[key]] ||= []).push(r); return m; }
function numOrNull(v) { const n = parseFloat(v); return Number.isFinite(n) ? n : null; }
function intOr0(v) { const n = parseInt(v, 10); return Number.isFinite(n) ? n : 0; }
function clean(o) { for (const k of Object.keys(o)) if (o[k] === null) delete o[k]; return o; }
function parseArgs(a) { const o = {}; for (let i = 0; i < a.length; i++) { if (a[i].startsWith("--")) { const k = a[i].slice(2); const n = a[i + 1]; if (!n || n.startsWith("--")) o[k] = true; else { o[k] = n; i++; } } } return o; }
function fail(m) { console.error(`[pro-import] ${m}`); process.exit(1); }
