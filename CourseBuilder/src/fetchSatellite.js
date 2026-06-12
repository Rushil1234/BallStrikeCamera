// Satellite imagery analysis: downloads Esri World Imagery tiles for the
// course BBOX and classifies pixels by HSV color into course feature types.
// Output is a 2m-resolution grid used to supplement OSM data with:
//   - cart path detection (gray/white pavement)
//   - extra bunker confirmation + depth scoring
//   - supplementary tree cluster positions
//   - water boundary sharpening
//
// No API key required (Esri World Imagery is publicly accessible).
// Uses jimp (pure JS) for JPEG tile decoding.

import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const Jimp = require('jimp');

import { existsSync, readFileSync, writeFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dir = dirname(fileURLToPath(import.meta.url));
const SAT_CACHE = join(__dir, 'satellite_grid_cache.json');

// Tile server: Esri World Imagery (publicly accessible, ~0.6m/px at z=18)
const TILE_URL = (z, y, x) =>
  `https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/${z}/${y}/${x}`;

const ZOOM = 18;

// Classification values
export const SAT = {
  UNKNOWN:  0,
  BUNKER:   1,
  WATER:    2,
  CARTPATH: 3,
  TREES:    4,
  FAIRWAY:  5,
};

// ---------- Tile math ----------
function latLngToTileXY(lat, lng, z) {
  const n = 1 << z;
  const tx = Math.floor((lng + 180) / 360 * n);
  const latRad = lat * Math.PI / 180;
  const ty = Math.floor((1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI) / 2 * n);
  return { tx, ty };
}

// Top-left lat/lng of a tile
function tileTopLeft(tx, ty, z) {
  const n = 1 << z;
  const lng = tx / n * 360 - 180;
  const latRad = Math.atan(Math.sinh(Math.PI * (1 - 2 * ty / n)));
  const lat = latRad * 180 / Math.PI;
  return { lat, lng };
}

// Pixel (px, py) within a tile → lat/lng
function tilePixelToLatLng(tx, ty, px, py, z) {
  const tileSize = 256;
  const n = 1 << z;
  const lng = ((tx + px / tileSize) / n) * 360 - 180;
  const y = Math.PI * (1 - 2 * (ty + py / tileSize) / n);
  const lat = Math.atan(Math.sinh(y)) * 180 / Math.PI;
  return { lat, lng };
}

// ---------- Color classification ----------
// Convert 0-255 RGB to HSV (H: 0-360, S: 0-1, V: 0-1)
function rgbToHsv(r, g, b) {
  const rn = r / 255, gn = g / 255, bn = b / 255;
  const max = Math.max(rn, gn, bn), min = Math.min(rn, gn, bn);
  const d = max - min;
  let h = 0, s = max === 0 ? 0 : d / max;
  if (d > 0) {
    if (max === rn)      h = ((gn - bn) / d + 6) % 6;
    else if (max === gn) h = (bn - rn) / d + 2;
    else                 h = (rn - gn) / d + 4;
    h *= 60;
  }
  return { h, s, v: max };
}

function classifyPixel(r, g, b) {
  const { h, s, v } = rgbToHsv(r, g, b);

  // Sand / bunker: warm tan, low-medium saturation, bright
  if (h >= 20 && h <= 55 && s >= 0.08 && s <= 0.55 && v >= 0.62) return SAT.BUNKER;

  // Water: blue-ish, or very dark (deep water appears near-black with hint of blue)
  if ((h >= 160 && h <= 230 && s >= 0.20 && v >= 0.08 && v <= 0.65)) return SAT.WATER;
  if (v < 0.12 && s < 0.25) return SAT.WATER; // very dark → deep water

  // Cart path / pavement: gray (low saturation), mid-bright
  const grayness = 1 - s;
  if (grayness > 0.82 && v >= 0.35 && v <= 0.82) return SAT.CARTPATH;

  // Tree canopy: dark-medium green
  if (h >= 80 && h <= 155 && s >= 0.22 && v >= 0.08 && v <= 0.52) return SAT.TREES;

  // Short-mown grass (fairway/green): brighter, more saturated green
  if (h >= 80 && h <= 145 && s >= 0.28 && v >= 0.38 && v <= 0.78) return SAT.FAIRWAY;

  return SAT.UNKNOWN;
}

// ---------- Download & classify tiles ----------
async function fetchTile(tx, ty) {
  const url = TILE_URL(ZOOM, ty, tx);
  try {
    const res = await fetch(url, {
      headers: { 'User-Agent': 'TrueCarryCourseBuilder/2.0 (educational/non-commercial)' },
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const buf = Buffer.from(await res.arrayBuffer());
    return buf;
  } catch (e) {
    console.warn(`    ⚠ tile ${tx}/${ty} failed: ${e.message}`);
    return null;
  }
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ---------- Main export ----------
export async function fetchSatelliteGrid(bbox, proj, refresh = false) {
  if (!refresh && existsSync(SAT_CACHE)) {
    console.log('  (using cached satellite grid)');
    return JSON.parse(readFileSync(SAT_CACHE, 'utf8'));
  }

  console.log('  Fetching satellite tiles (Esri World Imagery z=18)…');

  // Determine bounding lat/lng from course bbox + margin
  const MARGIN_M = 20;
  const { lat: latMax, lng: lngMin } = proj.toLngLat(bbox.minX - MARGIN_M, bbox.minZ - MARGIN_M);
  const { lat: latMin, lng: lngMax } = proj.toLngLat(bbox.maxX + MARGIN_M, bbox.maxZ + MARGIN_M);

  const { tx: tx0, ty: ty1 } = latLngToTileXY(latMin, lngMin, ZOOM); // southern = larger ty
  const { tx: tx1, ty: ty0 } = latLngToTileXY(latMax, lngMax, ZOOM); // northern = smaller ty

  const tileCountX = tx1 - tx0 + 1;
  const tileCountY = ty1 - ty0 + 1;
  const totalTiles = tileCountX * tileCountY;
  console.log(`  Coverage: ${tileCountX}×${tileCountY} = ${totalTiles} tiles`);

  // Output grid: 2m resolution covering the bbox + margin
  const CELL = 2; // meters
  const gCols = Math.ceil((bbox.maxX - bbox.minX + MARGIN_M * 2) / CELL) + 1;
  const gRows = Math.ceil((bbox.maxZ - bbox.minZ + MARGIN_M * 2) / CELL) + 1;
  const gOriginX = bbox.minX - MARGIN_M;
  const gOriginZ = bbox.minZ - MARGIN_M;
  const grid = new Uint8Array(gCols * gRows);

  let processed = 0;
  for (let ty = ty0; ty <= ty1; ty++) {
    for (let tx = tx0; tx <= tx1; tx++) {
      process.stdout.write(`\r  Tile ${++processed}/${totalTiles}…`);
      const buf = await fetchTile(tx, ty);
      if (!buf) continue;

      let img;
      try {
        img = await Jimp.read(buf);
      } catch (e) {
        console.warn(`\n    ⚠ jimp parse failed for tile ${tx}/${ty}: ${e.message}`);
        continue;
      }

      const W = img.bitmap.width, H = img.bitmap.height;
      const data = img.bitmap.data; // RGBA Buffer

      for (let py = 0; py < H; py++) {
        for (let px = 0; px < W; px++) {
          const { lat, lng } = tilePixelToLatLng(tx, ty, px, py, ZOOM);
          const { x, z } = proj.toXZ(lat, lng);

          // Map to grid cell
          const gc = Math.round((x - gOriginX) / CELL);
          const gr = Math.round((z - gOriginZ) / CELL);
          if (gc < 0 || gc >= gCols || gr < 0 || gr >= gRows) continue;

          const pi = (py * W + px) * 4;
          const cls = classifyPixel(data[pi], data[pi + 1], data[pi + 2]);

          // Higher-priority classes overwrite lower ones
          const existing = grid[gr * gCols + gc];
          if (cls > 0 && (existing === SAT.UNKNOWN || cls <= existing)) {
            grid[gr * gCols + gc] = cls;
          }
        }
      }

      // Polite delay every 10 tiles
      if (processed % 10 === 0) await sleep(300);
    }
  }
  console.log(' done.');

  // Extract cart path polylines from connected gray clusters
  const cartPaths = extractCartPaths(grid, gCols, gRows, gOriginX, gOriginZ, CELL, proj);

  const result = {
    cellSize:  CELL,
    originX:   gOriginX,
    originZ:   gOriginZ,
    cols:      gCols,
    rows:      gRows,
    data:      Array.from(grid),
    cartPaths, // array of polylines in local [x, z] pairs
  };

  writeFileSync(SAT_CACHE, JSON.stringify(result));
  console.log(`  Satellite grid saved (${gCols}×${gRows}, ${cartPaths.length} cart path segments)`);
  return result;
}

// ---------- Extract cart path centerlines via connected-component scan ----------
function extractCartPaths(grid, cols, rows, originX, originZ, cell, proj) {
  const MIN_PATH_CELLS = 8; // minimum length to count as a path
  const visited = new Uint8Array(cols * rows);
  const paths = [];

  for (let start = 0; start < grid.length; start++) {
    if (grid[start] !== SAT.CARTPATH || visited[start]) continue;

    // BFS to collect connected gray cluster
    const cluster = [];
    const queue = [start];
    visited[start] = 1;

    while (queue.length) {
      const idx = queue.shift();
      cluster.push(idx);
      const r = Math.floor(idx / cols), c = idx % cols;
      for (const [dr, dc] of [[-1,0],[1,0],[0,-1],[0,1]]) {
        const nr = r + dr, nc = c + dc;
        if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
        const ni = nr * cols + nc;
        if (!visited[ni] && (grid[ni] === SAT.CARTPATH || grid[ni] === SAT.UNKNOWN)) {
          // only include neighboring gray/unknown cells that are adjacent to gray
          if (grid[ni] === SAT.CARTPATH) { visited[ni] = 1; queue.push(ni); }
        }
      }
    }

    if (cluster.length < MIN_PATH_CELLS) continue;

    // Thin the cluster to approximate centerline: just use cell centers
    const polyline = cluster.map(idx => {
      const r = Math.floor(idx / cols), c = idx % cols;
      return [originX + c * cell, originZ + r * cell];
    });

    paths.push(polyline);
  }

  return paths;
}

// ---------- Helpers for mergeCourse to query the satellite grid ----------
export function satCellAt(satGrid, x, z) {
  const c = Math.round((x - satGrid.originX) / satGrid.cellSize);
  const r = Math.round((z - satGrid.originZ) / satGrid.cellSize);
  if (c < 0 || c >= satGrid.cols || r < 0 || r >= satGrid.rows) return SAT.UNKNOWN;
  return satGrid.data[r * satGrid.cols + c];
}

// Fraction of a polygon's cells that match a given classification
export function satFractionInPoly(satGrid, poly, targetClass) {
  if (!poly?.length || !satGrid) return 0;
  const xs = poly.map(p => p[0]), zs = poly.map(p => p[1]);
  const minX = Math.min(...xs), maxX = Math.max(...xs);
  const minZ = Math.min(...zs), maxZ = Math.max(...zs);
  let total = 0, match = 0;
  for (let x = minX; x <= maxX; x += satGrid.cellSize) {
    for (let z = minZ; z <= maxZ; z += satGrid.cellSize) {
      if (!pointInPoly(x, z, poly)) continue;
      total++;
      if (satGrid.data[Math.round((z - satGrid.originZ) / satGrid.cellSize) * satGrid.cols
                       + Math.round((x - satGrid.originX) / satGrid.cellSize)] === targetClass) match++;
    }
  }
  return total > 0 ? match / total : 0;
}

function pointInPoly(px, pz, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, zi] = poly[i], [xj, zj] = poly[j];
    if ((zi > pz) !== (zj > pz) && px < ((xj - xi) * (pz - zi)) / (zj - zi) + xi) inside = !inside;
  }
  return inside;
}
