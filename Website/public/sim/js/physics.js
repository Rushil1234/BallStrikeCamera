// Ball physics: aerodynamic flight (drag + Magnus lift), surface-aware
// bounce, and a unified roll/putt integrator with cup capture.
// No three.js dependency — runs in Node for tuning and testing.

export const SURF = {
  TEE: 'tee', FAIRWAY: 'fairway', FRINGE: 'fringe', ROUGH: 'rough',
  SAND: 'sand', GREEN: 'green', WATER: 'water',
};

// restitution: vertical energy kept on bounce
// retain: tangential velocity kept on bounce
// decel: rolling deceleration, m/s^2 (green ~ stimp 10)
export const SURF_PROPS = {
  tee:     { restitution: 0.38, retain: 0.58, decel: 2.0 },
  fairway: { restitution: 0.36, retain: 0.58, decel: 1.7 },
  fringe:  { restitution: 0.30, retain: 0.50, decel: 2.6 },
  rough:   { restitution: 0.20, retain: 0.36, decel: 5.0 },
  sand:    { restitution: 0.03, retain: 0.08, decel: 12.0 },
  green:   { restitution: 0.40, retain: 0.62, decel: 0.72 },
  water:   { restitution: 0.0,  retain: 0.0,  decel: 99 },
};

const G = 9.81;
const BALL_R = 0.0214;          // regulation ball radius, m
const AERO = 0.0192;            // 0.5 * rho * A / m for a golf ball
const CL_SLOPE = 2.2;           // lift coeff vs spin ratio, saturating
const CL_MAX = 0.32;
const CD_BASE = 0.255;          // drag coeff + lift-induced component
const SPIN_DECAY = 10;          // spin decay time constant, s
const CUP_R = 0.108 / 2;        // regulation cup
const CAPTURE_SPEED = 1.65;     // max speed the cup will swallow, m/s

const RPM_TO_RAD = Math.PI * 2 / 60;

// --- tiny vector helpers (plain objects, y up) ---
const v3 = (x = 0, y = 0, z = 0) => ({ x, y, z });
const add = (a, b) => v3(a.x + b.x, a.y + b.y, a.z + b.z);
const sub = (a, b) => v3(a.x - b.x, a.y - b.y, a.z - b.z);
const scl = (a, s) => v3(a.x * s, a.y * s, a.z * s);
const dot = (a, b) => a.x * b.x + a.y * b.y + a.z * b.z;
const len = (a) => Math.hypot(a.x, a.y, a.z);
const cross = (a, b) => v3(
  a.y * b.z - a.z * b.y,
  a.z * b.x - a.x * b.z,
  a.x * b.y - a.y * b.x,
);
const norm = (a) => { const l = len(a) || 1; return scl(a, 1 / l); };

/**
 * Create a ball simulation.
 * opts:
 *   pos {x,y,z}            start position (y = ground + ball radius)
 *   dir {x,z}              horizontal unit aim direction
 *   speed                  m/s
 *   launchDeg              vertical launch angle
 *   backspinRpm            backspin (positive = lift)
 *   sidespinRpm            signed; positive = fade/right, negative = draw/left (for RH golfer)
 *   wind {x,z}             m/s
 *   course { heightAt(x,z), surfaceAt(x,z), normalAt(x,z), waterLevel }
 *   pin {x,z}              cup location (capture enabled when provided)
 *   mode                   'fly' | 'roll'  (putts start in 'roll')
 *
 * Returned sim: { pos, vel, state, events[], carryPos, step(dt) }
 * state: 'fly' | 'roll' | 'rest' | 'holed' | 'water'
 * events pushed during step(): {type:'bounce'|'land'|'splash'|'holed'|'lip', ...}
 */
export function createShot(opts) {
  const { course, wind = { x: 0, z: 0 }, pin = null } = opts;
  const dir3 = norm(v3(opts.dir.x, 0, opts.dir.z));
  const la = (opts.launchDeg || 0) * Math.PI / 180;

  const sim = {
    pos: v3(opts.pos.x, opts.pos.y, opts.pos.z),
    vel: add(scl(dir3, opts.speed * Math.cos(la)), v3(0, opts.speed * Math.sin(la), 0)),
    state: opts.mode === 'roll' ? 'roll' : 'fly',
    events: [],
    carryPos: null,
    bounces: 0,
    age: 0,
  };

  // spin vector: backspin about the axis perpendicular to flight,
  // sidespin about vertical. omega in rad/s.
  const backAxis = norm(cross(dir3, v3(0, 1, 0)));   // gives upward magnus
  let omega = add(
    scl(backAxis, (opts.backspinRpm || 0) * RPM_TO_RAD),
    v3(0, (opts.sidespinRpm || 0) * RPM_TO_RAD, 0),
  );

  const windV = v3(wind.x, 0, wind.z);
  const SUB = 1 / 240;

  function groundNormal(x, z) {
    return course.normalAt(x, z);
  }

  function tryCup(speed) {
    if (!pin) return false;
    const d = Math.hypot(sim.pos.x - pin.x, sim.pos.z - pin.z);
    if (d < CUP_R + 0.03) {
      if (speed <= CAPTURE_SPEED) {
        sim.state = 'holed';
        sim.pos.x = pin.x; sim.pos.z = pin.z;
        sim.pos.y = course.heightAt(pin.x, pin.z) - 0.05;
        sim.events.push({ type: 'holed' });
        return true;
      }
      // lip out: deflect sideways, shed speed
      const out = norm(v3(sim.pos.x - pin.x, 0, sim.pos.z - pin.z));
      const tang = v3(-out.z, 0, out.x);
      sim.vel = add(scl(out, speed * 0.45), scl(tang, speed * 0.4));
      sim.events.push({ type: 'lip' });
    }
    return false;
  }

  function enterWater() {
    sim.state = 'water';
    sim.pos.y = (course.waterLevel ?? 0) + 0.0;
    sim.vel = v3();
    sim.events.push({ type: 'splash', pos: { ...sim.pos } });
  }

  function stepFly(dt) {
    const vrel = sub(sim.vel, windV);
    const vmag = len(vrel);
    let acc = v3(0, -G, 0);
    if (vmag > 0.01) {
      const spinRate = len(omega);
      const S = spinRate * BALL_R / vmag;                  // spin ratio
      const cl = Math.min(CL_MAX, CL_SLOPE * S);
      // drag crisis: dimpled ball drops Cd at high speed
      const hi = Math.min(Math.max((vmag - 30) / 25, 0), 1);
      const cd = CD_BASE - 0.055 * hi + 0.30 * cl;
      acc = add(acc, scl(vrel, -AERO * cd * vmag));        // drag
      if (spinRate > 1) {
        const liftDir = norm(cross(scl(omega, 1 / spinRate), scl(vrel, 1 / vmag)));
        acc = add(acc, scl(liftDir, AERO * cl * vmag * vmag));
      }
    }
    sim.vel = add(sim.vel, scl(acc, dt));
    sim.pos = add(sim.pos, scl(sim.vel, dt));
    omega = scl(omega, Math.exp(-dt / SPIN_DECAY));

    // catch ball at the visual water surface before it sinks to the carved bed
    if (course.waterLevel > -90 && sim.pos.y - BALL_R <= course.waterLevel) {
      if (course.surfaceAt(sim.pos.x, sim.pos.z) === SURF.WATER) {
        enterWater(); return;
      }
    }

    // tree canopy + trunk collision
    if (course.trees?.length && sim.pos.y < 22) {
      for (const tree of course.trees) {
        const hdx = Math.abs(sim.pos.x - tree.x);
        const hdz = Math.abs(sim.pos.z - tree.z);
        const maxR = 5.0 * tree.s;
        if (hdx > maxR || hdz > maxR) continue;
        // canopy sphere
        const canopyCY = tree.h + (tree.isPine ? 6.0 : 5.2) * tree.s;
        const canopyR = 3.5 * tree.s;
        const dx = sim.pos.x - tree.x, dy = sim.pos.y - canopyCY, dz = sim.pos.z - tree.z;
        const dist2 = dx * dx + dy * dy + dz * dz;
        if (dist2 < canopyR * canopyR) {
          const dist = Math.sqrt(dist2) || 0.01;
          const nx = dx / dist, ny = dy / dist, nz = dz / dist;
          const pen = canopyR - dist + 0.02;
          sim.pos.x += nx * pen; sim.pos.y += ny * pen; sim.pos.z += nz * pen;
          const vn = sim.vel.x * nx + sim.vel.y * ny + sim.vel.z * nz;
          sim.vel.x -= 1.28 * vn * nx; sim.vel.y -= 1.28 * vn * ny; sim.vel.z -= 1.28 * vn * nz;
          sim.vel.x *= 0.52; sim.vel.y *= 0.52; sim.vel.z *= 0.52;
          sim.vel.x += (Math.random() - 0.5) * 1.8;
          sim.vel.z += (Math.random() - 0.5) * 1.8;
          sim.events.push({ type: 'tree', pos: { ...sim.pos } });
          break;
        }
        // trunk cylinder
        const trunkH = (tree.isPine ? 8.6 : 4.8) * tree.s;
        const trunkR = (tree.isPine ? 0.30 : 0.36) * tree.s;
        const hd = Math.hypot(sim.pos.x - tree.x, sim.pos.z - tree.z);
        if (hd < trunkR + BALL_R && sim.pos.y > tree.h + 0.1 && sim.pos.y < tree.h + trunkH) {
          sim.vel.x *= 0.06; sim.vel.z *= 0.06;
          sim.events.push({ type: 'tree', pos: { ...sim.pos } });
          break;
        }
      }
    }

    const h = course.heightAt(sim.pos.x, sim.pos.z);
    if (sim.pos.y <= h + BALL_R) {
      sim.pos.y = h + BALL_R;
      const surf = course.surfaceAt(sim.pos.x, sim.pos.z);

      if (!sim.carryPos) {
        sim.carryPos = { ...sim.pos };
        sim.events.push({ type: 'land', pos: { ...sim.pos }, surface: surf });
      }
      if (surf === SURF.WATER) { enterWater(); return; }

      const props = SURF_PROPS[surf] || SURF_PROPS.rough;
      const n = groundNormal(sim.pos.x, sim.pos.z);
      const vn = dot(sim.vel, n);
      if (vn < 0) {
        sim.bounces++;
        const impact = -vn;
        let vnOut = impact * props.restitution;
        // firm landings don't rebound proportionally — cap it
        vnOut = Math.min(vnOut, 4.2);

        let vt = sub(sim.vel, scl(n, vn));
        vt = scl(vt, props.retain);

        // backspin bite: on greens/fringe a spinny wedge checks up or sucks back
        const backRpm = dot(omega, backAxis) / RPM_TO_RAD;
        if ((surf === SURF.GREEN || surf === SURF.FRINGE || surf === SURF.FAIRWAY) && backRpm > 3500) {
          const biteScale = surf === SURF.GREEN ? 1.0 : 0.45;
          const bite = Math.min((backRpm - 3500) / 6500, 1) * 3.0 * biteScale;
          const fwd = norm(v3(vt.x, 0, vt.z));
          vt = add(vt, scl(fwd, -bite));
        }

        sim.events.push({ type: 'bounce', speed: impact, surface: surf, pos: { ...sim.pos } });
        omega = scl(omega, 0.62);

        // plugged in soft sand
        if (surf === SURF.SAND && impact > 5) {
          sim.vel = v3();
          sim.state = 'roll';
          return;
        }

        if (vnOut < 0.55) {
          // transition to rolling
          sim.vel = v3(vt.x, 0, vt.z);
          sim.state = 'roll';
          if (len(sim.vel) < 0.2) restCheck();
        } else {
          sim.vel = add(vt, scl(n, vnOut));
          sim.pos.y = h + BALL_R + 0.001;
        }
      }
    }
  }

  function restCheck() {
    sim.vel = v3();
    sim.state = 'rest';
    sim.events.push({ type: 'rest', pos: { ...sim.pos } });
  }

  function stepRoll(dt) {
    const { x, z } = sim.pos;
    const surf = course.surfaceAt(x, z);
    if (surf === SURF.WATER) { enterWater(); return; }
    const props = SURF_PROPS[surf] || SURF_PROPS.rough;

    // slope acceleration from the height gradient
    const e = 0.35;
    const gx = (course.heightAt(x + e, z) - course.heightAt(x - e, z)) / (2 * e);
    const gz = (course.heightAt(x, z + e) - course.heightAt(x, z - e)) / (2 * e);
    const slope = v3(-gx * G, 0, -gz * G);

    const speed = Math.hypot(sim.vel.x, sim.vel.z);
    if (speed > 1e-4) {
      const fwd = v3(sim.vel.x / speed, 0, sim.vel.z / speed);
      const dec = Math.min(props.decel, speed / dt); // don't reverse via friction
      sim.vel = add(sim.vel, scl(fwd, -dec * dt));
    }
    sim.vel = add(sim.vel, scl(slope, dt));
    sim.vel.y = 0;

    sim.pos.x += sim.vel.x * dt;
    sim.pos.z += sim.vel.z * dt;
    sim.pos.y = course.heightAt(sim.pos.x, sim.pos.z) + BALL_R;

    const sp = Math.hypot(sim.vel.x, sim.vel.z);
    if (tryCup(sp)) return;

    const slopeMag = Math.hypot(gx, gz);
    if (sp < 0.18 && (slopeMag < 0.045 || surf !== SURF.GREEN)) restCheck();
    if (sp < 0.04) restCheck();
  }

  sim.step = function step(frameDt) {
    if (sim.state === 'rest' || sim.state === 'holed' || sim.state === 'water') return;
    let remaining = Math.min(frameDt, 0.1);
    while (remaining > 0 && (sim.state === 'fly' || sim.state === 'roll')) {
      const dt = Math.min(SUB, remaining);
      if (sim.state === 'fly') stepFly(dt); else stepRoll(dt);
      remaining -= dt;
      sim.age += dt;
      if (sim.age > 30) { restCheck(); break; }
    }
  };

  return sim;
}

/**
 * Flat-ground carry/total for a club at full power. Used to label the bag
 * and to draw aim guides. Returns meters: { carry, total, apex, time }.
 */
export function simulateCarry(speed, launchDeg, backspinRpm, wind = { x: 0, z: 0 }) {
  const flat = {
    heightAt: () => 0,
    surfaceAt: () => SURF.FAIRWAY,
    normalAt: () => ({ x: 0, y: 1, z: 0 }),
    waterLevel: -10,
  };
  const sim = createShot({
    pos: { x: 0, y: BALL_R, z: 0 },
    dir: { x: 0, z: 1 },
    speed, launchDeg, backspinRpm,
    sidespinRpm: 0, wind, course: flat,
  });
  let apex = 0, carry = 0, time = 0;
  for (let i = 0; i < 60 * 40 && sim.state !== 'rest'; i++) {
    sim.step(1 / 60);
    time += 1 / 60;
    apex = Math.max(apex, sim.pos.y);
    if (sim.carryPos && !carry) carry = Math.hypot(sim.carryPos.x, sim.carryPos.z);
  }
  const total = Math.hypot(sim.pos.x, sim.pos.z);
  return { carry, total, apex, time };
}

export { BALL_R, CUP_R };
