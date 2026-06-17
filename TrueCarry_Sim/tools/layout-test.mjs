import { LOCAL_COURSES } from '../js/local-courses.js';
import { layoutIslandCourse } from '../js/world.js';

const failures = [];
const summaries = [];

function ellipseVal(w, x, z) {
  const dx = x - w.cx;
  const dz = z - w.cz;
  const c = Math.cos(w.rot || 0);
  const s = Math.sin(w.rot || 0);
  const lx = dx * c + dz * s;
  const lz = -dx * s + dz * c;
  return (lx / w.rx) ** 2 + (lz / w.rz) ** 2;
}

function waterClearance(w, x, z, pad) {
  const normalizedRadius = Math.sqrt(ellipseVal(w, x, z));
  return (normalizedRadius - 1) * Math.min(w.rx, w.rz) - pad;
}

function orient(a, b, c) {
  return (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x);
}

function segmentsIntersect(a, b, c, d) {
  return orient(a, b, c) * orient(a, b, d) < 0
    && orient(c, d, a) * orient(c, d, b) < 0;
}

function segmentDistance(a, b, c, d) {
  const vx = b.x - a.x;
  const vz = b.z - a.z;
  const wx = d.x - c.x;
  const wz = d.z - c.z;
  const px = a.x - c.x;
  const pz = a.z - c.z;
  const A = vx * vx + vz * vz;
  const B = vx * wx + vz * wz;
  const C = wx * wx + wz * wz;
  const D = vx * px + vz * pz;
  const E = wx * px + wz * pz;
  const denom = A * C - B * B;
  let s = 0;
  let t = 0;
  if (denom !== 0) s = Math.max(0, Math.min(1, (B * E - C * D) / denom));
  t = (B * s + E) / C;
  if (t < 0) {
    t = 0;
    s = Math.max(0, Math.min(1, -D / A));
  } else if (t > 1) {
    t = 1;
    s = Math.max(0, Math.min(1, (B - D) / A));
  }
  const ax = a.x + vx * s;
  const az = a.z + vz * s;
  const bx = c.x + wx * t;
  const bz = c.z + wz * t;
  return Math.hypot(ax - bx, az - bz);
}

function fail(course, message) {
  failures.push(`${course.courseName}: ${message}`);
}

function checkCourse(course) {
  const world = layoutIslandCourse(course.holes, course.world || {});
  const realPositioned = !!course.world?.prepositioned;

  if (!realPositioned) {
    for (let i = 0; i < world.holes.length; i++) {
      for (let j = i + 1; j < world.holes.length; j++) {
        const aHole = world.holes[i];
        const bHole = world.holes[j];
        let minDistance = Infinity;
        for (let ai = 0; ai < aHole.path.length - 1; ai++) {
          for (let bi = 0; bi < bHole.path.length - 1; bi++) {
            if (segmentsIntersect(aHole.path[ai], aHole.path[ai + 1], bHole.path[bi], bHole.path[bi + 1])) {
              fail(course, `fairway centerlines cross: hole ${aHole.id} segment ${ai + 1} with hole ${bHole.id} segment ${bi + 1}`);
            }
            minDistance = Math.min(
              minDistance,
              segmentDistance(aHole.path[ai], aHole.path[ai + 1], bHole.path[bi], bHole.path[bi + 1]),
            );
          }
        }
        const minFairwayGap = (aHole.fairwayHalf || 15) + (bHole.fairwayHalf || 15) + 18;
        if (minDistance < minFairwayGap) {
          fail(course, `fairway corridors too close: holes ${aHole.id}/${bHole.id} are ${minDistance.toFixed(1)}m apart, need ${minFairwayGap}m`);
        }
      }
    }
  }

  for (const hole of world.holes) {
    const pathPad = (hole.fairwayHalf || 15) + 8;
    let minPathClearance = Infinity;
    for (let i = 0; i < hole.path.length - 1; i++) {
      const a = hole.path[i];
      const b = hole.path[i + 1];
      for (let k = 0; k <= 80; k++) {
        const t = k / 80;
        const x = a.x + (b.x - a.x) * t;
        const z = a.z + (b.z - a.z) * t;
        for (const w of world.water || []) {
          minPathClearance = Math.min(minPathClearance, waterClearance(w, x, z, pathPad));
        }
      }
    }
    if (minPathClearance < 0) {
      fail(course, `hole ${hole.id} fairway overlaps shared water by ${Math.abs(minPathClearance).toFixed(1)}m`);
    }

    const featureChecks = [
      ['tee', hole.path[0], 10],
      ['green', { x: hole.green.cx, z: hole.green.cz }, Math.max(hole.green.rx, hole.green.rz) + 8],
      ['pin', hole.pin, 6],
      ...(hole.bunkers || []).map((b, i) => [`bunker ${i + 1}`, { x: b.cx, z: b.cz }, Math.max(b.rx, b.rz) + 5]),
    ];
    for (const [label, p, pad] of featureChecks) {
      for (const w of world.water || []) {
        const clear = waterClearance(w, p.x, p.z, pad);
        if (clear < 0) {
          fail(course, `hole ${hole.id} ${label} is inside shared water by ${Math.abs(clear).toFixed(1)}m`);
        }
      }
    }
  }

  summaries.push(`${course.courseName}: ${world.holes.length} holes, ${world.water.length} shared water zones`);
}

for (const course of LOCAL_COURSES) {
  checkCourse(course);
}

if (failures.length) {
  console.error(failures.join('\n'));
  process.exit(1);
}

console.log(`Layout OK: ${summaries.join('; ')}. Fairways separated, no shared-water overlaps.`);
