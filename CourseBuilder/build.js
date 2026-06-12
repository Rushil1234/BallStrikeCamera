#!/usr/bin/env node
// CourseBuilder — generates a static course JSON for TrueCarry_Course.
// Usage: node build.js [--refresh] [output_path]
//   --refresh  ignores all caches and re-fetches everything
// Requires Node 18+ (built-in fetch).

import { fetchPinchbrookOSM }     from './src/fetchOSM.js';
import { fetchPinchbrookBackend } from './src/fetchBackend.js';
import { sampleElevationGrid }    from './src/fetchElevation.js';
import { fetchSatelliteGrid }     from './src/fetchSatellite.js';
import { mergeCourse }            from './src/mergeCourse.js';
import { makeProjector }          from './src/geoUtils.js';
import { writeFileSync, mkdirSync } from 'fs';
import { dirname }                  from 'path';

const args    = process.argv.slice(2);
const REFRESH = args.includes('--refresh');
const OUTPUT  = args.find(a => !a.startsWith('-')) || '../TrueCarry_Course/courses/pinchbrook.json';

async function main() {
  console.log('CourseBuilder v2 — Pinch Brook Golf Course');
  console.log('==========================================');
  if (REFRESH) console.log('  (refresh mode — ignoring all caches)');

  // Step 1: Backend metadata
  const backendData = await fetchPinchbrookBackend();
  console.log(`  Found: ${backendData.name} (${backendData.city}, ${backendData.state})`);

  // Step 2: OSM data
  const osmData = await fetchPinchbrookOSM();
  console.log(`  OSM: ${osmData.holeLines.length} holes, ${osmData.holeGreenRings.size} greens, ` +
              `${[...osmData.holeBunkers.values()].flat().length} bunkers, ` +
              `${osmData.woods.length} wood areas, ${osmData.cartPaths.length} cart path ways`);

  // Step 3: Compute bbox for data fetching
  const proj = makeProjector(backendData.lat, backendData.lng);
  const allCoords = [
    ...osmData.boundary,
    ...osmData.holeLines.map(h => h.teeLatLng),
    ...osmData.holeLines.map(h => h.greenLatLng),
  ];
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  for (const [lat, lng] of allCoords) {
    const { x, z } = proj.toXZ(lat, lng);
    if (x < minX) minX = x; if (x > maxX) maxX = x;
    if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
  }
  const bbox = { minX, maxX, minZ, maxZ };

  // Step 4: Elevation grid (10m resolution via NED10m)
  const elevData = await sampleElevationGrid(bbox, proj, 10);

  // Step 5: Satellite vision (Esri World Imagery z=18, cached)
  console.log('  Running satellite vision model…');
  let satGrid = null;
  try {
    satGrid = await fetchSatelliteGrid(bbox, proj, REFRESH);
    console.log(`  Satellite: ${satGrid.cols}×${satGrid.rows} grid, ${satGrid.cartPaths.length} cart path segments`);
  } catch (e) {
    console.warn(`  ⚠ Satellite fetch failed (continuing without): ${e.message}`);
  }

  // Step 6: Merge all sources
  console.log('  Merging data sources…');
  const course = mergeCourse(osmData, backendData, elevData, satGrid);

  // Step 7: Write output
  mkdirSync(dirname(OUTPUT), { recursive: true });
  writeFileSync(OUTPUT, JSON.stringify(course, null, 2));
  const stat = (await import('fs')).statSync(OUTPUT);
  console.log(`\nDone! Written to ${OUTPUT} (${(stat.size / 1024).toFixed(1)} KB)`);
  console.log(`  ${course.holes.length} holes · par ${course.meta.par} · ${course.trees.length} trees`);
  console.log(`  heightmap: ${course.heightmap.cols}×${course.heightmap.rows} @ ${course.heightmap.cellSize}m`);
  console.log(`  cart paths: ${course.cartPaths.length} segments`);
}

main().catch(err => { console.error('Build failed:', err); process.exit(1); });
