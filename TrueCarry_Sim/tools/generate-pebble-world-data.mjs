import fs from 'fs/promises';

const ORIGIN = { lat: 36.56512337660798, lng: -121.93942581877278 };
const OSM_PATH = '/tmp/pebble-osm-overpass.json';
const PATHS_PATH = '/tmp/pebble-osm-paths.json';
const OUT_PATH = new URL('../js/pebble-world-data.js', import.meta.url);

const CLIP = { minX: -1320, maxX: 1120, minZ: -1180, maxZ: 780 };
const PATH_CLIP = { minX: -1180, maxX: 1040, minZ: -980, maxZ: 720 };

function project(lat, lng) {
  return {
    x: Number(((lng - ORIGIN.lng) * Math.cos(ORIGIN.lat * Math.PI / 180) * 111320).toFixed(2)),
    z: Number(((lat - ORIGIN.lat) * 111320).toFixed(2)),
  };
}

function wayPoints(way, nodeMap = null) {
  const coords = way.geometry || (way.nodes || []).map((id) => nodeMap?.get(id)).filter(Boolean);
  return (coords || []).map((p) => project(p.lat, p.lon));
}

function bounds(points) {
  const b = { minX: Infinity, maxX: -Infinity, minZ: Infinity, maxZ: -Infinity };
  for (const p of points) {
    b.minX = Math.min(b.minX, p.x);
    b.maxX = Math.max(b.maxX, p.x);
    b.minZ = Math.min(b.minZ, p.z);
    b.maxZ = Math.max(b.maxZ, p.z);
  }
  return b;
}

function intersects(b, clip) {
  return b.maxX >= clip.minX && b.minX <= clip.maxX && b.maxZ >= clip.minZ && b.minZ <= clip.maxZ;
}

function ptInClip(p, clip, pad = 0) {
  return p.x >= clip.minX - pad && p.x <= clip.maxX + pad && p.z >= clip.minZ - pad && p.z <= clip.maxZ + pad;
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

function chainLines(lines) {
  if (!lines.length) return [];
  const unused = lines.map((line) => line.points.slice());
  let startIndex = 0;
  let bestMinX = Infinity;
  for (let i = 0; i < unused.length; i++) {
    const b = bounds(unused[i]);
    if (b.minX < bestMinX) {
      bestMinX = b.minX;
      startIndex = i;
    }
  }
  let chain = unused.splice(startIndex, 1)[0];
  if (chain[0].x > chain[chain.length - 1].x) chain = chain.reverse();

  while (unused.length) {
    const head = chain[0];
    const tail = chain[chain.length - 1];
    let choice = null;
    for (let i = 0; i < unused.length; i++) {
      const line = unused[i];
      const a = line[0];
      const b = line[line.length - 1];
      const candidates = [
        { i, mode: 'append', rev: false, d: dist(tail, a) },
        { i, mode: 'append', rev: true, d: dist(tail, b) },
        { i, mode: 'prepend', rev: true, d: dist(head, a) },
        { i, mode: 'prepend', rev: false, d: dist(head, b) },
      ];
      for (const c of candidates) if (!choice || c.d < choice.d) choice = c;
    }
    const line = unused.splice(choice.i, 1)[0];
    const pts = choice.rev ? line.slice().reverse() : line;
    if (choice.mode === 'append') chain = chain.concat(pts.slice(choice.d < 3 ? 1 : 0));
    else chain = pts.slice(0, choice.d < 3 ? -1 : undefined).concat(chain);
  }
  return chain;
}

function featureCollection(raw, predicate, clip, simplify = 1.2) {
  const out = [];
  for (const way of raw.elements || []) {
    if (way.type !== 'way' || !predicate(way.tags || {})) continue;
    const points = wayPoints(way);
    if (points.length < 3) continue;
    const b = bounds(points);
    if (!intersects(b, clip)) continue;
    out.push({ id: way.id, points: rdp(points, simplify) });
  }
  return out;
}

function pathCollection(raw, clip) {
  const nodeMap = new Map((raw.elements || []).filter((e) => e.type === 'node').map((n) => [n.id, n]));
  const out = [];
  for (const way of raw.elements || []) {
    if (way.type !== 'way' || !way.tags?.highway && way.tags?.golf !== 'cartpath') continue;
    const points = wayPoints(way, nodeMap).filter((p) => ptInClip(p, clip, 120));
    if (points.length < 2) continue;
    const b = bounds(points);
    if (!intersects(b, clip)) continue;
    const len = lineLength(points);
    if (len < 24) continue;
    const highway = way.tags.highway || 'cartpath';
    if (!['cartpath', 'service', 'path', 'track', 'footway', 'cycleway', 'tertiary', 'residential'].includes(highway)) continue;
    out.push({
      id: way.id,
      kind: way.tags.golf === 'cartpath' ? 'cartpath' : highway,
      width: highway === 'tertiary' || highway === 'residential' ? 4.6 : 3.2,
      points: rdp(points, 1.7),
    });
  }
  return out.sort((a, b) => lineLength(b.points) - lineLength(a.points)).slice(0, 55);
}

const osm = JSON.parse(await fs.readFile(OSM_PATH, 'utf8'));
let pathRaw = null;
try {
  pathRaw = JSON.parse(await fs.readFile(PATHS_PATH, 'utf8'));
} catch {
  pathRaw = { elements: [] };
}

const coastLines = [];
for (const way of osm.elements || []) {
  if (way.type !== 'way' || way.tags?.natural !== 'coastline') continue;
  const points = wayPoints(way);
  if (points.length >= 2) coastLines.push({ id: way.id, points });
}

const chained = chainLines(coastLines);
const clippedCoast = rdp(chained.filter((p) => ptInClip(p, CLIP, 40)), 3.5);
const first = clippedCoast[0];
const last = clippedCoast[clippedCoast.length - 1];
const land = [
  ...clippedCoast,
  { x: CLIP.maxX, z: Math.min(last?.z ?? CLIP.minZ, CLIP.minZ) },
  { x: CLIP.maxX, z: CLIP.maxZ },
  { x: CLIP.minX, z: CLIP.maxZ },
  { x: CLIP.minX, z: first?.z ?? CLIP.minZ },
];

const woods = featureCollection(osm, (tags) => tags.natural === 'wood' || tags.landuse === 'forest', PATH_CLIP, 2.5);
const ponds = featureCollection(osm, (tags) => tags.natural === 'water', PATH_CLIP, 1.2);
const sandy = featureCollection(osm, (tags) => tags.natural === 'sand', PATH_CLIP, 1.4);
const paths = pathCollection(pathRaw, PATH_CLIP);

const data = {
  attribution: 'OpenStreetMap contributors (ODbL)',
  source: 'https://www.openstreetmap.org/copyright',
  coastline: {
    land,
    beach: clippedCoast,
  },
  paths,
  visualZones: {
    woods,
    ponds,
    sand: sandy,
    scrub: sandy.slice(0, 34),
  },
};

const body = `// Generated by tools/generate-pebble-world-data.mjs.\n`
  + `// Local private Pebble prototype world layer from OpenStreetMap/Overpass data.\n\n`
  + `export const PEBBLE_WORLD_REALISM = ${JSON.stringify(data)};\n`;
await fs.writeFile(OUT_PATH, body, 'utf8');
console.log(`wrote ${OUT_PATH.pathname}: ${clippedCoast.length} coastline pts, ${paths.length} paths, ${woods.length} wood zones`);
