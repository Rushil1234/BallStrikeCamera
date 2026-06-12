// Headless regression for the /play sim: water-hazard integrity, penalty
// drops, and a competent bot playing every hole through the real terrain +
// physics. Run with tools/test.sh (uses macOS JavaScriptCore).
for (const c of CLUBS) {
  if (!c.putter) {
    const r = simulateCarry(c.speed, c.launch, c.spin);
    c.carryM = r.carry; c.totalM = r.total;
  } else c.carryM = 0;
}

let totalStrokes = 0, totalPar = 0, failures = 0;

// ---------- water integrity ----------
// Any carved ground that sits below the waterline is visually under the
// water plane, so the game must rule it WATER. A ball "at rest" there is
// the "why am I starting inside the water" bug.
for (const hole of HOLES) {
  if (!hole.water.length) continue;
  const course = buildCourse(hole);
  let submergedPlayable = 0, sampled = 0;
  const boxes = [];
  for (const w of hole.water) {
    if (w.type === 'pond') {
      const r = Math.max(w.rx, w.rz) + 14;
      boxes.push({ x0: w.cx - r, x1: w.cx + r, z0: w.cz - r, z1: w.cz + r });
    } else {
      for (const p of w.pts) {
        const r = w.width / 2 + 12;
        boxes.push({ x0: p.x - r, x1: p.x + r, z0: p.z - r, z1: p.z + r });
      }
    }
  }
  for (const b of boxes) {
    for (let x = b.x0; x <= b.x1; x += 1.5) {
      for (let z = b.z0; z <= b.z1; z += 1.5) {
        const { m } = course.waterMask(x, z);
        if (m < 0.02) continue;
        if (course.heightAt(x, z) > course.waterLevel - 0.05) continue;
        sampled++;
        if (course.surfaceAt(x, z) !== 'water') submergedPlayable++;
      }
    }
  }
  if (submergedPlayable > 0) {
    print("HOLE " + hole.id + " water integrity: " + submergedPlayable + "/" + sampled +
          " submerged points are playable (should be WATER)  !!!");
    failures++;
  } else {
    print("HOLE " + hole.id + " water integrity: OK (" + sampled + " submerged points)");
  }
}

// ---------- penalty drop placement ----------
// Fire shots straight into each hazard; the computed drop must be on dry
// ground that is clearly above the waterline.
for (const hole of HOLES) {
  if (!hole.water.length) continue;
  const course = buildCourse(hole);
  if (typeof findDropPoint !== 'function') {
    print("HOLE " + hole.id + " drop: findDropPoint missing  !!!");
    failures++;
    break;
  }
  for (const w of hole.water) {
    const target = w.type === 'pond' ? { x: w.cx, z: w.cz }
      : { x: w.pts[Math.floor(w.pts.length / 2)].x, z: w.pts[Math.floor(w.pts.length / 2)].z };
    const start = { x: course.teePos.x, y: course.teePos.y + 0.0214, z: course.teePos.z };
    const dx = target.x - start.x, dz = target.z - start.z;
    const L = Math.hypot(dx, dz) || 1;
    // pick a club that lands in the hazard: carry ~ distance to target
    let c = CLUBS[0];
    for (const cc of CLUBS) {
      if (!cc.putter && cc.carryM >= L * 0.98) c = cc;
    }
    const sim = createShot({
      pos: { ...start }, dir: { x: dx / L, z: dz / L }, speed: c.speed,
      launchDeg: c.launch, backspinRpm: c.spin, sidespinRpm: 0,
      wind: { x: 0, z: 0 }, course, pin: { x: course.pinPos.x, z: course.pinPos.z },
      mode: 'fly',
    });
    const pts = [];
    for (let i = 0; i < 6000 && (sim.state === 'fly' || sim.state === 'roll'); i++) {
      sim.step(1 / 60);
      pts.push({ x: sim.pos.x, z: sim.pos.z });
    }
    if (sim.state !== 'water') continue; // shot missed the hazard — nothing to test
    const drop = findDropPoint(course, pts, start);
    const ds = course.surfaceAt(drop.x, drop.z);
    const dh = course.heightAt(drop.x, drop.z);
    const dm = course.waterMask(drop.x, drop.z).m;
    if (ds === 'water' || (dm >= 0.02 && dh <= course.waterLevel + 0.2)) {
      print("HOLE " + hole.id + " drop: wet drop at (" + drop.x.toFixed(1) + "," + drop.z.toFixed(1) +
            ") surf=" + ds + " h=" + dh.toFixed(2) + " wl=" + course.waterLevel.toFixed(2) + "  !!!");
      failures++;
    } else {
      print("HOLE " + hole.id + " drop: OK (surf=" + ds + ", mask=" + dm.toFixed(2) + ")");
    }
  }
}

// ---------- bot round ----------
for (const hole of HOLES) {
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
  if (course.isOB(course.teePos.x, course.teePos.z) || course.isOB(hole.pin.x, hole.pin.z)
      || course.isOB(mid.x, mid.z) || !course.isOB(mid.x + 200, mid.z)
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
      // smallest club that reaches (driver when nothing does),
      // swung at partial power to fit the number
      c = CLUBS[0];
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
    const pts = [];
    for (let i = 0; i < 6000 && (sim.state === 'fly' || sim.state === 'roll'); i++) {
      sim.step(1 / 60);
      pts.push({ x: sim.pos.x, z: sim.pos.z });
    }
    if (isNaN(sim.pos.x) || isNaN(sim.pos.y)) { print("  !!! NaN position"); failures++; break; }
    const endRem = Math.hypot(sim.pos.x - pin.x, sim.pos.z - pin.z);
    if (sim.state === 'holed') holed = true;
    else if (sim.state === 'water') {
      strokes++;
      // take the real in-game drop and play on from it
      const drop = findDropPoint(course, pts, pos);
      const dh = course.heightAt(drop.x, drop.z);
      const dm = course.waterMask(drop.x, drop.z).m;
      if (course.surfaceAt(drop.x, drop.z) === 'water' || (dm >= 0.02 && dh <= course.waterLevel + 0.2)) {
        print("  !!! wet in-round drop on hole " + hole.id);
        failures++;
      }
      pos = { x: drop.x, y: dh + 0.0214, z: drop.z };
      lie = course.surfaceAt(pos.x, pos.z);
      print("  shot " + shot + " " + c.name + " pw" + power.toFixed(2) + " -> WATER (+1, drop to " + lie + ")");
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
print("ROUND: " + totalStrokes + " strokes, par " + totalPar +
      " (" + (totalStrokes - totalPar >= 0 ? "+" : "") + (totalStrokes - totalPar) + ")" +
      (failures ? "  FAILURES: " + failures : "  all checks OK"));
