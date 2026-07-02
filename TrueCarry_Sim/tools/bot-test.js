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
  const pebbleWorld = {
    profile: 'coastal',
    ...(typeof PEBBLE_PRIVATE_WORLD !== 'undefined' ? PEBBLE_PRIVATE_WORLD : {}),
    ...(typeof PEBBLE_OSM_WORLD !== 'undefined' ? PEBBLE_OSM_WORLD : {}),
    ...(typeof PEBBLE_WORLD_REALISM !== 'undefined' ? PEBBLE_WORLD_REALISM : {}),
    elevation: typeof PEBBLE_ELEVATION !== 'undefined' ? PEBBLE_ELEVATION : null,
  };
  const laidOutPebble = typeof layoutIslandCourse !== 'undefined'
    ? layoutIslandCourse(pebbleHoles, pebbleWorld).holes
    : pebbleHoles;
  TEST_COURSES.push({ name: 'Cypress Coast Links', holes: laidOutPebble });
}

if (typeof AUGUSTA_PRIVATE_HOLES !== 'undefined') {
  const augustaHoles = typeof AUGUSTA_OSM_BY_HOLE !== 'undefined'
    ? AUGUSTA_PRIVATE_HOLES.map(h => ({ ...h, osm: AUGUSTA_OSM_BY_HOLE[h.id] || null }))
    : AUGUSTA_PRIVATE_HOLES;
  const augustaWorld = {
    profile: 'coastal',
    ...(typeof AUGUSTA_PRIVATE_WORLD !== 'undefined' ? AUGUSTA_PRIVATE_WORLD : { prepositioned: true }),
    elevation: typeof AUGUSTA_ELEVATION !== 'undefined' ? AUGUSTA_ELEVATION : null,
  };
  const laidOutAugusta = typeof layoutIslandCourse !== 'undefined'
    ? layoutIslandCourse(augustaHoles, augustaWorld).holes
    : augustaHoles;
  TEST_COURSES.push({ name: 'Magnolia Hills', holes: laidOutAugusta });
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
    if (courseName.indexOf('Cypress Coast') >= 0) {
      if (teeS === 'water' || pinS === 'water') {
        print("  !!! Cypress Coast playable point classified as water");
        failures++;
      }
      const coast = hole.island && hole.island.coastline && hole.island.coastline.beach;
      const land = hole.island && hole.island.coastline && hole.island.coastline.land;
      if (coast && land && coast.length > 5) {
        let oceanOk = false;
        for (let ci = 1; ci < coast.length - 1; ci += Math.max(1, Math.floor(coast.length / 16))) {
          const n = coastlineOutsideNormal(coast, ci, land);
          const sample = { x: coast[ci].x + n.x * 42, z: coast[ci].z + n.z * 42 };
          if (course.surfaceAt(sample.x, sample.z) === 'water') {
            oceanOk = true;
            break;
          }
        }
        if (!oceanOk) {
          print("  !!! Cypress Coast coastline samples did not classify as ocean");
          failures++;
        }
      }
    }
    if (courseName.indexOf('Magnolia Hills') >= 0) {
      // Real course accuracy: centerline length must track the official card.
      let pathM = 0;
      for (let pi = 1; pi < hole.path.length; pi++) {
        pathM += Math.hypot(hole.path[pi].x - hole.path[pi - 1].x, hole.path[pi].z - hole.path[pi - 1].z);
      }
      const pathY = pathM * 1.09361;
      if (hole.cardYards && Math.abs(pathY - hole.cardYards) / hole.cardYards > 0.15) {
        print("  !!! centerline " + Math.round(pathY) + "y vs card " + hole.cardYards + "y");
        failures++;
      }
      // Water holes (Amen Corner creek, 15/16 ponds) must classify as water.
      if (hole.id === 12 || hole.id === 15 || hole.id === 16) {
        if (!hole.water.length) {
          print("  !!! expected water features on hole " + hole.id);
          failures++;
        } else {
          let wet = false;
          for (const w of hole.water) {
            const probe = w.type === 'pond'
              ? { x: w.cx, z: w.cz }
              : w.pts[Math.floor(w.pts.length / 2)];
            if (course.surfaceAt(probe.x, probe.z) === 'water') { wet = true; break; }
          }
          if (!wet) {
            print("  !!! hole " + hole.id + " water probes did not classify as water");
            failures++;
          }
        }
      }
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
    let lie = 'tee', strokes = 0, holed = false, waterBias = 0, retryClubBump = 0;
    const pin = course.pinPos;

    for (let shot = 1; shot <= 16 && !holed; shot++) {
      // After a splash the replay is from the same spot; carry further each try.
      const rem = Math.hypot(pos.x - pin.x, pos.z - pin.z) + waterBias;
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
        if (retryClubBump > 0) {
          // Replaying over water: a longer club, not the same splash again.
          c = CLUBS[Math.max(0, CLUBS.indexOf(c) - retryClubBump)];
        }
        const frac = Math.min(rem * 0.97 / (c.carryM * lieE.speed), 1.05);
        power = Math.min(Math.max((Math.pow(frac, 1 / 1.8) - 0.3) / 0.7, 0.2), 1);
      }

      let target = pin;
      if (mode === 'fly' && rem > 125) {
        const current = course.pathInfo(pos.x, pos.z);
        const advance = Math.max(72, Math.min(c.carryM * 0.82, rem * 0.78)) + waterBias;
        target = course.pointAtAlong(Math.min(holeLength(hole), current.along + advance));
      }
      const dx = target.x - pos.x, dz = target.z - pos.z, L = Math.hypot(dx, dz) || 1;
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
        waterBias += 18;
        retryClubBump++;
        print("  shot " + shot + " " + c.name + " pw" + power.toFixed(2) + " -> WATER (+1, replay)");
        continue;
      } else {
        pos = { x: sim.pos.x, y: sim.pos.y, z: sim.pos.z };
        lie = course.surfaceAt(pos.x, pos.z);
        waterBias = 0;
        retryClubBump = 0;
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
