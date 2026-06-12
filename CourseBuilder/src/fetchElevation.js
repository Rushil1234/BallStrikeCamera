// Samples USGS elevation via OpenTopoData (free, no key, batches of 100).
// Returns a flat grid of elevation values in meters.

const TOPO_URL = 'https://api.opentopodata.org/v1/ned10m';
const BATCH    = 99;   // max per request
const DELAY_MS = 1200; // polite delay between batches

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function fetchBatch(locations) {
  const body = locations.map(([lat, lng]) => `${lat.toFixed(6)},${lng.toFixed(6)}`).join('|');
  const res = await fetch(`${TOPO_URL}?locations=${encodeURIComponent(body)}&interpolation=bilinear`);
  if (!res.ok) throw new Error(`OpenTopoData ${res.status}`);
  const data = await res.json();
  return (data.results || []).map(r => r.elevation ?? 0);
}

export async function sampleElevationGrid(bbox, proj, cellSize = 10) {
  // bbox: { minX, maxX, minZ, maxZ } in local meters
  const margin = cellSize;
  const x0 = bbox.minX - margin, x1 = bbox.maxX + margin;
  const z0 = bbox.minZ - margin, z1 = bbox.maxZ + margin;

  const cols = Math.ceil((x1 - x0) / cellSize) + 1;
  const rows = Math.ceil((z1 - z0) / cellSize) + 1;

  console.log(`  Elevation grid: ${cols}×${rows} = ${cols * rows} points at ${cellSize}m spacing…`);

  // Build all lat/lng sample points
  const samples = [];
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const x = x0 + c * cellSize;
      const z = z0 + r * cellSize;
      const { lng, lat } = proj.toLngLat(x, z);
      samples.push({ r, c, lat, lng });
    }
  }

  const elevData = new Float32Array(rows * cols);

  // Batch fetch
  for (let i = 0; i < samples.length; i += BATCH) {
    const batch = samples.slice(i, i + BATCH);
    const locs  = batch.map(s => [s.lat, s.lng]);
    process.stdout.write(`\r  Elevation batch ${Math.ceil(i / BATCH) + 1}/${Math.ceil(samples.length / BATCH)}…`);
    const elevs = await fetchBatch(locs);
    for (let j = 0; j < batch.length; j++) {
      const { r, c } = batch[j];
      elevData[r * cols + c] = elevs[j] ?? 0;
    }
    if (i + BATCH < samples.length) await sleep(DELAY_MS);
  }
  console.log(' done.');

  return { cols, rows, cellSize, originX: x0, originZ: z0, data: Array.from(elevData) };
}
