// Fetches all golf features for Pinch Brook from Overpass API.
// Falls back to local cache if Overpass is unavailable.

import { readFileSync, existsSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
const __dir = dirname(fileURLToPath(import.meta.url));

const OVERPASS = 'https://overpass-api.de/api/interpreter';
const CACHE_PATH = join(__dir, 'pinchbrook_osm_cache.json');
const BBOX = '40.789,-74.395,40.803,-74.380';
const BOUNDARY_WAY = 40375147;

async function overpass(query) {
  // Use local cache if available (avoids rate limits during development)
  if (existsSync(CACHE_PATH)) {
    console.log('  (using cached OSM data)');
    return JSON.parse(readFileSync(CACHE_PATH, 'utf8'));
  }
  const res = await fetch(OVERPASS, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
      'User-Agent': 'TrueCarryCourseBuilder/1.0',
    },
    body: `data=${encodeURIComponent(query)}`,
  });
  if (!res.ok) throw new Error(`Overpass HTTP ${res.status}`);
  return res.json();
}

function buildNodeMap(elements) {
  const m = new Map();
  for (const e of elements) if (e.type === 'node' && e.lat != null) m.set(e.id, [e.lat, e.lon]);
  return m;
}

function wayToRing(way, nodes) {
  return way.nodes.map(id => nodes.get(id)).filter(Boolean);
}

function centroid(ring) {
  return [ring.reduce((s, p) => s + p[0], 0) / ring.length,
          ring.reduce((s, p) => s + p[1], 0) / ring.length];
}

export async function fetchPinchbrookOSM() {
  console.log('  Fetching OSM golf features…');
  const query = `[out:json][timeout:90];
(
  way(${BOUNDARY_WAY});
  way["golf"](${BBOX});
  node["golf"](${BBOX});
  way["natural"="water"](${BBOX});
  way["natural"="wood"](${BBOX});
  node["natural"="tree"](${BBOX});
  way["golf"="cartpath"](${BBOX});
  way["highway"="service"]["service"="driveway"](${BBOX});
  way["highway"="service"](${BBOX});
  way["surface"="asphalt"](${BBOX});
  way["surface"="concrete"](${BBOX});
);
out body;>;out skel qt;`;

  const data = await overpass(query);
  const elems  = data.elements;
  const nodes  = buildNodeMap(elems);
  const ways   = elems.filter(e => e.type === 'way' && e.nodes);
  const osmNodes = elems.filter(e => e.type === 'node');

  // Separate by type
  const holes       = [];
  const greenWays   = [];
  const teeWays     = [];
  const bunkerWays  = [];
  const fairwayWays = [];
  const waterWays   = [];
  const woodWays    = [];
  const cartWays    = [];
  let   boundaryWay = null;
  const treeNodes   = [];

  for (const w of ways) {
    const t = w.tags || {};
    const g = t.golf;
    if (w.id === BOUNDARY_WAY) { boundaryWay = w; continue; }
    if (g === 'hole')           holes.push(w);
    else if (g === 'green')     greenWays.push(w);
    else if (g === 'tee')       teeWays.push(w);
    else if (g === 'bunker')    bunkerWays.push(w);
    else if (g === 'fairway')   fairwayWays.push(w);
    else if (g === 'water_hazard' || t.natural === 'water') waterWays.push(w);
    else if (t.natural === 'wood') woodWays.push(w);
    else if (g === 'cartpath' || t.highway === 'service' ||
             t.surface === 'asphalt' || t.surface === 'concrete') cartWays.push(w);
  }
  for (const n of osmNodes) {
    if (n.tags?.natural === 'tree') treeNodes.push([n.lat, n.lon]);
  }

  // Each golf=hole way has exactly 2 nodes: tee end and green end
  const holeLines = holes.map(h => {
    const t = h.tags || {};
    const pts = h.nodes.map(id => nodes.get(id)).filter(Boolean);
    return {
      ref:    parseInt(t.ref, 10),
      par:    parseInt(t.par, 10) || 4,
      teeLatLng:   pts[0],
      greenLatLng: pts[pts.length - 1],
      path:        pts,
    };
  }).filter(h => h.ref >= 1 && h.ref <= 18).sort((a, b) => a.ref - b.ref);

  function nearestHoleFor(coord) {
    let best = null, bestDist = Infinity;
    const c = centroid([coord]);
    for (const h of holeLines) {
      const d = Math.hypot((c[0]-h.teeLatLng[0])*111320, (c[1]-h.teeLatLng[1])*84300)
              + Math.hypot((c[0]-h.greenLatLng[0])*111320, (c[1]-h.greenLatLng[1])*84300);
      if (d < bestDist) { bestDist = d; best = h.ref; }
    }
    return best;
  }

  function nearestHoleByPathDist(ring) {
    const cen = centroid(ring);
    let best = null, bestDist = Infinity;
    for (const h of holeLines) {
      const path = [h.teeLatLng, h.greenLatLng];
      let minD = Infinity;
      for (let i = 0; i < path.length - 1; i++) {
        const [ax, az] = [(path[i][0]-cen[0])*111320, (path[i][1]-cen[1])*84300];
        const [bx, bz] = [(path[i+1][0]-cen[0])*111320, (path[i+1][1]-cen[1])*84300];
        const len2 = bx*bx+bz*bz;
        const t2 = len2 ? Math.max(0, Math.min(1, (-ax*bx-az*bz)/len2)) : 0;
        const dx = ax+t2*bx, dz = az+t2*bz;
        minD = Math.min(minD, Math.hypot(dx, dz));
      }
      if (minD < bestDist) { bestDist = minD; best = h.ref; }
    }
    return best;
  }

  // Build per-hole geometry maps
  const holeGreenRings  = new Map(); // ref -> ring (lat/lng pairs)
  const holeTeeRings    = new Map(); // ref -> ring
  const holeBunkers     = new Map(); // ref -> ring[]
  const holeWater       = new Map(); // ref -> ring[]
  const holeFairways    = new Map(); // ref -> ring

  // Assign greens by proximity to hole's green endpoint
  for (const gw of greenWays) {
    const ring = wayToRing(gw, nodes);
    if (!ring.length) continue;
    const cen = centroid(ring);
    let best = null, bestDist = Infinity;
    for (const h of holeLines) {
      const d = Math.hypot((cen[0]-h.greenLatLng[0])*111320, (cen[1]-h.greenLatLng[1])*84300);
      if (d < bestDist) { bestDist = d; best = h.ref; }
    }
    if (best && bestDist < 80) holeGreenRings.set(best, ring);
  }

  // Assign tees by proximity to hole's tee endpoint
  for (const tw of teeWays) {
    const ring = wayToRing(tw, nodes);
    if (!ring.length) continue;
    const cen = centroid(ring);
    let best = null, bestDist = Infinity;
    for (const h of holeLines) {
      const d = Math.hypot((cen[0]-h.teeLatLng[0])*111320, (cen[1]-h.teeLatLng[1])*84300);
      if (d < bestDist) { bestDist = d; best = h.ref; }
    }
    if (best && bestDist < 60) {
      if (!holeTeeRings.has(best)) holeTeeRings.set(best, ring);
    }
  }

  // Assign bunkers
  for (const bw of bunkerWays) {
    const ring = wayToRing(bw, nodes);
    if (!ring.length) continue;
    const ref = nearestHoleByPathDist(ring);
    if (ref) {
      if (!holeBunkers.has(ref)) holeBunkers.set(ref, []);
      holeBunkers.get(ref).push(ring);
    }
  }

  // Assign water hazards
  for (const ww of waterWays) {
    const ring = wayToRing(ww, nodes);
    if (!ring.length) continue;
    const ref = nearestHoleByPathDist(ring);
    if (ref) {
      if (!holeWater.has(ref)) holeWater.set(ref, []);
      holeWater.get(ref).push(ring);
    }
  }

  // Assign OSM fairways
  for (const fw of fairwayWays) {
    const ring = wayToRing(fw, nodes);
    if (!ring.length) continue;
    const ref = nearestHoleByPathDist(ring);
    if (ref) holeFairways.set(ref, ring);
  }

  const boundary  = boundaryWay ? wayToRing(boundaryWay, nodes) : [];
  const woods     = woodWays.map(w => wayToRing(w, nodes)).filter(r => r.length > 0);
  const cartPaths = cartWays.map(w => wayToRing(w, nodes)).filter(r => r.length >= 2);

  return {
    holeLines,
    holeGreenRings,
    holeTeeRings,
    holeBunkers,
    holeWater,
    holeFairways,
    woods,
    treeNodes,
    boundary,
    cartPaths,
  };
}
