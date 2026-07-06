// EXPERIMENTAL — NOT WIRED INTO THE SIM YET.
// Generates the St Andrews Old Course replica course modules from OSM data.
//
// Status (2026-07-04): blocked on OSM source-data quirks that need manual
// hole-by-hole inspection before this can ship honestly:
//   - The Old Course 8th ("Short") has no centerline at all (synthesised here).
//   - No green polygon exists within 190m of hole 7's centerline end in either
//     orientation; the estuary-loop double greens (7/11, 8/10) appear missing
//     or mapped outside the Old Course boundary polygon (which itself excludes
//     the loop tip — see the `insideCourse` note below).
//   - Five adjacent Links courses share the bbox; the round-walk DP below
//     handles orientation, but green/bunker attribution at the loop needs
//     verified data first.
// Next step: inspect the loop in an OSM editor, fix/confirm upstream data or
// hand-author the four loop greens, then wire in like Augusta.
// Fan-made unofficial replica; not affiliated with or endorsed by ANGC.
// Centerlines + surfaces (c) OpenStreetMap contributors (ODbL), fetched via Overpass:
//   ways:      [out:json]; ( way["golf"](33.494,-82.034,33.513,-82.008);
//                            way["natural"="water"](...); way["waterway"](...) ); out geom;
//   relations: [out:json]; ( relation["golf"](...); relation["natural"="water"](...) ); out geom;
// Card pars/yardages from the public Masters scorecard (par 72, 7,555y).
// Usage: STANDREWS_OSM_DIR=/path/to/json node tools/generate-standrews-course.mjs
//   expects <dir>/standrews-osm-ways.json and <dir>/standrews-osm-rels.json

import fs from 'fs/promises';

const ORIGIN = { lat: 56.34750, lng: -2.81020 };
const DIR = process.env.STANDREWS_OSM_DIR || '/tmp';
const OUT_HOLES = new URL('../js/standrews-private.js', import.meta.url);
const OUT_OSM = new URL('../js/standrews-osm.js', import.meta.url);
const OUT_WORLD = new URL('../js/standrews-world-data.js', import.meta.url);

// Official card: hole -> [par, yards]. Total 7,555y, par 72.
const CARD = {
  1: [4, 376], 2: [4, 453], 3: [4, 398], 4: [4, 480], 5: [5, 568], 6: [4, 412],
  7: [4, 371], 8: [3, 175], 9: [4, 352], 10: [4, 386], 11: [3, 174], 12: [4, 348],
  13: [4, 465], 14: [5, 614], 15: [4, 455], 16: [4, 418], 17: [4, 495], 18: [4, 357],
};

// Real hole names (each is the plant the hole is named for).
const NAMES = {
  1: 'BURN', 2: 'DYKE', 3: 'CARTGATE (OUT)', 4: 'GINGER BEER',
  5: "HOLE O'CROSS (OUT)", 6: 'HEATHERY (OUT)', 7: 'HIGH (OUT)', 8: 'SHORT', 9: 'END',
  10: 'BOBBY JONES', 11: 'HIGH (IN)', 12: 'HEATHERY (IN)', 13: "HOLE O'CROSS (IN)",
  14: 'LONG', 15: 'CARTGATE (IN)', 16: 'CORNER OF THE DYKE', 17: 'ROAD', 18: 'TOM MORRIS',
};

function project(lat, lng) {
  return {
    x: Number(((lng - ORIGIN.lng) * Math.cos(ORIGIN.lat * Math.PI / 180) * 111320).toFixed(2)),
    z: Number(((lat - ORIGIN.lat) * 111320).toFixed(2)),
  };
}

const round2 = (v) => Number(v.toFixed(2));

function projectWay(way) {
  return (way.geometry || []).map((p) => project(p.lat, p.lon));
}

function dist(a, b) {
  return Math.hypot(a.x - b.x, a.z - b.z);
}

function lineLength(points) {
  let total = 0;
  for (let i = 1; i < points.length; i++) total += dist(points[i - 1], points[i]);
  return total;
}

function rdp(points, epsilon) {
  if (points.length <= 2) return points;
  const first = points[0];
  const last = points[points.length - 1];
  const dx = last.x - first.x;
  const dz = last.z - first.z;
  const len2 = dx * dx + dz * dz || 1;
  let best = 0;
  let index = -1;
  for (let i = 1; i < points.length - 1; i++) {
    const t = ((points[i].x - first.x) * dx + (points[i].z - first.z) * dz) / len2;
    const px = first.x + dx * t;
    const pz = first.z + dz * t;
    const d = Math.hypot(points[i].x - px, points[i].z - pz);
    if (d > best) {
      best = d;
      index = i;
    }
  }
  if (best <= epsilon || index < 0) return [first, last];
  return [...rdp(points.slice(0, index + 1), epsilon).slice(0, -1), ...rdp(points.slice(index), epsilon)];
}

function centroid(points) {
  let sx = 0;
  let sz = 0;
  for (const p of points) {
    sx += p.x;
    sz += p.z;
  }
  return { x: sx / points.length, z: sz / points.length };
}

function pointInPolygon(poly, x, z) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const xi = poly[i].x;
    const zi = poly[i].z;
    const xj = poly[j].x;
    const zj = poly[j].z;
    if ((zi > z) !== (zj > z) && x < ((xj - xi) * (z - zi)) / (zj - zi) + xi) inside = !inside;
  }
  return inside;
}

function distToPolyline(pts, x, z) {
  let best = Infinity;
  for (let i = 0; i < pts.length - 1; i++) {
    const ax = pts[i].x;
    const az = pts[i].z;
    const abx = pts[i + 1].x - ax;
    const abz = pts[i + 1].z - az;
    const L2 = abx * abx + abz * abz;
    const t = L2 ? Math.min(Math.max(((x - ax) * abx + (z - az) * abz) / L2, 0), 1) : 0;
    best = Math.min(best, Math.hypot(x - (ax + abx * t), z - (az + abz * t)));
  }
  return best;
}

function polyMinDistToPath(points, path) {
  let best = Infinity;
  for (const p of points) best = Math.min(best, distToPolyline(path, p.x, p.z));
  return best;
}

// Ellipse fit: centroid + principal axes with half-extent radii.
// terrain.js ellipseVal maps local x-axis to world direction (cos rot, sin rot).
function fitEllipse(points, minR, maxR) {
  const c = centroid(points);
  let sxx = 0;
  let sxz = 0;
  let szz = 0;
  for (const p of points) {
    const dx = p.x - c.x;
    const dz = p.z - c.z;
    sxx += dx * dx;
    sxz += dx * dz;
    szz += dz * dz;
  }
  const n = points.length;
  sxx /= n;
  sxz /= n;
  szz /= n;
  const theta = 0.5 * Math.atan2(2 * sxz, sxx - szz);
  const ax = { x: Math.cos(theta), z: Math.sin(theta) };
  let rx = 0;
  let rz = 0;
  for (const p of points) {
    const dx = p.x - c.x;
    const dz = p.z - c.z;
    rx = Math.max(rx, Math.abs(dx * ax.x + dz * ax.z));
    rz = Math.max(rz, Math.abs(-dx * ax.z + dz * ax.x));
  }
  const clamp = (v) => Math.min(maxR, Math.max(minR, v));
  return {
    cx: round2(c.x), cz: round2(c.z),
    rx: round2(clamp(rx * 0.92)), rz: round2(clamp(rz * 0.92)),
    rot: round2(theta),
  };
}

function polygonArea(points) {
  let a = 0;
  for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
    a += (points[j].x + points[i].x) * (points[j].z - points[i].z);
  }
  return Math.abs(a / 2);
}

// A closed water polygon that is long/thin or curved (creek stretch, kidney pond)
// must become a channel along its medial line — a pond ellipse would swallow the
// fairway/green next to it. Bucket boundary points along the principal axis and
// average both banks to approximate the centerline.
function waterPolyToFeature(points) {
  const c = centroid(points);
  let sxx = 0;
  let sxz = 0;
  let szz = 0;
  for (const p of points) {
    const dx = p.x - c.x;
    const dz = p.z - c.z;
    sxx += dx * dx;
    sxz += dx * dz;
    szz += dz * dz;
  }
  const theta = 0.5 * Math.atan2(2 * sxz, sxx - szz);
  const ax = { x: Math.cos(theta), z: Math.sin(theta) };
  let minT = Infinity;
  let maxT = -Infinity;
  let maxW = 0;
  for (const p of points) {
    const t = (p.x - c.x) * ax.x + (p.z - c.z) * ax.z;
    minT = Math.min(minT, t);
    maxT = Math.max(maxT, t);
    maxW = Math.max(maxW, Math.abs(-(p.x - c.x) * ax.z + (p.z - c.z) * ax.x));
  }
  const axisLen = maxT - minT;
  const area = polygonArea(points);
  const fill = area / (Math.PI * (axisLen / 2) * maxW || 1);
  if (axisLen < maxW * 2.6 && fill > 0.55) {
    return { type: 'pond', ...fitEllipse(points, 4, 60) };
  }
  const buckets = Math.max(3, Math.round(axisLen / 14));
  const line = [];
  for (let i = 0; i < buckets; i++) {
    const t0 = minT + (axisLen * i) / buckets;
    const t1 = minT + (axisLen * (i + 1)) / buckets;
    const inBucket = points.filter((p) => {
      const t = (p.x - c.x) * ax.x + (p.z - c.z) * ax.z;
      return t >= t0 && t <= t1;
    });
    if (inBucket.length >= 2) {
      const bc = centroid(inBucket);
      line.push({ x: round2(bc.x), z: round2(bc.z) });
    }
  }
  const width = Math.min(26, Math.max(6, (area / (axisLen || 1)) * 1.15));
  if (line.length < 2) return { type: 'pond', ...fitEllipse(points, 4, 60) };
  return { type: 'channel', width: round2(width), pts: line };
}

function isClosed(way) {
  const g = way.geometry || [];
  return g.length > 3 && g[0].lat === g[g.length - 1].lat && g[0].lon === g[g.length - 1].lon;
}

// Chain a multipolygon relation's outer member ways into closed rings.
function stitchOuters(rel) {
  const segs = rel.members
    .filter((m) => m.type === 'way' && m.role === 'outer' && m.geometry)
    .map((m) => m.geometry.map((p) => project(p.lat, p.lon)));
  const rings = [];
  const unused = segs.slice();
  while (unused.length) {
    let ring = unused.shift();
    let extended = true;
    while (extended && dist(ring[0], ring[ring.length - 1]) > 0.5) {
      extended = false;
      for (let i = 0; i < unused.length; i++) {
        const s = unused[i];
        const end = ring[ring.length - 1];
        if (dist(end, s[0]) < 0.5) {
          ring = ring.concat(s.slice(1));
        } else if (dist(end, s[s.length - 1]) < 0.5) {
          ring = ring.concat(s.slice(0, -1).reverse());
        } else continue;
        unused.splice(i, 1);
        extended = true;
        break;
      }
    }
    rings.push(ring);
  }
  return rings.filter((r) => r.length >= 4);
}

function fail(msg) {
  console.error(`FATAL: ${msg}`);
  process.exit(1);
}

const waysJson = JSON.parse(await fs.readFile(`${DIR}/standrews-osm-ways.json`, 'utf8'));
const relsJson = await fs.readFile(`${DIR}/standrews-osm-rels.json`, 'utf8').then(JSON.parse).catch(() => ({ elements: [] }));

const allWays = waysJson.elements.filter((e) => e.type === 'way');
const courseWay = allWays.find((w) => w.tags?.leisure === 'golf_course' && w.tags?.name === 'Old Course');
if (!courseWay) fail('Old Course boundary polygon not found');
const coursePoly = projectWay(courseWay);
const insideCourse = (w) => {
  const pts = projectWay(w);
  if (!pts.length) return false;
  const c = centroid(pts);
  return pointInPolygon(coursePoly, c.x, c.z);
};
// The OSM Old Course polygon EXCLUDES the Eden-end loop greens, so only the
// hole centerlines are boundary-filtered; surfaces are claimed by each hole's
// distance gates instead (neighbouring courses are fence-separated, well
// outside the corridor thresholds).
const ways = allWays;
const byGolf = (v) => ways.filter((w) => w.tags?.golf === v);

// --- championship hole centerlines (named; the Par-3 course holes are unnamed/short) ---
const holeWays = byGolf('hole');
const champ = new Map();
for (let ref = 1; ref <= 18; ref++) {
  const candidates = holeWays.filter((w) => Number(w.tags?.ref) === ref && insideCourse(w));
  const named = candidates.filter((w) => w.tags?.name);
  const pool = named.length ? named : candidates;
  if (!pool.length) continue;   // synthesised below if genuinely absent
  pool.sort((a, b) => lineLength(projectWay(b)) - lineLength(projectWay(a)));
  champ.set(ref, pool[0]);
}

for (let ref = 1; ref <= 18; ref++) {
  if (ref === 8) continue;   // synthesised after orientation (missing in OSM)
  if (!champ.get(ref)) fail(`no centerline for hole ${ref}`);
}

// Orient every hole tee->green by minimizing the round's total walk
// (green of k -> tee of k+1). Local nearest-tee/green heuristics fail here:
// five adjacent Links courses put foreign tees and the shared double greens
// right next to both ends of several holes. The round-walk criterion is
// global and unambiguous.
const rawPaths = new Map();
const presentRefs = [];
for (let ref = 1; ref <= 18; ref++) {
  if (!champ.get(ref)) continue;
  presentRefs.push(ref);
  rawPaths.set(ref, rdp(projectWay(champ.get(ref)), 5).map((p) => ({ x: round2(p.x), z: round2(p.z) })));
}
const INF = 1e15;
let walkCosts = [0, 0];
const choices = [];
for (let i = 1; i < presentRefs.length; i++) {
  const prev = rawPaths.get(presentRefs[i - 1]);
  const cur = rawPaths.get(presentRefs[i]);
  const prevEnds = [prev[prev.length - 1], prev[0]];
  const curStarts = [cur[0], cur[cur.length - 1]];
  const next = [INF, INF];
  const choice = [0, 0];
  for (let o = 0; o < 2; o++) {
    for (let po = 0; po < 2; po++) {
      const c = walkCosts[po] + dist(prevEnds[po], curStarts[o]);
      if (c < next[o]) { next[o] = c; choice[o] = po; }
    }
  }
  choices.push(choice);
  walkCosts = next;
}
const orient = new Map();
let last = walkCosts[0] <= walkCosts[1] ? 0 : 1;
orient.set(presentRefs[presentRefs.length - 1], last);
for (let i = presentRefs.length - 1; i >= 1; i--) {
  last = choices[i - 1][last];
  orient.set(presentRefs[i - 1], last);
}
const orientedPath = (ref) => (orient.get(ref) ? rawPaths.get(ref).slice().reverse() : rawPaths.get(ref));

// Synthesise the missing 8th ("Short", 175y par 3) from ORIENTED neighbours:
// it plays to the 8/10 double green (= oriented hole 10's green end), teeing
// off between the oriented 7th green and 9th tee.
if (!rawPaths.get(8)) {
  const o7 = orientedPath(7);
  const o9 = orientedPath(9);
  const o10 = orientedPath(10);
  const green8 = o10[o10.length - 1];
  const end7 = o7[o7.length - 1];
  const start9 = o9[0];
  const anchor = { x: (end7.x + start9.x) / 2, z: (end7.z + start9.z) / 2 };
  const dx = anchor.x - green8.x;
  const dz = anchor.z - green8.z;
  const L = Math.hypot(dx, dz) || 1;
  const tee = { x: round2(green8.x + (dx / L) * 160), z: round2(green8.z + (dz / L) * 160) };
  rawPaths.set(8, [tee, { x: round2(green8.x), z: round2(green8.z) }]);
  orient.set(8, 0);
  champ.set(8, { id: -8, tags: { ref: '8' } });
}

// --- surface polygons ---
const greenPolys = byGolf('green').filter(isClosed).map((w) => ({ id: w.id, points: projectWay(w) }));
const teePolys = byGolf('tee').filter(isClosed).map((w) => ({ id: w.id, points: projectWay(w) }));
const bunkerPolys = byGolf('bunker').filter(isClosed).map((w) => ({ id: w.id, points: projectWay(w) }));
const fairwayPolys = [
  ...byGolf('fairway').filter(isClosed).map((w) => ({ id: w.id, points: projectWay(w) })),
  ...relsJson.elements
    .filter((r) => r.tags?.golf === 'fairway')
    .flatMap((r) => stitchOuters(r).map((ring, i) => ({ id: r.id * 10 + i, points: ring }))),
];

// --- water features (creek + ponds) ---
const waterWays = ways.filter((w) => w.tags?.golf === 'lateral_water_hazard'
  || w.tags?.natural === 'water' || w.tags?.waterway);
const waterFeatures = waterWays.map((w) => {
  const pts = projectWay(w);
  if (isClosed(w)) return { kind: 'poly', id: w.id, points: pts };
  return { kind: 'line', id: w.id, points: pts };
});

// --- build holes ---
const holes = [];
const osmByHole = {};
const usedBunkers = new Map(); // bunker id -> hole ref (nearest wins)

for (let ref = 1; ref <= 18; ref++) {
  let path = orientedPath(ref);

  const end = path[path.length - 1];
  // Match by nearest polygon EDGE, not centroid — the Old Course's double
  // greens are so large that a hole's own half can be 80m from the centroid.
  const nearestVertexDist = (pts) => Math.min(...pts.map((p) => dist(end, p)));
  let green = greenPolys
    .map((g) => ({ g, d: nearestVertexDist(g.points) }))
    .sort((a, b) => a.d - b.d)[0];
  if (!green || green.d > 60) {
    // OSM is missing this green (the Eden-loop doubles) — synthesise a
    // links-scale green at the centerline end, oriented to the approach.
    const prev = path[Math.max(0, path.length - 2)];
    const ang = Math.atan2(end.x - prev.x, end.z - prev.z);
    const rx = 17, rz = 14;
    const pts = [];
    for (let i = 0; i < 24; i++) {
      const a = (i / 24) * Math.PI * 2;
      const lx = Math.cos(a) * rx;
      const lz = Math.sin(a) * rz;
      pts.push({
        x: round2(end.x + lx * Math.cos(ang) - lz * Math.sin(ang)),
        z: round2(end.z + lx * Math.sin(ang) + lz * Math.cos(ang)),
      });
    }
    const synth = { id: -(1000 + ref), points: pts };
    greenPolys.push(synth);
    green = { g: synth, d: 0 };
    console.log(`hole ${ref}: green synthesised at centerline end (missing in OSM)`);
  }
  const greenEllipse = fitEllipse(green.g.points, 8, 26);
  // Pin sits in THIS hole's half of the green: blend the boundary vertex
  // nearest the approach with the polygon centroid, then nudge inside.
  const gcen = centroid(green.g.points);
  const nearV = green.g.points.reduce((a, b) => (dist(end, a) <= dist(end, b) ? a : b));
  let pin = { x: nearV.x * 0.45 + gcen.x * 0.55, z: nearV.z * 0.45 + gcen.z * 0.55 };
  for (let i = 0; i < 6 && !pointInPolygon(green.g.points, pin.x, pin.z); i++) {
    pin = { x: (pin.x + gcen.x) / 2, z: (pin.z + gcen.z) / 2 };
  }
  pin = { x: round2(pin.x), z: round2(pin.z) };
  // End the playing path at the pin (not the shared-green centroid).
  if (dist(end, pin) < 45) path[path.length - 1] = pin;
  else path.push(pin);

  const [par, yards] = CARD[ref];
  let centerlineYards = lineLength(path) * 1.09361;
  if (Math.abs(centerlineYards - yards) / yards > 0.22) {
    // OSM hole ways sometimes start at back plates or walk-backs. Adjust the
    // TEE end along the opening segment so the playing length matches the
    // official card; the green end never moves.
    const targetM = yards * 0.9144;
    const excessM = lineLength(path) - targetM;
    if (excessM > 0) {
      let cut = excessM;
      while (path.length > 2 && cut > 0) {
        const segLen = dist(path[0], path[1]);
        if (segLen <= cut) { cut -= segLen; path.shift(); }
        else break;
      }
      const segLen = dist(path[0], path[1]);
      const f = Math.min(cut / segLen, 0.95);
      path[0] = {
        x: round2(path[0].x + (path[1].x - path[0].x) * f),
        z: round2(path[0].z + (path[1].z - path[0].z) * f),
      };
    } else {
      const dx = path[0].x - path[1].x;
      const dz = path[0].z - path[1].z;
      const L2 = Math.hypot(dx, dz) || 1;
      path[0] = {
        x: round2(path[0].x + (dx / L2) * -excessM),
        z: round2(path[0].z + (dz / L2) * -excessM),
      };
    }
    const fixed = lineLength(path) * 1.09361;
    console.log(`hole ${ref}: tee adjusted ${centerlineYards.toFixed(0)}y -> ${fixed.toFixed(0)}y (card ${yards}y)`);
    centerlineYards = fixed;
  }

  const tees = teePolys.filter((t) => dist(centroid(t.points), path[0]) < 50);

  const bunkers = [];
  for (const b of bunkerPolys) {
    const c = centroid(b.points);
    const metric = Math.min(distToPolyline(path, c.x, c.z), dist(c, pin));
    if (metric > 62) continue;
    const prev = usedBunkers.get(b.id);
    if (prev !== undefined && prev.metric <= metric) continue;
    usedBunkers.set(b.id, { ref, metric, poly: b });
  }

  const fairways = fairwayPolys.filter((f) => {
    let inside = 0;
    for (let i = 0; i < path.length - 1; i++) {
      for (let t = 0; t <= 1; t += 0.2) {
        const x = path[i].x + (path[i + 1].x - path[i].x) * t;
        const z = path[i].z + (path[i + 1].z - path[i].z) * t;
        if (pointInPolygon(f.points, x, z)) inside++;
      }
    }
    return inside >= 2;
  });

  // Keep an approach buffer: approximated channels must never encroach on the
  // green surface itself (the real banks stop short of the putting surface).
  const outsideGreen = (p) => {
    const dx = p.x - greenEllipse.cx;
    const dz = p.z - greenEllipse.cz;
    const c = Math.cos(greenEllipse.rot);
    const s = Math.sin(greenEllipse.rot);
    const lx = dx * c + dz * s;
    const lz = -dx * s + dz * c;
    return (lx / (greenEllipse.rx + 8)) ** 2 + (lz / (greenEllipse.rz + 8)) ** 2 > 1;
  };
  const splitOutsideGreen = (pts) => {
    const runs = [];
    let run = [];
    for (const p of pts) {
      if (outsideGreen(p)) run.push(p);
      else if (run.length) { runs.push(run); run = []; }
    }
    if (run.length) runs.push(run);
    return runs.filter((r) => r.length >= 2);
  };

  const water = [];
  const pushChannel = (feature) => {
    for (const run of splitOutsideGreen(feature.pts)) {
      water.push({ ...feature, pts: run });
    }
  };
  for (const w of waterFeatures) {
    if (polyMinDistToPath(w.points, path) > 70) continue;
    if (w.kind === 'poly') {
      const feature = waterPolyToFeature(w.points);
      if (feature.type === 'channel') pushChannel(feature);
      else water.push(feature);
    } else {
      // Keep only the stretch of the creek near this hole so bounds stay tight.
      const near = [];
      let run = [];
      for (const p of w.points) {
        if (distToPolyline(path, p.x, p.z) < 220) run.push(p);
        else if (run.length) { near.push(run); run = []; }
      }
      if (run.length) near.push(run);
      const seg = near.sort((a, b) => lineLength(b) - lineLength(a))[0];
      if (seg && seg.length >= 2) {
        pushChannel({ type: 'channel', width: 9, pts: rdp(seg, 4).map((p) => ({ x: round2(p.x), z: round2(p.z) })) });
      }
    }
  }

  // Four pin positions inside the real green: center plus front/back/left/right
  // quadrants at 45% of each ellipse radius (the sim rotates them per day).
  const pc = Math.cos(greenEllipse.rot);
  const ps = Math.sin(greenEllipse.rot);
  const pinAt = (lx, lz) => ({
    x: round2(pin.x + lx * pc - lz * ps),
    z: round2(pin.z + lx * ps + lz * pc),
  });
  const pins = [pin,
    pinAt(0, -greenEllipse.rz * 0.35),
    pinAt(greenEllipse.rx * 0.35, 0),
    pinAt(0, greenEllipse.rz * 0.35),
    pinAt(-greenEllipse.rx * 0.35, 0),
  ].filter((p) => pointInPolygon(green.g.points, p.x, p.z));

  holes.push({
    id: ref, name: NAMES[ref], par, yards, seed: 8700 + ref,
    path, fairwayHalf: par === 3 ? 12 : 24,
    green: greenEllipse, pin, pins,
    bunkers: [], water,
    treeDensity: 0.12, windMax: 14,
    _centerlineYards: Math.round(centerlineYards),
  });
  osmByHole[ref] = {
    fairways: fairways.map((f) => ({ id: f.id, points: rdp(f.points, 1.2).map((p) => ({ x: round2(p.x), z: round2(p.z) })) })),
    greens: [{ id: green.g.id, points: rdp(green.g.points, 0.8).map((p) => ({ x: round2(p.x), z: round2(p.z) })) }],
    tees: tees.map((t) => ({ id: t.id, points: rdp(t.points, 0.8).map((p) => ({ x: round2(p.x), z: round2(p.z) })) })),
    bunkers: [],
  };
}

// Resolve bunker ownership (each bunker to its nearest hole only).
for (const { ref, poly } of usedBunkers.values()) {
  const hole = holes[ref - 1];
  hole.bunkers.push({ ...fitEllipse(poly.points, 3, 18), depth: 1.6 });
  osmByHole[ref].bunkers.push({ id: poly.id, points: rdp(poly.points, 0.8).map((p) => ({ x: round2(p.x), z: round2(p.z) })) });
}

// --- report + sanity ---
let totalBunkers = 0;
for (const h of holes) {
  totalBunkers += h.bunkers.length;
  console.log(
    `hole ${String(h.id).padStart(2)} ${h.name.padEnd(13)} par ${h.par} card ${h.yards}y centerline ${h._centerlineYards}y `
    + `fairways ${osmByHole[h.id].fairways.length} bunkers ${h.bunkers.length} water ${h.water.length}`,
  );
}
console.log(`total bunkers assigned: ${totalBunkers}`);
if (holes.length !== 18) fail(`expected 18 holes, got ${holes.length}`);

// --- emit modules ---
const holeSrc = holes.map((h) => {
  const { _centerlineYards, yards, ...rest } = h;
  return `  makeHole(${JSON.stringify({ ...rest, yards }).replace(/"([a-zA-Z_]\w*)":/g, '$1: ')}),`;
}).join('\n');

// Cart/service paths for scene realism.
const pathWays = ways.filter((w) => w.tags?.golf === 'cartpath' || w.tags?.golf === 'path');
const worldPaths = pathWays.map((w) => ({
  id: w.id,
  kind: 'cart',
  width: 2.7,
  points: rdp(projectWay(w), 2).map((p) => ({ x: round2(p.x), z: round2(p.z) })),
})).filter((p) => p.points.length >= 2);

// Swilcan Bridge: find where the 18th's burn channel crosses the centerline.
function segIntersect(a, b, c, d) {
  const r = { x: b.x - a.x, z: b.z - a.z };
  const s2 = { x: d.x - c.x, z: d.z - c.z };
  const denom = r.x * s2.z - r.z * s2.x;
  if (Math.abs(denom) < 1e-9) return null;
  const t = ((c.x - a.x) * s2.z - (c.z - a.z) * s2.x) / denom;
  const u = ((c.x - a.x) * r.z - (c.z - a.z) * r.x) / denom;
  if (t < 0 || t > 1 || u < 0 || u > 1) return null;
  return { x: a.x + r.x * t, z: a.z + r.z * t, rot: Math.atan2(s2.x, s2.z) };
}
const bridges = [];
const h18 = holes[17];
for (const w of h18.water) {
  if (w.type !== 'channel' || bridges.length) continue;
  for (let i = 0; i < h18.path.length - 1 && !bridges.length; i++) {
    for (let j = 0; j < w.pts.length - 1; j++) {
      const hit = segIntersect(h18.path[i], h18.path[i + 1], w.pts[j], w.pts[j + 1]);
      if (hit) {
        // Span perpendicular to the burn, wide enough to clear its banks.
        bridges.push({ x: round2(hit.x), z: round2(hit.z), rot: round2(hit.rot), span: (w.width || 9) + 6 });
        break;
      }
    }
  }
}
if (bridges.length) console.log(`Swilcan Bridge at ${bridges[0].x}, ${bridges[0].z}`);

// Sense of place: the town edge. Real building footprints + boundary walls
// near the links (R&A clubhouse, Hamilton Grand, the Links Road row).
const townJson = await fs.readFile(`${DIR}/standrews-town.json`, 'utf8').then(JSON.parse).catch(() => ({ elements: [] }));
const nearCourse = (pts, maxD) => {
  const c = centroid(pts);
  if (pointInPolygon(coursePoly, c.x, c.z)) return true;
  return Math.min(...coursePoly.map((q) => Math.hypot(q.x - c.x, q.z - c.z))) < maxD;
};
const buildings = [];
for (const w of townJson.elements) {
  if (w.type !== 'way' || !w.tags?.building || !w.geometry) continue;
  const pts = projectWay(w);
  if (pts.length < 4 || !nearCourse(pts, 140)) continue;
  const e = fitEllipse(pts, 1, 200);
  const levels = Number(w.tags['building:levels']) || 0;
  const hgt = Number(String(w.tags.height || '').replace(/[^0-9.]/g, '')) || 0;
  buildings.push({
    x: e.cx, z: e.cz, rot: e.rot,
    w: round2(Math.max(4, e.rx * 2 * 0.9)),
    d: round2(Math.max(4, e.rz * 2 * 0.9)),
    h: round2(hgt || (levels ? levels * 3.1 + 1.5 : 6.5 + Math.random() * 3)),
  });
  if (buildings.length >= 150) break;
}
const wallLines = [];
for (const w of townJson.elements) {
  if (w.type !== 'way' || !w.tags?.barrier || !w.geometry) continue;
  const pts = projectWay(w);
  if (pts.length < 2 || !nearCourse(pts, 70)) continue;
  wallLines.push(rdp(pts, 1.5).map((q) => ({ x: round2(q.x), z: round2(q.z) })));
  if (wallLines.length >= 80) break;
}
console.log(`town: ${buildings.length} buildings, ${wallLines.length} wall runs`);

const worldRealism = {
  attribution: '(c) OpenStreetMap contributors (ODbL)',
  paths: worldPaths,
  visualZones: {
    // Open links look: near-treeless fescue, pale revetted sand, cold burn
    // water, wind-burnt olive rough fading to dune scrub.
    waterColor: 0x1a2b33,
    sandColor: 0xdcd3bd,
    roughColor: 0x6f7c46,
    deepColor: 0x596a3a,
    // Links ground game: humps/hollows, golden fescue floor, gorse (whin)
    // banks, and deep revetted pot bunkers.
    dunes: { amp: 1.35, freq: 0.021 },
    forestFloor: { color: 0xb9a35e, start: 6 },
    flora: 'gorse',
    bunkerDepth: 1.7,
    bridges,
    buildings,
    walls: wallLines,
    atmosphere: 'overcast',
  },
};

const holesBody = `// St Andrews Old Course replica — unofficial, fan-made; not affiliated with ANGC.
// Centerlines (c) OpenStreetMap contributors (ODbL); card data from the public scorecard.
// Generated by tools/generate-standrews-course.mjs — do not hand-edit.

function makeHole({
  id, name, par, yards, seed, path, fairwayHalf = 15, green, pin, pins = null, bunkers = [], water = [],
  treeDensity = 1.15, windMax = 6,
}) {
  return {
    id, name, par, seed, path, fairwayHalf, cardYards: yards,
    green, pin, pins, bunkers, water, treeDensity, windMax,
  };
}

export const STANDREWS_PRIVATE_HOLES = [
${holeSrc}
];

export const STANDREWS_PRIVATE_WORLD = {
  profile: 'coastal',
  prepositioned: true,
  boundsMargin: 240,
  water: [],
  // Open links: quick-but-fair greens, baked firm turf, relentless gusts.
  conditions: { stimp: 10.5, firmness: 1.3, gustiness: 0.5 },
};
`;

const osmBody = `// OSM golf geometry pulled from Overpass for the St Andrews Old Course replica.
// Data (c) OpenStreetMap contributors, available under the Open Database License.
// Query bbox: 33.494,-82.034,33.513,-82.008; generated by tools/generate-standrews-course.mjs.

export const STANDREWS_OSM_ATTRIBUTION = "(c) OpenStreetMap contributors (ODbL)";

export const STANDREWS_OSM_BY_HOLE = ${JSON.stringify(osmByHole)};
`;

const worldBody = `// Scene-realism layer (cart paths, forest/flora config) for the Augusta replica.
// Path data (c) OpenStreetMap contributors (ODbL).
// Generated by tools/generate-standrews-course.mjs — do not hand-edit.

export const STANDREWS_WORLD_REALISM = ${JSON.stringify(worldRealism)};
`;

await fs.writeFile(OUT_HOLES, holesBody, 'utf8');
await fs.writeFile(OUT_OSM, osmBody, 'utf8');
await fs.writeFile(OUT_WORLD, worldBody, 'utf8');
console.log(`wrote ${OUT_HOLES.pathname}`);
console.log(`wrote ${OUT_OSM.pathname}`);
console.log(`wrote ${OUT_WORLD.pathname} (${worldPaths.length} paths)`);
