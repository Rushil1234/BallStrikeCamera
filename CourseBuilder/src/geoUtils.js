// Geographic utilities — WGS84 ↔ local flat-earth meters.
// All angles in degrees. Origin is the course center.
// Coordinate system: x = east (+), z = north (-) mirroring Three.js convention.

export function makeProjector(originLat, originLng) {
  const RAD = Math.PI / 180;
  const mPerDegLat = 111320;
  const mPerDegLng = 111320 * Math.cos(originLat * RAD);

  return {
    toXZ(lat, lng) {
      return {
        x: (lng - originLng) * mPerDegLng,
        z: (lat - originLat) * mPerDegLat,
      };
    },
    toLngLat(x, z) {
      return {
        lng: originLng + x / mPerDegLng,
        lat: originLat + z / mPerDegLat,
      };
    },
    mPerDegLat,
    mPerDegLng,
  };
}

export function ringToXZ(coords, proj) {
  return coords.map(([lat, lng]) => [proj.toXZ(lat, lng).x, proj.toXZ(lat, lng).z]);
}

export function centroidXZ(ring) {
  const n = ring.length;
  return [ring.reduce((s, p) => s + p[0], 0) / n, ring.reduce((s, p) => s + p[1], 0) / n];
}

export function dist2D(a, b) {
  return Math.hypot(a[0] - b[0], a[1] - b[1]);
}

// Point-to-segment distance (2D)
export function ptToSeg(p, a, b) {
  const dx = b[0] - a[0], dz = b[1] - a[1];
  const len2 = dx * dx + dz * dz;
  if (len2 === 0) return dist2D(p, a);
  const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / len2));
  return dist2D(p, [a[0] + t * dx, a[1] + t * dz]);
}

// Minimum distance from point to a polyline
export function ptToPath(p, path) {
  let min = Infinity;
  for (let i = 0; i < path.length - 1; i++) min = Math.min(min, ptToSeg(p, path[i], path[i + 1]));
  return min;
}

// Generate a corridor polygon around a path with given half-width
export function corridorPolygon(path, halfWidth) {
  if (path.length < 2) return [];
  const left = [], right = [];
  for (let i = 0; i < path.length; i++) {
    const prev = path[Math.max(0, i - 1)];
    const next = path[Math.min(path.length - 1, i + 1)];
    const dx = next[0] - prev[0], dz = next[1] - prev[1];
    const len = Math.hypot(dx, dz) || 1;
    const px = -dz / len * halfWidth, pz = dx / len * halfWidth;
    left.push([path[i][0] + px, path[i][1] + pz]);
    right.push([path[i][0] - px, path[i][1] - pz]);
  }
  return [...left, ...right.reverse(), left[0]];
}

// Point-in-polygon (ray casting)
export function pointInPolygon(px, pz, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const xi = poly[i][0], zi = poly[i][1];
    const xj = poly[j][0], zj = poly[j][1];
    if ((zi > pz) !== (zj > pz) && px < ((xj - xi) * (pz - zi)) / (zj - zi) + xi) inside = !inside;
  }
  return inside;
}

// Area of polygon (shoelace)
export function polyArea(poly) {
  let area = 0;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    area += poly[j][0] * poly[i][1] - poly[i][0] * poly[j][1];
  }
  return Math.abs(area) / 2;
}

// Random points inside polygon (rejection sampling)
export function randomPointsInPoly(poly, count) {
  const xs = poly.map(p => p[0]), zs = poly.map(p => p[1]);
  const minX = Math.min(...xs), maxX = Math.max(...xs);
  const minZ = Math.min(...zs), maxZ = Math.max(...zs);
  const pts = [];
  let tries = 0;
  while (pts.length < count && tries < count * 20) {
    tries++;
    const x = minX + Math.random() * (maxX - minX);
    const z = minZ + Math.random() * (maxZ - minZ);
    if (pointInPolygon(x, z, poly)) pts.push([x, z]);
  }
  return pts;
}
