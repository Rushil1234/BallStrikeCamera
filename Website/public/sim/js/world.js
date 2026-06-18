// Course-world layout: place every hole into one persistent island map.
// The hole definitions stay local/simple in holes.js; this module clones,
// rotates, and routes them into shared world coordinates for play and maps.

function clone(v) {
  return JSON.parse(JSON.stringify(v));
}

function emptyBounds() {
  return { minX: Infinity, maxX: -Infinity, minZ: Infinity, maxZ: -Infinity };
}

function addBounds(b, x, z, m = 0) {
  b.minX = Math.min(b.minX, x - m);
  b.maxX = Math.max(b.maxX, x + m);
  b.minZ = Math.min(b.minZ, z - m);
  b.maxZ = Math.max(b.maxZ, z + m);
}

function padBounds(b, m) {
  return { minX: b.minX - m, maxX: b.maxX + m, minZ: b.minZ - m, maxZ: b.maxZ + m };
}

function mergeBounds(bounds, margin = 0) {
  const out = emptyBounds();
  bounds.forEach((b) => {
    addBounds(out, b.minX, b.minZ);
    addBounds(out, b.maxX, b.maxZ);
  });
  return padBounds(out, margin);
}

const DEG = Math.PI / 180;
const WORLD_SPREAD = 1.22;

// Hand-routed course plan. Angles are bearings where 0 points north/+z.
// The route loops around a central lake instead of stacking holes in rows.
const BUILTIN_ROUTING = [
  { x: -850, z: -620, a:  55 },
  { x: -540, z: -390, a: 110 },
  { x: -360, z: -500, a:  20 },
  { x: -185, z:  -20, a: -55 },
  { x: -500, z:  250, a: 100 },
  { x: -320, z:  180, a:  55 },
  { x:  -10, z:  380, a:   0 },
  { x:  150, z:  895, a:-100 },
  { x: -280, z:  680, a:-170 },
  { x:   70, z: -620, a: 130 },
  { x:  340, z: -790, a:  20 },
  { x:  430, z: -650, a: -10 },
  { x:  360, z: -110, a: -75 },
  { x:  130, z:   70, a:  80 },
  { x:  465, z:  165, a:   0 },
  { x:  385, z:  700, a:-135 },
  { x:  100, z:  370, a:  95 },
  { x:  560, z:  330, a:-170 },
];

const BUILTIN_WATER = [
  { type: 'pond', cx: -75, cz: -425, rx: 175, rz: 270, rot: -0.5, worldOnly: true },
  { type: 'pond', cx: 325, cz: 880, rx: 115, rz: 190, rot: -0.6, worldOnly: true },
];

function scaledWater(water, spread) {
  return {
    ...water,
    cx: water.cx * spread,
    cz: water.cz * spread,
  };
}

export function measureHole(hole) {
  const b = emptyBounds();
  for (const p of hole.path || []) addBounds(b, p.x, p.z, 24);
  if (hole.green) addBounds(b, hole.green.cx, hole.green.cz, Math.max(hole.green.rx, hole.green.rz));
  for (const s of hole.bunkers || []) addBounds(b, s.cx, s.cz, Math.max(s.rx, s.rz));
  for (const w of hole.water || []) {
    if (w.type === 'pond') addBounds(b, w.cx, w.cz, Math.max(w.rx, w.rz));
    else for (const p of w.pts || []) addBounds(b, p.x, p.z, (w.width || 0) + 10);
  }
  if (!Number.isFinite(b.minX)) addBounds(b, 0, 0, 1);
  return b;
}

function transformPoint(p, tx, tz, ang) {
  const c = Math.cos(ang), s = Math.sin(ang);
  return {
    x: tx + p.x * c + p.z * s,
    z: tz - p.x * s + p.z * c,
  };
}

function transformHole(hole, tx, tz, ang) {
  const h = clone(hole);
  for (const p of h.path || []) {
    const q = transformPoint(p, tx, tz, ang);
    p.x = q.x; p.z = q.z;
  }
  if (h.green) {
    const q = transformPoint({ x: h.green.cx, z: h.green.cz }, tx, tz, ang);
    h.green.cx = q.x; h.green.cz = q.z; h.green.rot = (h.green.rot || 0) + ang;
  }
  if (h.pin) {
    const q = transformPoint(h.pin, tx, tz, ang);
    h.pin.x = q.x; h.pin.z = q.z;
  }
  for (const srf of h.bunkers || []) {
    const q = transformPoint({ x: srf.cx, z: srf.cz }, tx, tz, ang);
    srf.cx = q.x; srf.cz = q.z; srf.rot = (srf.rot || 0) + ang;
  }
  for (const w of h.water || []) {
    if (w.type === 'pond') {
      const q = transformPoint({ x: w.cx, z: w.cz }, tx, tz, ang);
      w.cx = q.x; w.cz = q.z; w.rot = (w.rot || 0) + ang;
    } else {
      for (const p of w.pts || []) {
        const q = transformPoint(p, tx, tz, ang);
        p.x = q.x; p.z = q.z;
      }
    }
  }
  h.worldOffset = { x: tx, z: tz };
  h.worldAngle = ang;
  return h;
}

function connectorBetween(a, b) {
  const from = a.path[a.path.length - 1];
  const to = b.path[0];
  return {
    from: { x: from.x, z: from.z },
    to: { x: to.x, z: to.z },
  };
}

export function layoutIslandCourse(rawHoles, options = {}) {
  const holes = rawHoles || [];
  const spread = options.spread ?? WORLD_SPREAD;
  const routing = options.routing || BUILTIN_ROUTING;
  const baseWater = options.water || BUILTIN_WATER;
  const boundsMargin = options.boundsMargin ?? 150;
  const profile = options.profile || 'island';
  const coastline = options.coastline || null;
  const elevation = options.elevation || null;
  const paths = options.paths || [];
  const visualZones = options.visualZones || {};
  const osmCoastline = options.osmCoastline || [];
  const prepositioned = !!options.prepositioned;
  if (!holes.length) {
    const b = emptyBounds();
    addBounds(b, 0, 0, 1);
    return { holes: [], bounds: b, connectors: [], profile };
  }

  const placed = holes.map((hole, i) => {
    if (prepositioned) return clone(hole);
    const r = routing[i] || {
      x: Math.cos(i * 1.7) * 520,
      z: Math.sin(i * 1.7) * 520,
      a: (i * 47) % 360,
    };
    return transformHole(hole, r.x * spread, r.z * spread, r.a * DEG);
  });

  const worldWater = baseWater.map((w) => scaledWater(w, spread));
  const boundsPieces = placed.map(measureHole);
  for (const w of worldWater) {
    boundsPieces.push({
      minX: w.cx - w.rx, maxX: w.cx + w.rx,
      minZ: w.cz - w.rz, maxZ: w.cz + w.rz,
    });
  }
  const bounds = mergeBounds(boundsPieces, boundsMargin);
  const connectors = [];
  for (let i = 0; i < placed.length - 1; i++) connectors.push(connectorBetween(placed[i], placed[i + 1]));

  for (const hole of placed) {
    hole.island = {
      bounds,
      connectors,
      water: worldWater,
      holeCount: placed.length,
      profile,
      coastline,
      elevation,
      paths,
      visualZones,
      osmCoastline,
    };
  }

  return { holes: placed, bounds, connectors, water: worldWater, profile, coastline, elevation, paths, visualZones, osmCoastline };
}
