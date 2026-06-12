// GPS → TrueCarry_Sim format converter.
// Converts GolfCourse objects (from Supabase course_geometries.payload)
// into the holes[] format used by TrueCarry_Sim/js/holes.js.
// Safe to load as a plain <script> tag (no ES module syntax).

// ─── Geodesic math ──────────────────────────────────────────────────────────

function gpsToLocal(lat, lng, ref) {
  const M = 111319.5;
  const x = (lng - ref.lng) * Math.cos(ref.lat * Math.PI / 180) * M;
  const z = (lat - ref.lat) * M;
  return { x, z };
}

function ptsDist(a, b) {
  return Math.hypot(b.x - a.x, b.z - a.z);
}

function polygonCentroid(coords, ref) {
  const pts = coords.map(c => gpsToLocal(c.latitude, c.longitude, ref));
  const cx = pts.reduce((s, p) => s + p.x, 0) / pts.length;
  const cz = pts.reduce((s, p) => s + p.z, 0) / pts.length;
  return { cx, cz, pts };
}

function polygonToEllipse(coords, ref) {
  const { cx, cz, pts } = polygonCentroid(coords, ref);
  const rx = Math.max(...pts.map(p => Math.abs(p.x - cx)));
  const rz = Math.max(...pts.map(p => Math.abs(p.z - cz)));

  // Rough rotation from bounding-box principal axis
  let rot = 0;
  if (pts.length >= 3) {
    let sxx = 0, szz = 0, sxz = 0;
    pts.forEach(p => {
      const dx = p.x - cx, dz = p.z - cz;
      sxx += dx * dx; szz += dz * dz; sxz += dx * dz;
    });
    rot = 0.5 * Math.atan2(2 * sxz, sxx - szz);
  }

  return { cx, cz, rx: Math.max(rx, 3), rz: Math.max(rz, 3), rot };
}

function polygonToWater(coords, ref) {
  const { cx, cz, pts } = polygonCentroid(coords, ref);
  const rx = Math.max(...pts.map(p => Math.abs(p.x - cx)));
  const rz = Math.max(...pts.map(p => Math.abs(p.z - cz)));

  // Elongated → channel; round-ish → pond
  const aspect = Math.max(rx, rz) / (Math.min(rx, rz) || 1);
  if (aspect > 2.5) {
    const isWide = rx > rz;
    return {
      type: 'channel',
      width: Math.max(8, Math.min(rx, rz) * 1.6),
      pts: isWide
        ? [{ x: cx - rx, z: cz }, { x: cx + rx, z: cz }]
        : [{ x: cx, z: cz - rz }, { x: cx, z: cz + rz }],
    };
  }
  return { type: 'pond', cx, cz, rx: Math.max(rx, 6), rz: Math.max(rz, 6), rot: 0 };
}

// Estimate fairwayHalf: average perpendicular distance from the path axis
// to the polygon boundary, clamped to [9, 28].
function estimateFairwayHalf(polygon, ref, path) {
  if (!polygon?.coordinates?.length || path.length < 2) return 16;
  const pts = polygon.coordinates.map(c => gpsToLocal(c.latitude, c.longitude, ref));

  // Path direction
  const last = path[path.length - 1];
  const dLen = Math.hypot(last.x - path[0].x, last.z - path[0].z) || 1;
  const perp = { x: -(last.z - path[0].z) / dLen, z: (last.x - path[0].x) / dLen };

  const dists = pts.map(p => Math.abs(p.x * perp.x + p.z * perp.z));
  const avg = dists.reduce((s, d) => s + d, 0) / (dists.length || 1);
  return Math.max(9, Math.min(28, avg));
}

// ─── Single-hole conversion ──────────────────────────────────────────────────

function convertHoleToSim(hole) {
  const tee = hole.teeCoordinate ||
    (hole.teeCoordinateByTeeBox && Object.values(hole.teeCoordinateByTeeBox)[0]);

  if (!tee) return null;
  const ref = { lat: tee.latitude, lng: tee.longitude };

  // Build path (tee at origin, then waypoints, green last)
  let path = [{ x: 0, z: 0 }];
  const pathCoords = hole.pathCoordinates || [];
  for (const c of pathCoords.slice(1)) {
    const pt = gpsToLocal(c.latitude, c.longitude, ref);
    // Deduplicate (skip if too close to last point)
    if (path.length === 0 || ptsDist(path[path.length - 1], pt) > 2) {
      path.push(pt);
    }
  }

  // Green center
  const gc = hole.greenCenterCoordinate;
  let greenLocal = gc ? gpsToLocal(gc.latitude, gc.longitude, ref) : null;

  // If green isn't already the last path point, append it
  if (greenLocal && path.length > 0 && ptsDist(path[path.length - 1], greenLocal) > 5) {
    path.push({ x: greenLocal.x, z: greenLocal.z });
  }

  // Need at least tee + one more point
  if (path.length < 2) {
    if (greenLocal) { path.push(greenLocal); }
    else { return null; }
  }

  greenLocal = greenLocal || path[path.length - 1];

  // Green ellipse
  let green;
  if (hole.greenPolygon?.coordinates?.length > 2) {
    green = polygonToEllipse(hole.greenPolygon.coordinates, ref);
    green.depth = undefined; // greens don't have depth
  } else {
    green = { cx: greenLocal.x, cz: greenLocal.z, rx: 13, rz: 16, rot: 0 };
  }

  // Pin — offset slightly from green center
  const pin = { x: green.cx + 1.8, z: green.cz + 2.5 };

  // Fairway width
  const fairwayHalf = estimateFairwayHalf(hole.fairwayPolygon, ref, path);

  // Bunkers
  const bunkers = (hole.bunkerPolygons || [])
    .filter(p => p.coordinates?.length > 2)
    .map(p => ({ ...polygonToEllipse(p.coordinates, ref), depth: 1.1 }));

  // Water
  const water = (hole.waterPolygons || [])
    .filter(p => p.coordinates?.length > 2)
    .map(p => polygonToWater(p.coordinates, ref));

  // Confidence score (0–1)
  const hasPath     = (hole.pathCoordinates || []).length > 1;
  const hasFairway  = !!hole.fairwayPolygon;
  const hasGreenPoly= !!hole.greenPolygon;
  const hasBunkers  = (hole.bunkerPolygons || []).length > 0;
  const confidence  = (
    (tee ? 0.25 : 0) +
    (gc  ? 0.25 : 0) +
    (hasPath    ? 0.20 : 0) +
    (hasFairway ? 0.15 : 0) +
    (hasGreenPoly ? 0.10 : 0) +
    (hasBunkers ? 0.05 : 0)
  );

  return {
    id:          hole.number,
    name:        String(hole.number),
    par:         hole.par || 4,
    seed:        hole.number * 1117,
    path,
    fairwayHalf,
    green,
    pin,
    bunkers,
    water,
    treeDensity: 1.0,
    windMax:     6,
    _confidence: confidence,  // internal, stripped before saving
  };
}

// ─── Full course conversion ──────────────────────────────────────────────────

function convertCourseToSim(golfCourse) {
  const holes = (golfCourse.holes || [])
    .filter(h => h.number > 0)
    .sort((a, b) => a.number - b.number)
    .map(convertHoleToSim)
    .filter(Boolean);

  const avgConfidence = holes.length
    ? holes.reduce((s, h) => s + (h._confidence || 0), 0) / holes.length
    : 0;

  // Strip internal fields before returning
  const cleanHoles = holes.map(h => {
    const { _confidence, ...rest } = h;
    return rest;
  });

  return { holes: cleanHoles, avgConfidence };
}

// Export for both browser global and module contexts
if (typeof window !== 'undefined') {
  window.convertCourseToSim = convertCourseToSim;
  window.gpsToLocal = gpsToLocal;
}
if (typeof module !== 'undefined') {
  module.exports = { convertCourseToSim, gpsToLocal, polygonToEllipse };
}
