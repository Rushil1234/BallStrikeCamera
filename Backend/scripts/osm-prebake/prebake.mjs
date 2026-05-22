#!/usr/bin/env node
// prebake.mjs
//
// Bulk-populate Supabase `course_geometries` with free, non-proprietary golf geometry derived
// from OpenStreetMap (ODbL) + optional GolfCourseAPI scorecards. The app reads `accepted` rows
// from this table first (CourseDataAggregator.loadSharedGeometry), so a course pre-baked here
// plays in rangefinder/full-GPS mode without any live Overpass call.
//
// Pipeline per run:
//   1. Enumerate `leisure=golf_course` features in a US state via the Overpass API (free).
//   2. For each course, fetch nearby greens/tees/holes/pins (mirrors the in-app query).
//   3. Infer holes (geometry.mjs — same logic as the iOS HoleInference), synthesize green
//      polygons from centers where OSM didn't trace them.
//   4. Optionally match GolfCourseAPI for par/handicap/yardages + tee boxes.
//   5. Upsert a snake_case GolfCourse payload (matching the Swift Codable shape) with
//      geometry_state='accepted', source='osm', generated_by='osm_prebake'.
//
// Usage:
//   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... [GOLFCOURSEAPI_KEY=...] \
//     node prebake.mjs --state "Pennsylvania" [--limit 50] [--dry-run] [--min-greens 9]
//
// Run a small --limit / --dry-run first. Be polite to Overpass: the script throttles requests.

import { createClient } from "@supabase/supabase-js";
import { inferHoles, centroid, yardsBetween } from "./geometry.mjs";

// ---- args / env -----------------------------------------------------------

const args = parseArgs(process.argv.slice(2));
const STATE = args.state;
const BBOX = args.bbox; // "south,west,north,east"
const LIMIT = args.limit ? parseInt(args.limit, 10) : Infinity;
const MIN_GREENS = args["min-greens"] ? parseInt(args["min-greens"], 10) : 9;
const DRY_RUN = !!args["dry-run"];
const OVERPASS_URL = process.env.OVERPASS_URL || "https://overpass-api.de/api/interpreter";
const PER_COURSE_RADIUS_M = 1600;
const THROTTLE_MS = 1500;

if (!STATE && !BBOX) {
  fail('Provide --state "Pennsylvania" or --bbox "s,w,n,e".');
}

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const GCA_KEY = process.env.GOLFCOURSEAPI_KEY;

if (!DRY_RUN && (!SUPABASE_URL || !SERVICE_KEY)) {
  fail("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required unless --dry-run.");
}

const supabase =
  !DRY_RUN && SUPABASE_URL
    ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } })
    : null;

// ---- main -----------------------------------------------------------------

main().catch((e) => fail(e.stack || String(e)));

async function main() {
  console.log(`[prebake] enumerating golf courses for ${STATE || BBOX} …`);
  const courses = await enumerateCourses();
  console.log(`[prebake] found ${courses.length} golf_course features`);

  let baked = 0;
  let skipped = 0;
  for (const course of courses) {
    if (baked >= LIMIT) break;
    try {
      const result = await bakeCourse(course);
      if (!result) {
        skipped++;
        continue;
      }
      if (DRY_RUN) {
        console.log(`[dry-run] ${result.name} — ${result.holes.length} holes`);
        if (args.print && baked === 0) console.log(JSON.stringify(result.holes[0], null, 2));
        if (args.emit && baked === 0) {
          const fs = await import("node:fs");
          fs.writeFileSync(args.emit, JSON.stringify(result));
          console.log(`[emit] wrote ${args.emit}`);
        }
        if (args["emit-all"]) {
          const fs = await import("node:fs");
          fs.appendFileSync(args["emit-all"], JSON.stringify(result) + "\n");
        }
      } else {
        await upsert(result);
        console.log(`[ok] ${result.name} — ${result.holes.length} holes`);
      }
      baked++;
    } catch (e) {
      skipped++;
      console.warn(`[skip] ${course.name || course.id}: ${e.message}`);
    }
    await sleep(THROTTLE_MS);
  }
  console.log(`[prebake] done. baked=${baked} skipped=${skipped}`);
}

// ---- step 1: enumerate courses -------------------------------------------

async function enumerateCourses() {
  const filter = BBOX
    ? `(${BBOX})`
    : ""; // bbox handled below
  let query;
  if (BBOX) {
    const b = BBOX;
    query = `[out:json][timeout:90];
      ( way["leisure"="golf_course"](${b}); relation["leisure"="golf_course"](${b}); );
      out center tags;`;
  } else {
    query = `[out:json][timeout:120];
      area["name"="${STATE}"]["boundary"="administrative"]->.a;
      ( way["leisure"="golf_course"](area.a); relation["leisure"="golf_course"](area.a); );
      out center tags;`;
  }
  void filter;
  const elements = await overpass(query);
  return elements
    .filter((e) => e.center || (e.lat && e.lon))
    .map((e) => {
      const lat = e.center ? e.center.lat : e.lat;
      const lon = e.center ? e.center.lon : e.lon;
      const tags = e.tags || {};
      return {
        id: `osm-${e.type}-${e.id}`,
        name: tags.name || tags["name:en"] || "Unknown Golf Course",
        lat,
        lon,
        tags,
      };
    })
    .filter((c) => c.name !== "Unknown Golf Course" || true);
}

// ---- step 2-4: bake one course -------------------------------------------

async function bakeCourse(course) {
  const query = `[out:json][timeout:60];
    ( way["golf"="green"](around:${PER_COURSE_RADIUS_M},${course.lat},${course.lon});
      way["golf"="tee"](around:${PER_COURSE_RADIUS_M},${course.lat},${course.lon});
      way["golf"="fairway"](around:${PER_COURSE_RADIUS_M},${course.lat},${course.lon});
      way["golf"="hole"](around:${PER_COURSE_RADIUS_M},${course.lat},${course.lon});
      node["golf"="pin"](around:${PER_COURSE_RADIUS_M},${course.lat},${course.lon});
    );
    out body; >; out skel qt;`;
  const elements = await overpass(query);
  const classified = classify(elements);
  if (classified.greens.length < MIN_GREENS) {
    throw new Error(`only ${classified.greens.length} greens (< ${MIN_GREENS})`);
  }

  const holes = inferHoles(classified);
  // Keep holes 1–18 only, and dedupe by number — extra "holes" are usually practice greens, and
  // multi-nine facilities tag repeated refs; either makes a malformed round downstream.
  const byNum = new Map();
  for (const h of holes) {
    if (!(h.center && h.number >= 1 && h.number <= 18)) continue;
    if (!byNum.has(h.number) || (!byNum.get(h.number).polygon && h.polygon)) byNum.set(h.number, h);
  }
  const usable = [...byNum.values()].sort((a, b) => a.number - b.number);
  if (usable.length < MIN_GREENS) {
    throw new Error(`only ${usable.length} usable holes`);
  }

  // Optional scorecard from GolfCourseAPI.
  let scorecard = null;
  if (GCA_KEY) {
    scorecard = await fetchScorecard(course).catch(() => null);
  }

  return buildPayload(course, usable, scorecard);
}

function classify(elements) {
  const nodes = new Map();
  for (const e of elements) {
    if (e.type === "node" && e.lat != null) nodes.set(e.id, { lat: e.lat, lon: e.lon });
  }
  const ways = new Map();
  for (const e of elements) {
    if (e.type === "way" && e.nodes) {
      const coords = e.nodes.map((id) => nodes.get(id)).filter(Boolean);
      if (coords.length >= 2) ways.set(e.id, { coords, tags: e.tags || {} });
    }
  }
  const out = { greens: [], tees: [], fairways: [], holeWays: [], pins: [] };
  for (const e of elements) {
    if (e.type === "node" && e.tags && e.tags.golf === "pin" && e.lat != null) {
      out.pins.push({ lat: e.lat, lon: e.lon });
    }
  }
  for (const [, w] of ways) {
    const g = w.tags.golf;
    if (g === "green") out.greens.push({ coords: w.coords });
    else if (g === "tee") out.tees.push({ coords: w.coords });
    else if (g === "fairway") out.fairways.push({ coords: w.coords });
    else if (g === "hole")
      out.holeWays.push({
        coords: w.coords,
        ref: w.tags.ref ? parseInt(w.tags.ref, 10) : null,
        par: w.tags.par ? parseInt(w.tags.par, 10) : null,
      });
  }
  return out;
}

// ---- step 5: build snake_case GolfCourse payload -------------------------

function buildPayload(course, holes, scorecard) {
  const now = new Date().toISOString();
  const teeBoxes = scorecard?.teeBoxes?.length
    ? scorecard.teeBoxes
    : [{ id: "gps", name: "Course GPS", color: "Gray", total_yards: 0 }];

  const scByNumber = new Map((scorecard?.holes || []).map((h) => [h.number, h]));

  const payloadHoles = holes.map((h) => {
    const sc = scByNumber.get(h.number);
    const teeYards = {};
    if (sc?.yardage) for (const t of teeBoxes) teeYards[t.id] = sc.yardage;
    const teeCoordByBox = {};
    if (h.tee) for (const t of teeBoxes) teeCoordByBox[t.id] = coord(h.tee);
    return clean({
      id: `${course.id}-hole-${h.number}`,
      course_id: course.id,
      number: h.number,
      par: sc?.par ?? h.par,
      handicap: sc?.handicap ?? null,
      tee_yards_by_tee_box: teeYards,
      green_front_coordinate: h.front ? coord(h.front) : null,
      green_center_coordinate: coord(h.center),
      green_back_coordinate: h.back ? coord(h.back) : null,
      tee_coordinate_by_tee_box: h.tee ? teeCoordByBox : null,
      path_coordinates: (h.path || []).map(coord),
      hazards: [],
      tee_coordinate: h.tee ? coord(h.tee) : null,
      green_polygon: h.polygon ? { coordinates: h.polygon.map(coord) } : null,
      fairway_polygon: null,
      bunker_polygons: [],
      water_polygons: [],
    });
  });

  return {
    id: course.id,
    name: scorecard?.name || course.name,
    city: scorecard?.city || "",
    state: scorecard?.state || STATE || "",
    country: "US",
    latitude: course.lat,
    longitude: course.lon,
    holes: payloadHoles,
    tee_boxes: teeBoxes,
    source: scorecard ? "merged" : "openStreetMap",
    cached_at: now,
    course_polygon: null,
    geometry_metadata: {
      state: "accepted",
      confidence: scorecard ? 1.0 : 0.85,
      source: "osm",
      schema_version: 3,
      generated_by: "osm_prebake",
      validation_errors: [],
      imagery_source: null,
      updated_at: now,
    },
  };
}

function coord(c) {
  return { latitude: c.lat, longitude: c.lon };
}

// ---- Supabase upsert ------------------------------------------------------

async function upsert(payload) {
  const row = {
    course_id: payload.id,
    course_name: payload.name,
    city: payload.city,
    state: payload.state,
    source: "osm",
    geometry_state: "accepted",
    confidence: payload.geometry_metadata.confidence,
    schema_version: payload.geometry_metadata.schema_version,
    generated_by: "osm_prebake",
    validation_errors: [],
    latitude: payload.latitude,
    longitude: payload.longitude,
    payload,
    updated_at: new Date().toISOString(),
  };
  const { error } = await supabase
    .from("course_geometries")
    .upsert(row, { onConflict: "course_id" });
  if (error) throw new Error(`supabase upsert: ${error.message}`);
}

// ---- GolfCourseAPI scorecard ---------------------------------------------

async function fetchScorecard(course) {
  const res = await fetch(
    `https://api.golfcourseapi.com/v1/search?search_query=${encodeURIComponent(course.name)}`,
    { headers: { Authorization: `Key ${GCA_KEY}`, Accept: "application/json" } }
  );
  if (!res.ok) throw new Error(`GCA search ${res.status}`);
  const data = await res.json();
  const list = data.courses || [];
  const best = pickBest(list, course);
  if (!best) return null;

  let full = best;
  if (!best.holes || !best.holes.length) {
    const dr = await fetch(`https://api.golfcourseapi.com/v1/courses/${best.id}`, {
      headers: { Authorization: `Key ${GCA_KEY}`, Accept: "application/json" },
    });
    if (dr.ok) full = (await dr.json()).course || best;
  }
  return normalizeScorecard(full);
}

function pickBest(list, course) {
  if (!list.length) return null;
  const origin = { lat: course.lat, lon: course.lon };
  let best = null;
  let bestScore = Infinity;
  for (const c of list) {
    const loc = c.location || {};
    const name = c.club_name || c.course_name || "";
    let penalty = 0;
    if (!namesOverlap(name, course.name)) penalty += 3000;
    const dist =
      loc.latitude != null
        ? yardsBetween(origin, { lat: loc.latitude, lon: loc.longitude }) * 0.9144
        : 8000;
    const score = dist + penalty;
    if (score < bestScore) {
      bestScore = score;
      best = c;
    }
  }
  return best;
}

function normalizeScorecard(raw) {
  const teesRaw = [...(raw.tees?.male || []), ...(raw.tees?.female || [])];
  const teeBoxes = teesRaw.length
    ? teesRaw.map((t, i) => ({
        id: `tee${i}`,
        name: t.tee_name || t.name || `Tee ${i + 1}`,
        color: t.tee_color || "White",
        total_yards: t.total_yards || t.total_distance || 0,
        rating: t.course_rating ?? null,
        slope: t.slope_rating ?? null,
      }))
    : [{ id: "gps", name: "Course GPS", color: "Gray", total_yards: 0 }];

  const holeSource = raw.holes || teesRaw[0]?.holes || [];
  const holes = holeSource.map((h, i) => ({
    number: h.hole_number ?? h.number ?? i + 1,
    par: h.par ?? 4,
    handicap: h.handicap ?? null,
    yardage: h.yardage ?? h.yards ?? h.distance ?? null,
  }));

  return {
    name: raw.club_name || raw.course_name || "",
    city: raw.location?.city || "",
    state: raw.location?.state || "",
    teeBoxes,
    holes,
  };
}

function namesOverlap(a, b) {
  const ignored = new Set(["the", "golf", "club", "course", "country", "links"]);
  const toks = (s) =>
    new Set(
      s
        .toLowerCase()
        .split(/[^a-z0-9]+/)
        .filter((w) => w.length > 2 && !ignored.has(w))
    );
  const sa = toks(a);
  const sb = toks(b);
  for (const t of sa) if (sb.has(t)) return true;
  return false;
}

// ---- helpers --------------------------------------------------------------

async function overpass(query) {
  const res = await fetch(OVERPASS_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": "TrueCarry-prebake" },
    body: "data=" + encodeURIComponent(query),
  });
  if (res.status === 429 || res.status === 504) {
    await sleep(5000);
    return overpass(query);
  }
  if (!res.ok) throw new Error(`overpass ${res.status}`);
  const json = await res.json();
  return json.elements || [];
}

function clean(obj) {
  // Drop null-valued optional fields so the Swift decoder treats them as absent.
  for (const k of Object.keys(obj)) if (obj[k] === null) delete obj[k];
  return obj;
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (!next || next.startsWith("--")) out[key] = true;
      else {
        out[key] = next;
        i++;
      }
    }
  }
  return out;
}

void centroid; // imported for parity with geometry module; used indirectly.
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
function fail(msg) {
  console.error(`[prebake] ${msg}`);
  process.exit(1);
}
