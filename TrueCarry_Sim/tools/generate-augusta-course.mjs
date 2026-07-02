// Generates the Augusta National replica course modules from OSM data.
// Fan-made unofficial replica; not affiliated with or endorsed by ANGC.
// Centerlines + surfaces (c) OpenStreetMap contributors (ODbL), fetched via Overpass:
//   ways:      [out:json]; ( way["golf"](33.494,-82.034,33.513,-82.008);
//                            way["natural"="water"](...); way["waterway"](...) ); out geom;
//   relations: [out:json]; ( relation["golf"](...); relation["natural"="water"](...) ); out geom;
// Card pars/yardages from the public Masters scorecard (par 72, 7,555y).
// Usage: AUGUSTA_OSM_DIR=/path/to/json node tools/generate-augusta-course.mjs
//   expects <dir>/augusta-osm-ways.json and <dir>/augusta-osm-rels.json

import fs from 'fs/promises';

const ORIGIN = { lat: 33.49927, lng: -82.023751 };
const DIR = process.env.AUGUSTA_OSM_DIR || '/tmp';
const OUT_HOLES = new URL('../js/augusta-private.js', import.meta.url);
const OUT_OSM = new URL('../js/augusta-osm.js', import.meta.url);
const OUT_WORLD = new URL('../js/augusta-world-data.js', import.meta.url);

// Official card: hole -> [par, yards]. Total 7,555y, par 72.
const CARD = {
  1: [4, 445], 2: [5, 585], 3: [4, 350], 4: [3, 240], 5: [4, 495], 6: [3, 180],
  7: [4, 450], 8: [5, 570], 9: [4, 460], 10: [4, 495], 11: [4, 520], 12: [3, 155],
  13: [5, 545], 14: [4, 440], 15: [5, 550], 16: [3, 170], 17: [4, 440], 18: [4, 465],
};

// Real hole names (each is the plant the hole is named for).
const NAMES = {
  1: 'TEA OLIVE', 2: 'PINK DOGWOOD', 3: 'FLOWERING PEACH', 4: 'FLOWERING CRAB APPLE',
  5: 'MAGNOLIA', 6: 'JUNIPER', 7: 'PAMPAS', 8: 'YELLOW JASMINE', 9: 'CAROLINA CHERRY',
  10: 'CAMELLIA', 11: 'WHITE DOGWOOD', 12: 'GOLDEN BELL', 13: 'AZALEA', 14: 'CHINESE FIR',
  15: 'FIRETHORN', 16: 'REDBUD', 17: 'NANDINA', 18: 'HOLLY',
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

const waysJson = JSON.parse(await fs.readFile(`${DIR}/augusta-osm-ways.json`, 'utf8'));
const relsJson = JSON.parse(await fs.readFile(`${DIR}/augusta-osm-rels.json`, 'utf8'));

const ways = waysJson.elements.filter((e) => e.type === 'way');
const byGolf = (v) => ways.filter((w) => w.tags?.golf === v);

// --- championship hole centerlines (named; the Par-3 course holes are unnamed/short) ---
const holeWays = byGolf('hole');
const champ = new Map();
for (let ref = 1; ref <= 18; ref++) {
  const candidates = holeWays.filter((w) => Number(w.tags?.ref) === ref);
  const named = candidates.filter((w) => w.tags?.name);
  const pool = named.length ? named : candidates;
  if (!pool.length) fail(`no centerline for hole ${ref}`);
  pool.sort((a, b) => lineLength(projectWay(b)) - lineLength(projectWay(a)));
  champ.set(ref, pool[0]);
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
  const way = champ.get(ref);
  let path = rdp(projectWay(way), 5).map((p) => ({ x: round2(p.x), z: round2(p.z) }));

  // Orient tee -> green: the end nearer a green polygon is the green end.
  const nearestGreenDist = (pt) => Math.min(...greenPolys.map((g) => dist(pt, centroid(g.points))));
  if (nearestGreenDist(path[0]) < nearestGreenDist(path[path.length - 1])) path = path.slice().reverse();

  const end = path[path.length - 1];
  const green = greenPolys
    .map((g) => ({ g, d: dist(end, centroid(g.points)) }))
    .sort((a, b) => a.d - b.d)[0];
  if (!green || green.d > 60) fail(`hole ${ref}: no green polygon near centerline end (best ${green?.d?.toFixed(1)}m)`);
  const greenEllipse = fitEllipse(green.g.points, 8, 26);
  // End the playing path exactly at the real green center.
  const gc = { x: greenEllipse.cx, z: greenEllipse.cz };
  if (dist(end, gc) < 30) path[path.length - 1] = gc;
  else path.push(gc);

  const [par, yards] = CARD[ref];
  const centerlineYards = lineLength(path) * 1.09361;
  if (Math.abs(centerlineYards - yards) / yards > 0.15) {
    fail(`hole ${ref}: centerline ${centerlineYards.toFixed(0)}y vs card ${yards}y (>15% off)`);
  }

  const tees = teePolys.filter((t) => dist(centroid(t.points), path[0]) < 50);

  const bunkers = [];
  for (const b of bunkerPolys) {
    const c = centroid(b.points);
    const metric = Math.min(distToPolyline(path, c.x, c.z), dist(c, gc));
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

  holes.push({
    id: ref, name: NAMES[ref], par, yards, seed: 8100 + ref,
    path, fairwayHalf: par === 3 ? 9 : 16,
    green: greenEllipse, pin: { x: greenEllipse.cx, z: greenEllipse.cz },
    bunkers: [], water,
    treeDensity: 1.15, windMax: 6,
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
  hole.bunkers.push({ ...fitEllipse(poly.points, 3, 18), depth: 1.1 });
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

const worldRealism = {
  attribution: '(c) OpenStreetMap contributors (ODbL)',
  paths: worldPaths,
  visualZones: {
    // Georgia parkland look, tuned to reference photos of the real course:
    // walls of tall loblolly pines, pine-straw floor, azalea banks, blinding
    // white quartz ("Spruce Pine") bunker sand, bright tightly-mown second cut.
    forest: { pineShare: 0.88, scaleMin: 1.05, scaleRange: 1.5 },
    forestFloor: { color: 0x8a6742, start: 24 },
    flora: 'azalea',
    waterColor: 0x0d3a5c,
    sandColor: 0xefe9dc,
    roughColor: 0x4d8236,
    deepColor: 0x3f702c,
  },
};

const holesBody = `// Augusta National replica — unofficial, fan-made; not affiliated with ANGC.
// Centerlines (c) OpenStreetMap contributors (ODbL); card data from the public scorecard.
// Generated by tools/generate-augusta-course.mjs — do not hand-edit.

function makeHole({
  id, name, par, yards, seed, path, fairwayHalf = 15, green, pin, bunkers = [], water = [],
  treeDensity = 1.15, windMax = 6,
}) {
  return {
    id, name, par, seed, path, fairwayHalf, cardYards: yards,
    green, pin, bunkers, water, treeDensity, windMax,
  };
}

export const AUGUSTA_PRIVATE_HOLES = [
${holeSrc}
];

export const AUGUSTA_PRIVATE_WORLD = {
  profile: 'coastal',
  prepositioned: true,
  boundsMargin: 240,
  water: [],
};
`;

const osmBody = `// OSM golf geometry pulled from Overpass for the Augusta National replica.
// Data (c) OpenStreetMap contributors, available under the Open Database License.
// Query bbox: 33.494,-82.034,33.513,-82.008; generated by tools/generate-augusta-course.mjs.

export const AUGUSTA_OSM_ATTRIBUTION = "(c) OpenStreetMap contributors (ODbL)";

export const AUGUSTA_OSM_BY_HOLE = ${JSON.stringify(osmByHole)};
`;

const worldBody = `// Scene-realism layer (cart paths, forest/flora config) for the Augusta replica.
// Path data (c) OpenStreetMap contributors (ODbL).
// Generated by tools/generate-augusta-course.mjs — do not hand-edit.

export const AUGUSTA_WORLD_REALISM = ${JSON.stringify(worldRealism)};
`;

await fs.writeFile(OUT_HOLES, holesBody, 'utf8');
await fs.writeFile(OUT_OSM, osmBody, 'utf8');
await fs.writeFile(OUT_WORLD, worldBody, 'utf8');
console.log(`wrote ${OUT_HOLES.pathname}`);
console.log(`wrote ${OUT_OSM.pathname}`);
console.log(`wrote ${OUT_WORLD.pathname} (${worldPaths.length} paths)`);
