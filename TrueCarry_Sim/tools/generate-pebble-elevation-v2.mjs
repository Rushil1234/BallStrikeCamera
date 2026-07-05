// Augusta DEM v2: samples the USGS 3DEP elevation raster (1m/10m source data)
// through the ImageServer getSamples API — ~12m grid spacing versus the 45m
// point-query grid of v1. Output shape is unchanged (terrain.js interpolates).
import fs from 'fs/promises';

const ORIGIN = { lat: 36.56512337660798, lng: -121.93942581877278 };
const BBOX = { south: 36.556, west: -121.952, north: 36.572, east: -121.928 };
const WIDTH = 130;
const HEIGHT = 110;
const BATCH = 400;
const CACHE_PATH = '/tmp/pebble-3dep-cache.json';
const OUT_PATH = new URL('../js/pebble-elevation.js', import.meta.url);
const SERVICE = 'https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer/getSamples';

function project(lat, lng) {
  return {
    x: (lng - ORIGIN.lng) * Math.cos(ORIGIN.lat * Math.PI / 180) * 111320,
    z: (lat - ORIGIN.lat) * 111320,
  };
}

function percentile(values, p) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * p)))];
}

const samples = [];
for (let y = 0; y < HEIGHT; y++) {
  const lat = BBOX.south + (BBOX.north - BBOX.south) * (y / (HEIGHT - 1));
  for (let x = 0; x < WIDTH; x++) {
    const lng = BBOX.west + (BBOX.east - BBOX.west) * (x / (WIDTH - 1));
    samples.push([lng, lat]);
  }
}

let cache = {};
try { cache = JSON.parse(await fs.readFile(CACHE_PATH, 'utf8')); } catch {}

async function fetchBatch(points) {
  const geometry = JSON.stringify({ points, spatialReference: { wkid: 4326 } });
  const params = new URLSearchParams({
    geometry,
    geometryType: 'esriGeometryMultipoint',
    returnFirstValueOnly: 'true',
    f: 'json',
  });
  const res = await fetch(SERVICE, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  });
  if (!res.ok) throw new Error(`3DEP ${res.status}`);
  const data = await res.json();
  if (!data.samples) throw new Error(`3DEP: ${JSON.stringify(data).slice(0, 200)}`);
  // Samples come back keyed by location; index by "lng,lat" rounded.
  const out = new Map();
  for (const s of data.samples) {
    const key = `${s.location.x.toFixed(6)},${s.location.y.toFixed(6)}`;
    const v = Number(s.value);
    out.set(key, Number.isFinite(v) && v > -500 ? v : null);
  }
  return out;
}

const values = new Array(samples.length).fill(null);
const missing = [];
for (let i = 0; i < samples.length; i++) {
  const key = `${samples[i][0].toFixed(6)},${samples[i][1].toFixed(6)}`;
  if (Object.hasOwn(cache, key)) values[i] = cache[key];
  else missing.push(i);
}
console.log(`grid ${WIDTH}x${HEIGHT} = ${samples.length} pts, ${missing.length} to fetch`);

for (let b = 0; b < missing.length; b += BATCH) {
  const idxs = missing.slice(b, b + BATCH);
  const pts = idxs.map((i) => samples[i]);
  let got = null;
  for (let attempt = 1; attempt <= 3 && !got; attempt++) {
    try { got = await fetchBatch(pts); } catch (e) {
      console.warn(`batch ${b / BATCH} attempt ${attempt}: ${e.message}`);
      await new Promise((r) => setTimeout(r, 2000 * attempt));
    }
  }
  if (!got) throw new Error('3DEP batch failed after retries');
  for (const i of idxs) {
    const key = `${samples[i][0].toFixed(6)},${samples[i][1].toFixed(6)}`;
    const v = got.get(key) ?? null;
    values[i] = v;
    cache[key] = v;
  }
  process.stdout.write('.');
  await new Promise((r) => setTimeout(r, 300));
}
await fs.writeFile(CACHE_PATH, JSON.stringify(cache), 'utf8');
process.stdout.write('\n');

// Fill any gaps from neighbours, then round.
for (let pass = 0; pass < 5; pass++) {
  let changed = false;
  for (let y = 0; y < HEIGHT; y++) {
    for (let x = 0; x < WIDTH; x++) {
      const i = y * WIDTH + x;
      if (Number.isFinite(values[i])) continue;
      let sum = 0, count = 0;
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nx = x + dx, ny = y + dy;
        if (nx < 0 || nx >= WIDTH || ny < 0 || ny >= HEIGHT) continue;
        const v = values[ny * WIDTH + nx];
        if (Number.isFinite(v)) { sum += v; count++; }
      }
      if (count) { values[i] = sum / count; changed = true; }
    }
  }
  if (!changed) break;
}
const finite = values.filter(Number.isFinite);
const fallback = percentile(finite, 0.25) || 0;
const rounded = values.map((v) => Number((Number.isFinite(v) ? v : fallback).toFixed(2)));

const sw = project(BBOX.south, BBOX.west);
const ne = project(BBOX.north, BBOX.east);
const data = {
  attribution: 'USGS 3DEP (ImageServer getSamples)',
  source: 'https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer',
  origin: ORIGIN,
  bbox: BBOX,
  width: WIDTH,
  height: HEIGHT,
  worldBounds: {
    minX: Number(sw.x.toFixed(2)),
    maxX: Number(ne.x.toFixed(2)),
    minZ: Number(sw.z.toFixed(2)),
    maxZ: Number(ne.z.toFixed(2)),
  },
  min: Number(Math.min(...finite).toFixed(2)),
  max: Number(Math.max(...finite).toFixed(2)),
  base: Number(percentile(finite, 0.04).toFixed(2)),
  scale: 1,
  values: rounded,
};

const body = `// Generated by tools/generate-pebble-elevation-v2.mjs (3DEP raster v2, ~12m grid).\n`
  + `// Elevation source: USGS 3DEP. Compact local DEM for the Pebble replica.\n\n`
  + `export const PEBBLE_ELEVATION = ${JSON.stringify(data)};\n`;
await fs.writeFile(OUT_PATH, body, 'utf8');
console.log(`wrote ${OUT_PATH.pathname} (${WIDTH}x${HEIGHT}, ${data.min}m..${data.max}m)`);
