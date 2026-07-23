// geometry.mjs
// Port of the iOS HoleInference / GolfGeometry logic (Swift) into JS, so server-baked geometry
// matches what the app would have inferred live. Pure functions, no I/O.
//
// All distances in yards unless noted. Coordinates are { lat, lon }.

const METERS_PER_YARD = 0.9144;

export function yardsBetween(a, b) {
  // Haversine, returned in yards.
  const R = 6_371_000; // meters
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLon = ((b.lon - a.lon) * Math.PI) / 180;
  const lat1 = (a.lat * Math.PI) / 180;
  const lat2 = (b.lat * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  const meters = 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
  return meters / METERS_PER_YARD;
}

export function centroid(coords) {
  if (!coords || coords.length === 0) return null;
  const lat = coords.reduce((s, c) => s + c.lat, 0) / coords.length;
  const lon = coords.reduce((s, c) => s + c.lon, 0) / coords.length;
  return { lat, lon };
}

function bearingDeg(from, to) {
  const lat1 = (from.lat * Math.PI) / 180;
  const lat2 = (to.lat * Math.PI) / 180;
  const dLon = ((to.lon - from.lon) * Math.PI) / 180;
  const y = Math.sin(dLon) * Math.cos(lat2);
  const x =
    Math.cos(lat1) * Math.sin(lat2) -
    Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
  return (Math.atan2(y, x) * 180) / Math.PI;
}

function project(start, bearingDegrees, distanceMeters) {
  const R = 6_371_000;
  const brng = (bearingDegrees * Math.PI) / 180;
  const lat1 = (start.lat * Math.PI) / 180;
  const lon1 = (start.lon * Math.PI) / 180;
  const ad = distanceMeters / R;
  const lat2 = Math.asin(
    Math.sin(lat1) * Math.cos(ad) + Math.cos(lat1) * Math.sin(ad) * Math.cos(brng)
  );
  const lon2 =
    lon1 +
    Math.atan2(
      Math.sin(brng) * Math.sin(ad) * Math.cos(lat1),
      Math.cos(ad) - Math.sin(lat1) * Math.sin(lat2)
    );
  return { lat: (lat2 * 180) / Math.PI, lon: (lon2 * 180) / Math.PI };
}

// Mirror of GolfGeometry.synthesizeGreen (Swift): 12m front/back, 10m left/right.
export function synthesizeGreen(center, tee) {
  const heading = tee ? bearingDeg(tee, center) : 0;
  const front = project(center, heading + 180, 12);
  const back = project(center, heading, 12);
  const left = project(center, heading - 90, 10);
  const right = project(center, heading + 90, 10);
  return {
    front,
    back,
    polygon: [front, right, back, left, front],
  };
}

function inferPar(distYds) {
  if (distYds < 245) return 3;
  if (distYds < 480) return 4;
  return 5;
}

function popNearest(pool, point) {
  if (pool.length === 0) return null;
  let bestIdx = 0;
  let bestDist = Infinity;
  for (let i = 0; i < pool.length; i++) {
    const c = centroid(pool[i].coords);
    const d = c ? yardsBetween(c, point) : Infinity;
    if (d < bestDist) {
      bestDist = d;
      bestIdx = i;
    }
  }
  return pool.splice(bestIdx, 1)[0];
}

// classified: { greens:[{coords}], tees:[{coords}], fairways:[{coords}],
//               holeWays:[{coords, ref, par}], pins:[{lat,lon}] }
// Returns an array of hole objects: { number, par, tee, center, front, back, polygon, path }.
export function inferHoles(classified) {
  const authoritative = (classified.holeWays || []).filter(
    (w) => Number.isInteger(w.ref) && w.coords.length >= 2
  );
  if (authoritative.length >= 9) {
    return buildAuthoritative(authoritative, classified);
  }
  return buildInferred(classified);
}

function buildAuthoritative(holeWays, classified) {
  const sorted = [...holeWays].sort((a, b) => a.ref - b.ref);
  const greens = [...classified.greens];
  const tees = [...classified.tees];
  return sorted
    .map((w) => {
      const teeEnd = w.coords[0];
      const greenEnd = w.coords[w.coords.length - 1];
      const green = popNearest(greens, greenEnd);
      const tee = popNearest(tees, teeEnd);
      const center = green ? centroid(green.coords) : greenEnd;
      const teeCoord = tee ? centroid(tee.coords) : teeEnd;
      if (!center) return null;
      return finishHole({
        number: w.ref,
        par: w.par ?? inferPar(yardsBetween(teeCoord, center)),
        tee: teeCoord,
        center,
        greenCoords: green ? green.coords : null,
        path: w.coords,
      });
    })
    .filter(Boolean);
}

function buildInferred(classified) {
  const greens = [...classified.greens];
  const tees = [...classified.tees];
  const pending = [];
  let g;
  while ((g = greens.pop())) {
    const center = centroid(g.coords);
    if (!center) continue;
    const tee = popNearest(tees, center);
    pending.push({ green: g, tee, center });
  }
  // Order by greedy nearest walk from the southernmost tee/green.
  const ordered = orderByWalk(pending);
  return ordered
    .map((p, idx) => {
      const teeCoord = p.tee ? centroid(p.tee.coords) : p.center;
      return finishHole({
        number: idx + 1,
        par: inferPar(yardsBetween(p.center, teeCoord)),
        tee: teeCoord,
        center: p.center,
        greenCoords: p.green.coords,
        path: [teeCoord, p.center],
      });
    })
    .filter(Boolean);
}

function orderByWalk(pending) {
  if (pending.length === 0) return [];
  const remaining = [...pending];
  let seed = 0;
  let minLat = Infinity;
  remaining.forEach((p, i) => {
    const lat = (p.tee && centroid(p.tee.coords)?.lat) ?? p.center.lat;
    if (lat < minLat) {
      minLat = lat;
      seed = i;
    }
  });
  let current = remaining.splice(seed, 1)[0];
  const ordered = [current];
  while (remaining.length) {
    let nextIdx = 0;
    let best = Infinity;
    remaining.forEach((p, i) => {
      const c = (p.tee && centroid(p.tee.coords)) || p.center;
      const d = yardsBetween(current.center, c);
      if (d < best) {
        best = d;
        nextIdx = i;
      }
    });
    current = remaining.splice(nextIdx, 1)[0];
    ordered.push(current);
  }
  return ordered;
}

function finishHole({ number, par, tee, center, greenCoords, path }) {
  let polygon = greenCoords && greenCoords.length >= 3 ? greenCoords : null;
  let front = null;
  let back = null;
  if (!polygon) {
    const synth = synthesizeGreen(center, tee);
    polygon = synth.polygon;
    front = synth.front;
    back = synth.back;
  } else if (tee) {
    // Real OSM green: derive front/back from the traced polygon along the hole's
    // line of play (tee -> center) instead of leaving them null.
    const fb = greenFrontBack(polygon, tee, center);
    front = fb.front;
    back = fb.back;
  }
  return { number, par, tee, center, front, back, polygon, path };
}

// Front/back points of a green polygon along the approach->center line of play.
// front = polygon vertex nearest the player; back = farthest. approach is the
// tee (or fairway) the hole is played from. Returns { front, back } (may be null).
export function greenFrontBack(polygon, approach, center) {
  if (!polygon || polygon.length < 3 || !approach || !center) {
    return { front: null, back: null };
  }
  const mLat = 111_320;
  const mLon = 111_320 * Math.cos((center.lat * Math.PI) / 180);
  const dx = (center.lon - approach.lon) * mLon;
  const dy = (center.lat - approach.lat) * mLat;
  const n = Math.hypot(dx, dy);
  if (n < 1) return { front: null, back: null }; // approach ~ on the green
  const ux = dx / n;
  const uy = dy / n;
  let lo = { a: Infinity, p: null };
  let hi = { a: -Infinity, p: null };
  for (const c of polygon) {
    const a = (c.lon - center.lon) * mLon * ux + (c.lat - center.lat) * mLat * uy;
    if (a < lo.a) lo = { a, p: c };
    if (a > hi.a) hi = { a, p: c };
  }
  return { front: lo.p, back: hi.p };
}

// Distance (yards) from a point to the tee->green segment, for attributing a
// hazard polygon to the hole whose corridor it actually sits in.
export function distToSegmentYds(pt, a, b) {
  const mLon = 111_320 * Math.cos((pt.lat * Math.PI) / 180);
  const px = pt.lon * mLon;
  const py = pt.lat * 111_320;
  const ax = a.lon * mLon;
  const ay = a.lat * 111_320;
  const bx = b.lon * mLon;
  const by = b.lat * 111_320;
  const dx = bx - ax;
  const dy = by - ay;
  const L2 = dx * dx + dy * dy;
  const t = L2 === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / L2));
  const cx = ax + t * dx;
  const cy = ay + t * dy;
  return Math.hypot(px - cx, py - cy) / 0.9144;
}
