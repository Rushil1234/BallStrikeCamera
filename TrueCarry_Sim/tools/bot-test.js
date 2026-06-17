// Headless regression: a competent bot plays every hole through the real
// terrain + physics. Run with tools/test.sh (uses macOS JavaScriptCore).
for (const c of CLUBS) {
  if (!c.putter) {
    const r = simulateCarry(c.speed, c.launch, c.spin);
    c.carryM = r.carry; c.totalM = r.total;
  } else c.carryM = 0;
}

const TEST_COURSES = [
  { name: 'Pine Hollow National', holes: HOLES },
];

if (typeof PEBBLE_PRIVATE_HOLES !== 'undefined') {
  const pebbleHoles = typeof PEBBLE_OSM_BY_HOLE !== 'undefined'
    ? PEBBLE_PRIVATE_HOLES.map(h => ({ ...h, osm: PEBBLE_OSM_BY_HOLE[h.id] || null }))
    : PEBBLE_PRIVATE_HOLES;
  TEST_COURSES.push({ name: 'Pebble Private Prototype', holes: pebbleHoles });
}

let failures = 0;

function playCourse(courseName, holes) {
  let totalStrokes = 0;
  let totalPar = 0;
  const startFailures = failures;

  print("");
  print("### COURSE " + courseName + " ###");

  for (const hole of holes) {
    const course = buildCourse(hole);
    print("=== HOLE " + hole.id + " " + hole.name + " par " + hole.par + " " +
          Math.round(holeLength(hole) * 1.09361) + "y ===");
    const teeS = course.surfaceAt(course.teePos.x, course.teePos.z);
    const pinS = course.surfaceAt(hole.pin.x, hole.pin.z);
    if (teeS !== 'tee' || pinS !== 'green') {
      print("  !!! bad surfaces: tee=" + teeS + " pin=" + pinS);
      failures++;
    }
    // boundary sanity: the playing corridor is in bounds, way offline is not
    const mid = course.pointAtAlong(holeLength(hole) / 2);
    const tee = hole.path[0];
    const green = hole.path[hole.path.length - 1];
    const hx = green.x - tee.x;
    const hz = green.z - tee.z;
    const hL = Math.hypot(hx, hz) || 1;
    const offline = { x: mid.x - (hz / hL) * 200, z: mid.z + (hx / hL) * 200 };
    if (course.isOB(course.teePos.x, course.teePos.z) || course.isOB(hole.pin.x, hole.pin.z)
        || course.isOB(mid.x, mid.z) || !course.isOB(offline.x, offline.z)
        || hole.bunkers.some(b => course.isOB(b.cx, b.cz))) {
      print("  !!! OB corridor misplaced");
      failures++;
    }

    let pos = { x: course.teePos.x, y: course.teePos.y + 0.0214, z: course.teePos.z };
    let lie = 'tee', strokes = 0, holed = false;
    const pin = course.pinPos;

    for (let shot = 1; shot <= 16 && !holed; shot++) {
      const rem = Math.hypot(pos.x - pin.x, pos.z - pin.z);
      const lieE = LIE_EFFECT[lie] || LIE_EFFECT.fairway;
      let c, power, mode = 'fly';

      if ((lie === 'green' || lie === 'fringe') && rem < 30) {
        c = CLUBS[CLUBS.length - 1]; mode = 'roll';
        const v = Math.min(Math.sqrt(2 * 0.72 * rem) * 1.12 + 0.25, c.speed);
        power = v / c.speed;
      } else {
        // smallest club that reaches, swung at partial power to fit the number
        c = CLUBS[CLUBS.length - 2];
        for (let i = 0; i < CLUBS.length - 1; i++) {
          if (CLUBS[i].carryM * lieE.speed >= rem * 0.98) c = CLUBS[i];
          else break;
        }
        if (lie === 'sand' && rem < 110) c = CLUBS[CLUBS.length - 2];
        const frac = Math.min(rem * 0.97 / (c.carryM * lieE.speed), 1.05);
        power = Math.min(Math.max((Math.pow(frac, 1 / 1.8) - 0.3) / 0.7, 0.2), 1);
      }

      const dx = pin.x - pos.x, dz = pin.z - pos.z, L = Math.hypot(dx, dz) || 1;
      const speed = c.putter ? c.speed * power : c.speed * (0.3 + 0.7 * power) * lieE.speed;
      strokes++;
      const sim = createShot({
        pos: { ...pos }, dir: { x: dx / L, z: dz / L }, speed,
        launchDeg: c.putter ? 0 : c.launch,
        backspinRpm: c.putter ? 0 : c.spin * lieE.spin * (0.55 + 0.45 * power),
        sidespinRpm: 0, wind: { x: 0, z: 0 }, course,
        pin: { x: pin.x, z: pin.z }, mode: c.putter ? 'roll' : 'fly',
      });
      for (let i = 0; i < 6000 && (sim.state === 'fly' || sim.state === 'roll'); i++) sim.step(1 / 60);
      if (isNaN(sim.pos.x) || isNaN(sim.pos.y)) { print("  !!! NaN position"); failures++; break; }
      const endRem = Math.hypot(sim.pos.x - pin.x, sim.pos.z - pin.z);
      if (sim.state === 'holed') holed = true;
      else if (sim.state === 'water') {
        strokes++;
        print("  shot " + shot + " " + c.name + " pw" + power.toFixed(2) + " -> WATER (+1, replay)");
        continue;
      } else {
        pos = { x: sim.pos.x, y: sim.pos.y, z: sim.pos.z };
        lie = course.surfaceAt(pos.x, pos.z);
      }
      print("  shot " + shot + " " + c.name + " pw" + power.toFixed(2) + " -> " +
            (holed ? "HOLED" : lie) + "  remaining " +
            (endRem < 20 ? (endRem * 3.28084).toFixed(1) + "ft" : Math.round(endRem * 1.09361) + "y"));
    }
    if (!holed) { print("  !!! never holed out"); failures++; }
    else print("  score " + strokes + " (par " + hole.par + ")");
    totalStrokes += strokes; totalPar += hole.par;
  }

  print("");
  print(courseName + " ROUND: " + totalStrokes + " strokes, par " + totalPar +
        " (" + (totalStrokes - totalPar >= 0 ? "+" : "") + (totalStrokes - totalPar) + ")" +
        (failures > startFailures ? "  FAILURES: " + (failures - startFailures) : "  all holes OK"));
}

for (const testCourse of TEST_COURSES) {
  playCourse(testCourse.name, testCourse.holes);
}

print("");
print("TOTAL FAILURES: " + failures);
