// Combines OSM + backend + elevation + satellite data into the final course JSON.
// Key improvements v2:
//   - Bakes bunker bowl depressions and water carves into the heightmap
//   - Adds satellite-detected cart paths and supplementary tree positions
//   - Assigns bunker depth based on polygon area + satellite confirmation

import {
  makeProjector, ringToXZ, centroidXZ, dist2D,
  corridorPolygon, randomPointsInPoly, polyArea, pointInPolygon,
} from './geoUtils.js';
import { satCellAt, satFractionInPoly, SAT } from './fetchSatellite.js';

const FAIRWAY_HW = { 3: 12, 4: 20, 5: 24 };

function buildFairwayCorridor(teeXZ, greenXZ, par) {
  const hw = FAIRWAY_HW[par] ?? 18;
  const dx = greenXZ[0] - teeXZ[0], dz = greenXZ[1] - teeXZ[1];
  const len = Math.hypot(dx, dz) || 1;
  const nx = dx / len, nz = dz / len;
  return corridorPolygon(
    [[teeXZ[0] + nx * 5, teeXZ[1] + nz * 5], [greenXZ[0] - nx * 12, greenXZ[1] - nz * 12]],
    hw,
  );
}

// Seeded LCG for deterministic tree placement
function makeRNG(seed) {
  let s = seed | 0;
  return () => { s = (s * 1664525 + 1013904223) & 0xffffffff; return (s >>> 0) / 0xffffffff; };
}

// ---- Heightmap manipulation: bake features into elevation grid ----
function pip(px, pz, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, zi] = poly[i], [xj, zj] = poly[j];
    if ((zi > pz) !== (zj > pz) && px < ((xj - xi) * (pz - zi)) / (zj - zi) + xi) inside = !inside;
  }
  return inside;
}

function cellsInPoly(poly, originX, originZ, cellSize, cols, rows) {
  if (!poly?.length) return [];
  const xs = poly.map(p => p[0]), zs = poly.map(p => p[1]);
  const c0 = Math.max(0, Math.floor((Math.min(...xs) - originX) / cellSize));
  const c1 = Math.min(cols - 1, Math.ceil((Math.max(...xs) - originX) / cellSize));
  const r0 = Math.max(0, Math.floor((Math.min(...zs) - originZ) / cellSize));
  const r1 = Math.min(rows - 1, Math.ceil((Math.max(...zs) - originZ) / cellSize));
  const result = [];
  for (let r = r0; r <= r1; r++) {
    for (let c = c0; c <= c1; c++) {
      if (pip(originX + c * cellSize, originZ + r * cellSize, poly)) result.push(r * cols + c);
    }
  }
  return result;
}

function bakeHeightmap(elevData, holes, satGrid) {
  const grid = elevData.data.slice(); // work on a copy
  const { originX, originZ, cellSize, cols, rows } = elevData;

  for (const hole of holes) {
    // Bunkers: bowl depression, depth based on area + satellite sand fraction
    for (const bunker of hole.bunkers) {
      const area = polyArea(bunker);
      let depth = area < 60 ? 0.28 : area < 180 ? 0.38 : area < 500 ? 0.48 : 0.58;

      // Boost depth if satellite confirms sandy color there
      const sandFrac = satGrid ? satFractionInPoly(satGrid, bunker, SAT.BUNKER) : 0;
      depth *= 1 + sandFrac * 0.4; // up to 40% deeper if very sandy-looking

      const cells = cellsInPoly(bunker, originX, originZ, cellSize, cols, rows);
      if (!cells.length) continue;
      const avgElev = cells.reduce((s, i) => s + grid[i], 0) / cells.length;
      // Bowl: centre cells deepest, edges blend
      const cx = bunker.reduce((s, p) => s + p[0], 0) / bunker.length;
      const cz = bunker.reduce((s, p) => s + p[1], 0) / bunker.length;
      const maxR = Math.max(...bunker.map(p => Math.hypot(p[0] - cx, p[1] - cz))) || 1;
      for (const idx of cells) {
        const r = Math.floor(idx / cols), c = idx % cols;
        const dx = originX + c * cellSize - cx, dz = originZ + r * cellSize - cz;
        const t = Math.min(1, Math.hypot(dx, dz) / maxR);
        const bowl = depth * Math.pow(1 - t, 1.3);
        grid[idx] = avgElev - bowl;
      }
    }

    // Water: flatten to minimum within polygon then carve 0.6m below
    for (const water of hole.water) {
      const cells = cellsInPoly(water, originX, originZ, cellSize, cols, rows);
      if (!cells.length) continue;
      const minElev = Math.min(...cells.map(i => grid[i]));
      for (const idx of cells) grid[idx] = minElev - 0.6;
    }
  }

  return { ...elevData, data: grid };
}

// ---- Trees ----
function buildTrees(woods, globalBunkers, globalGreens, treeNodes, proj, rng, satGrid) {
  const trees = [];

  // Explicit OSM tree nodes
  for (const [lat, lng] of treeNodes) {
    const { x, z } = proj.toXZ(lat, lng);
    trees.push({ x, z, r: 2.8 + rng() * 1.6, isPine: rng() < 0.25 });
  }

  // Wood polygon fill
  const exclusions = [...globalBunkers, ...globalGreens];
  for (const poly of woods) {
    if (!poly.length) continue;
    const polyXZ = ringToXZ(poly, proj);
    const area = polyArea(polyXZ);
    const count = Math.floor(area / 48);
    const pts = randomPointsInPoly(polyXZ, count);
    for (const [x, z] of pts) {
      if (exclusions.some(ex => pointInPolygon(x, z, ex))) continue;
      trees.push({ x, z, r: 2.5 + rng() * 2.0, isPine: rng() < 0.3 });
    }
  }

  // Satellite-detected tree clusters outside wood polygons
  if (satGrid) {
    const { data, cols, rows, originX, originZ, cellSize } = satGrid;
    const SAMPLE_EVERY = 5; // check every Nth cell to avoid millions of points
    for (let r = 0; r < rows; r += SAMPLE_EVERY) {
      for (let c = 0; c < cols; c += SAMPLE_EVERY) {
        if (data[r * cols + c] !== SAT.TREES) continue;
        const x = originX + c * cellSize;
        const z = originZ + r * cellSize;
        if (exclusions.some(ex => pointInPolygon(x, z, ex))) continue;
        // Only add if not already covered by wood polygon
        const inWood = woods.some(w => pointInPolygon(x, z, ringToXZ(w, proj)));
        if (inWood) continue;
        if (rng() < 0.35) trees.push({ x, z, r: 2.2 + rng() * 1.8, isPine: rng() < 0.4 });
      }
    }
  }

  return trees;
}

// ---- Cart paths (OSM + satellite combined) ----
function buildCartPaths(osmCartPaths, satGrid, proj) {
  const paths = [];

  // OSM-sourced cart paths
  for (const ring of osmCartPaths) {
    const pts = ring.map(([lat, lng]) => {
      const { x, z } = proj.toXZ(lat, lng);
      return [x, z];
    });
    if (pts.length >= 2) paths.push(pts);
  }

  // Satellite-detected paths not already covered
  if (satGrid?.cartPaths) {
    for (const pts of satGrid.cartPaths) {
      // Only keep if reasonably long (>30m) to avoid noise
      if (pts.length < 15) continue;
      const len = pts.reduce((s, p, i) => {
        if (!i) return 0;
        return s + Math.hypot(p[0] - pts[i-1][0], p[1] - pts[i-1][1]);
      }, 0);
      if (len > 30) paths.push(pts);
    }
  }

  return paths;
}

// ---- Main merge ----
export function mergeCourse(osmData, backendData, elevData, satGrid = null) {
  const proj = makeProjector(backendData.lat, backendData.lng);

  const boundary = osmData.boundary.length ? ringToXZ(osmData.boundary, proj) : [];

  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  const allPts = [
    ...osmData.boundary,
    ...osmData.holeLines.map(h => h.teeLatLng),
    ...osmData.holeLines.map(h => h.greenLatLng),
  ];
  for (const [lat, lng] of allPts) {
    const { x, z } = proj.toXZ(lat, lng);
    if (x < minX) minX = x; if (x > maxX) maxX = x;
    if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
  }

  const holes = [];
  const allGreenPolys = [];
  const allBunkerPolys = [];
  let totalPar = 0;

  for (const hl of osmData.holeLines) {
    const ref = hl.ref, par = hl.par;
    totalPar += par;

    const teeXZ   = [proj.toXZ(hl.teeLatLng[0],   hl.teeLatLng[1]).x, proj.toXZ(hl.teeLatLng[0],   hl.teeLatLng[1]).z];
    const greenXZ = [proj.toXZ(hl.greenLatLng[0], hl.greenLatLng[1]).x, proj.toXZ(hl.greenLatLng[0], hl.greenLatLng[1]).z];

    const greenPoly = osmData.holeGreenRings.get(ref)
      ? ringToXZ(osmData.holeGreenRings.get(ref), proj) : null;
    if (greenPoly) allGreenPolys.push(greenPoly);

    const bunkerRings = (osmData.holeBunkers.get(ref) || []).map(r => ringToXZ(r, proj));
    const waterRings  = (osmData.holeWater.get(ref)  || []).map(r => ringToXZ(r, proj));
    for (const b of bunkerRings) allBunkerPolys.push(b);

    const osmFw  = osmData.holeFairways.get(ref);
    const fairway = osmFw ? ringToXZ(osmFw, proj) : buildFairwayCorridor(teeXZ, greenXZ, par);

    const pathXZ = hl.path.length > 2
      ? hl.path.map(p => [proj.toXZ(p[0], p[1]).x, proj.toXZ(p[0], p[1]).z])
      : [teeXZ, greenXZ];

    // Compute bunker depths using satellite confirmation
    const bunkersWithDepth = bunkerRings.map(poly => {
      const area = polyArea(poly);
      let depth = area < 60 ? 0.28 : area < 180 ? 0.38 : area < 500 ? 0.48 : 0.58;
      const sandFrac = satGrid ? satFractionInPoly(satGrid, poly, SAT.BUNKER) : 0;
      depth *= 1 + sandFrac * 0.4;
      return { poly, depth };
    });

    holes.push({
      number: ref,
      par,
      tee:    teeXZ,
      green: {
        center:         greenXZ,
        polygon:        greenPoly || null,
        undulationSeed: ref * 37,
      },
      path:    pathXZ,
      fairway,
      bunkers: bunkersWithDepth.map(b => b.poly),
      bunkerDepths: bunkersWithDepth.map(b => parseFloat(b.depth.toFixed(3))),
      water:   waterRings,
    });
  }

  // Bake depth features into heightmap
  console.log('  Baking bunker/water depth into heightmap…');
  const bakedElev = bakeHeightmap(elevData, holes, satGrid);

  // Trees
  const rng   = makeRNG(9999);
  const trees = buildTrees(osmData.woods, allBunkerPolys, allGreenPolys, osmData.treeNodes, proj, rng, satGrid);

  // Cart paths
  const cartPaths = buildCartPaths(osmData.cartPaths || [], satGrid, proj);

  const meta = {
    name:    backendData.name,
    city:    backendData.city,
    state:   backendData.state,
    country: backendData.country,
    par:     totalPar,
    stimp:   10,
    built:   new Date().toISOString().slice(0, 10),
    pipeline: 'v2-satellite',
  };

  return {
    meta,
    origin:    { lat: backendData.lat, lng: backendData.lng },
    bbox:      { minX, maxX, minZ, maxZ },
    boundary,
    heightmap: bakedElev,
    holes,
    trees,
    cartPaths,
    globalWater: [],
  };
}
