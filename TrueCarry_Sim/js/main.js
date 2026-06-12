// GSPro Web — game orchestration: scene, state machine, swing meter,
// cameras, shot lifecycle, scoring.

import * as THREE from 'three';
import { CLUBS, LIE_EFFECT, fmtYards } from './clubs.js';
import { createShot, simulateCarry, SURF } from './physics.js';
import { HOLES, RANGE, holeLength } from './holes.js';
import { buildCourse } from './terrain.js';
import { makeSky } from './sky.js';
import { loadAssets } from './assets.js';
import { HUD, toParStr } from './ui.js';
import { SFX } from './audio.js';
import { getLiveCode, connectLive } from './live.js';
import { fetchSimCourses } from './courses.js';

// ---------- boot ----------

const hud = new HUD();

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
renderer.domElement.classList.add('gl');
document.getElementById('app').prepend(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(58, window.innerWidth / window.innerHeight, 0.1, 6000);

// real-world assets (PBR ground, HDRI sky, tree cards) load while the
// title screen is up; TEE OFF enables when ready
let sky = null;
let assets = null;
hud.el.btnStart.textContent = 'LOADING…';
hud.el.btnStart.disabled = true;
const assetsReady = loadAssets(renderer).then((a) => {
  assets = a;
  sky = makeSky(scene, renderer, assets);
  hud.el.btnStart.textContent = 'TEE OFF';
  hud.el.btnStart.disabled = false;
  return a;
}).catch((err) => {
  hud.el.btnStart.textContent = 'LOAD FAILED — RETRY';
  hud.el.btnStart.disabled = false;
  console.error('asset load failed', err);
  throw err;
});

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

// precompute realistic carry numbers for the bag
for (const c of CLUBS) {
  if (c.putter) { c.carryM = 0; continue; }
  const r = simulateCarry(c.speed, c.launch, c.spin);
  c.carryM = r.carry;
  c.totalM = r.total;
}

// ---------- persistent scene objects ----------

const ball = new THREE.Mesh(
  new THREE.SphereGeometry(0.034, 18, 14),
  new THREE.MeshPhongMaterial({ color: 0xfdfdf6, specular: 0x999999, shininess: 60 }),
);
ball.castShadow = true;
scene.add(ball);

// soft blob shadow (cheaper + steadier than real shadow for a tiny ball)
const blobTex = (() => {
  const cv = document.createElement('canvas');
  cv.width = cv.height = 64;
  const c = cv.getContext('2d');
  const g = c.createRadialGradient(32, 32, 2, 32, 32, 30);
  g.addColorStop(0, 'rgba(0,0,0,0.55)');
  g.addColorStop(1, 'rgba(0,0,0,0)');
  c.fillStyle = g;
  c.fillRect(0, 0, 64, 64);
  return new THREE.CanvasTexture(cv);
})();
const blob = new THREE.Mesh(
  new THREE.PlaneGeometry(1, 1),
  new THREE.MeshBasicMaterial({ map: blobTex, transparent: true, depthWrite: false }),
);
blob.rotation.x = -Math.PI / 2;
scene.add(blob);

// shot tracer
const TRACER_MAX = 2400;
const tracerPos = new Float32Array(TRACER_MAX * 3);
const tracerGeo = new THREE.BufferGeometry();
tracerGeo.setAttribute('position', new THREE.BufferAttribute(tracerPos, 3));
tracerGeo.setDrawRange(0, 0);
const tracer = new THREE.Line(
  tracerGeo,
  new THREE.LineBasicMaterial({ color: 0xecd9ad, transparent: true, opacity: 0.85 }),
);
tracer.frustumCulled = false;
scene.add(tracer);
let tracerCount = 0;

// aim guide: dashed line + landing ring
const aimGeo = new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(), new THREE.Vector3()]);
const aimLine = new THREE.Line(
  aimGeo,
  new THREE.LineDashedMaterial({ color: 0xecd9ad, dashSize: 1.6, gapSize: 1.2, transparent: true, opacity: 0.6 }),
);
aimLine.frustumCulled = false;
scene.add(aimLine);

const ring = new THREE.Mesh(
  new THREE.TorusGeometry(1.5, 0.14, 10, 36),
  new THREE.MeshBasicMaterial({ color: 0xc9a86a, transparent: true, opacity: 0.85 }),
);
ring.rotation.x = -Math.PI / 2;
scene.add(ring);

// ---------- game state ----------

const game = {
  state: 'TITLE',           // TITLE FLYOVER AIM METER_POWER METER_ACCURACY FLIGHT HOLE_DONE ROUND_DONE
  holeIdx: 0,
  course: null,
  scores: HOLES.map(() => null),
  strokes: 0,
  ballPos: { x: 0, y: 0, z: 0 },
  lie: SURF.TEE,
  aimDir: { x: 0, z: 1 },
  clubIdx: 0,
  wind: { x: 0, z: 0, speed: 0 },
  sim: null,
  shotStart: null,
  meter: { cursor: 0, dirUp: true, power: 0 },
  flyT: 0,
  doneTimer: 0,
  greenCamSet: false,
  camLook: new THREE.Vector3(0, 0, 50),
  time: 0,
  isRange: false,
};

let rangeMarkers = null;

const club = () => CLUBS[game.clubIdx];
const onGreen = () => game.lie === SURF.GREEN;

function distToPin() {
  const p = game.course.pinPos;
  return Math.hypot(game.ballPos.x - p.x, game.ballPos.z - p.z);
}

function totalToPar() {
  let d = 0;
  HOLES.forEach((h, i) => { if (game.scores[i] != null) d += game.scores[i] - h.par; });
  return d;
}

// ---------- hole / shot setup ----------

function startHole(idx) {
  if (rangeMarkers) { rangeMarkers.forEach(m => scene.remove(m)); rangeMarkers = null; }
  game.isRange = false;
  if (idx === 0) game.scores = HOLES.map(() => null);
  if (game.course) {
    scene.remove(game.course.group);
    game.course.dispose();
  }
  game.holeIdx = idx;
  const def = HOLES[idx];
  game.course = buildCourse(def, assets);
  scene.add(game.course.group);

  game.strokes = 0;
  hud.shotDataHide();
  const t = game.course.teePos;
  game.ballPos = { x: t.x, y: t.y + 0.0214, z: t.z };
  game.lie = SURF.TEE;

  // wind
  const ang = Math.random() * Math.PI * 2;
  const spd = Math.random() * def.windMax;
  game.wind = { x: Math.sin(ang) * spd, z: Math.cos(ang) * spd, speed: spd };

  tracerCount = 0;
  tracerGeo.setDrawRange(0, 0);

  const yds = fmtYards(holeLength(def));
  hud.setHole(def.id, def.par, yds, def.name);
  hud.setStroke(1, totalToPar());
  hud.mapSetHole(def);
  hud.show();

  // flyover
  game.state = 'FLYOVER';
  game.flyT = 0;
  hud.introShow(def.id, def.name, def.par, yds);
  ball.visible = false;
  blob.visible = false;
  setGuides(false);
}

function suggestClub() {
  if (onGreen()) return CLUBS.length - 1;
  const remaining = distToPin();
  let best = 0, bestDiff = Infinity;
  for (let i = 0; i < CLUBS.length - 1; i++) {
    const d = Math.abs(CLUBS[i].carryM - remaining);
    if (d < bestDiff) { bestDiff = d; best = i; }
  }
  // inside shortest full carry: take the wedge (partial swing), not a long club
  if (remaining < CLUBS[CLUBS.length - 2].carryM) best = CLUBS.length - 2;
  if (game.lie === SURF.SAND) best = Math.max(best, CLUBS.length - 3); // sand → wedges
  return best;
}

function setupShot() {
  game.state = 'AIM';
  game.greenCamSet = false;
  ball.visible = true;
  blob.visible = true;
  ball.position.set(game.ballPos.x, game.ballPos.y, game.ballPos.z);

  game.clubIdx = suggestClub();

  // default aim: at the pin if reachable, else down the playing line
  const pin = game.course.pinPos;
  const rem = distToPin();
  if (onGreen() || rem <= club().carryM * 1.12 || club().putter) {
    aimAt(pin.x, pin.z);
  } else {
    const info = game.course.pathInfo(game.ballPos.x, game.ballPos.z);
    const tgt = game.course.pointAtAlong(info.along + Math.min(club().carryM, info.total - info.along));
    aimAt(tgt.x, tgt.z);
  }

  hud.setStroke(game.strokes + 1, totalToPar());
  hud.setPin(rem);
  hud.setLie(game.lie);
  refreshClubHud();
  hud.meterHide();
  setGuides(true);
  updateGuides();
}

function aimAt(x, z) {
  const dx = x - game.ballPos.x, dz = z - game.ballPos.z;
  const L = Math.hypot(dx, dz) || 1;
  game.aimDir = { x: dx / L, z: dz / L };
}

function refreshClubHud() {
  hud.setClub(club().name, club().carryM, !!club().putter);
  const rel = Math.atan2(game.wind.x, game.wind.z) - Math.atan2(game.aimDir.x, game.aimDir.z);
  hud.setWind(game.wind.speed * 2.237, rel);
}

function setGuides(v) {
  aimLine.visible = v;
  ring.visible = v;
}

function guideDistance(powerFrac = 1) {
  if (club().putter) {
    const v = club().speed * Math.max(powerFrac, 0.05);
    return Math.min(v * v / (2 * 0.72), 80);
  }
  return club().carryM * LIE_EFFECT[game.lie].speed * Math.pow(0.3 + 0.7 * powerFrac, 1.8);
}

function updateGuides(powerFrac = 1) {
  const d = guideDistance(powerFrac);
  const gx = game.ballPos.x + game.aimDir.x * d;
  const gz = game.ballPos.z + game.aimDir.z * d;
  const gy = game.course.heightAt(gx, gz);
  ring.position.set(gx, gy + 0.08, gz);
  const s = club().putter ? 0.35 : 1;
  ring.userData.baseScale = s;
  ring.scale.set(s, s, s);

  aimGeo.setFromPoints([
    new THREE.Vector3(game.ballPos.x, game.ballPos.y + 0.05, game.ballPos.z),
    new THREE.Vector3(gx, gy + 0.1, gz),
  ]);
  aimLine.computeLineDistances();
}

// ---------- swing ----------

function beginMeter() {
  game.state = 'METER_POWER';
  game.meter = { cursor: 0, dirUp: true, power: 0 };
  hud.meterShow();
  SFX.tick();
}

function setPower() {
  game.meter.power = game.meter.cursor;
  game.state = 'METER_ACCURACY';
  SFX.tick();
}

const SNAP = 0.12;

function fire(accuracyRaw) {
  // accuracyRaw: meter cursor at the moment of the strike click
  const acc = Math.max(-1, Math.min(1, (accuracyRaw - SNAP) / 0.45));
  const c = club();
  const lie = LIE_EFFECT[game.lie] || LIE_EFFECT.fairway;
  const power = Math.max(game.meter.power, 0.05);

  game.strokes += 1;
  hud.setStroke(game.strokes, totalToPar());
  hud.meterHide();
  hud.toastHide();

  const right = { x: -game.aimDir.z, z: game.aimDir.x };
  const pushRad = acc * 4.5 * Math.PI / 180 * (c.putter ? 0.35 : 1);
  const ca = Math.cos(pushRad), sa = Math.sin(pushRad);
  const dir = {
    x: game.aimDir.x * ca + right.x * sa,
    z: game.aimDir.z * ca + right.z * sa,
  };

  const jitter = 1 + (Math.random() - 0.5) * 2 * lie.jitter;
  const speed = c.putter
    ? c.speed * power * (game.lie === SURF.GREEN || game.lie === SURF.FRINGE ? 1 : 0.55)
    : c.speed * (0.3 + 0.7 * power) * lie.speed * jitter;
  const launchDeg = c.putter ? 0 : c.launch + (game.lie === SURF.ROUGH ? 1.5 : 0);
  const backspinRpm = c.putter ? 0 : c.spin * lie.spin * (0.55 + 0.45 * power);

  if (c.putter) {
    hud.shotDataHide();
  } else {
    hud.shotDataShow({ speedMph: speed * 2.237, launchDeg, spinRpm: backspinRpm });
  }
  game.shotApex = 0;
  game.shotGroundY = game.course.heightAt(game.ballPos.x, game.ballPos.z);

  game.sim = createShot({
    pos: { ...game.ballPos },
    dir,
    speed,
    launchDeg,
    backspinRpm,
    sidespinRpm: c.putter ? 0 : -acc * 2100,
    wind: game.wind,
    course: game.course,
    pin: { x: game.course.pinPos.x, z: game.course.pinPos.z },
    mode: c.putter ? 'roll' : 'fly',
  });

  game.shotStart = { ...game.ballPos };
  tracerCount = 0;
  tracerGeo.setDrawRange(0, 0);
  game.state = 'FLIGHT';
  setGuides(false);
  SFX.strike(power, !!c.putter);
}

// ---------- shot resolution ----------

function scoreName(strokes, par) {
  if (strokes === 1) return 'ACE!';
  const d = strokes - par;
  if (d <= -3) return 'ALBATROSS!';
  if (d === -2) return 'EAGLE!';
  if (d === -1) return 'BIRDIE';
  if (d === 0) return 'PAR';
  if (d === 1) return 'BOGEY';
  if (d === 2) return 'DOUBLE BOGEY';
  return `+${d}`;
}

function resolveShot() {
  const sim = game.sim;
  game.ballPos = { x: sim.pos.x, y: sim.pos.y, z: sim.pos.z };

  // Range mode: show carry/total, reset to tee, no scoring
  if (game.isRange) {
    const finalLie = sim.state === 'water' ? SURF.WATER
      : game.course.surfaceAt(sim.pos.x, sim.pos.z);
    const carry = sim.carryPos
      ? Math.hypot(sim.carryPos.x - game.shotStart.x, sim.carryPos.z - game.shotStart.z) : 0;
    const total = Math.hypot(sim.pos.x - game.shotStart.x, sim.pos.z - game.shotStart.z);
    if (!club().putter) hud.shotDataResult(fmtYards(carry), fmtYards(total));
    hud.toast(
      `<span class="t-gold">${fmtYards(carry)}y</span> CARRY · ${fmtYards(total)}y TOTAL` +
      `<span class="t-sub">RANGE · ${finalLie === SURF.WATER ? 'INTO WATER' : finalLie.toUpperCase()}</span>`,
      3500);
    const t = game.course.teePos;
    game.ballPos = { x: t.x, y: t.y + 0.0214, z: t.z };
    game.lie = SURF.TEE;
    game.shotStart = { ...game.ballPos };
    tracerCount = 0;
    tracerGeo.setDrawRange(0, 0);
    ball.visible = true;
    setupShot();
    return;
  }

  if (sim.state === 'holed') {
    const def = HOLES[game.holeIdx];
    game.scores[game.holeIdx] = game.strokes;
    hud.toast(
      `<span class="t-gold">${scoreName(game.strokes, def.par)}</span>` +
      `<span class="t-sub">HOLE ${def.id} · ${game.strokes} STROKES</span>`, 0);
    game.state = 'HOLE_DONE';
    game.doneTimer = 0;
    return;
  }

  if (sim.state === 'water') {
    game.strokes += 1; // penalty
    // drop at the last dry point along the flight
    let drop = game.shotStart;
    for (let i = tracerCount - 1; i >= 0; i--) {
      const x = tracerPos[i * 3], z = tracerPos[i * 3 + 2];
      if (game.course.surfaceAt(x, z) !== SURF.WATER) {
        // nudge back toward the shot origin, out of the hazard line
        const bx = game.shotStart.x - x, bz = game.shotStart.z - z;
        const L = Math.hypot(bx, bz) || 1;
        const dx = x + (bx / L) * 3, dz = z + (bz / L) * 3;
        if (game.course.surfaceAt(dx, dz) !== SURF.WATER) { drop = { x: dx, z: dz }; break; }
      }
    }
    game.ballPos = { x: drop.x, y: game.course.heightAt(drop.x, drop.z) + 0.0214, z: drop.z };
    game.lie = game.course.surfaceAt(drop.x, drop.z);
    hud.toast(`<span class="t-gold">WATER</span><span class="t-sub">+1 PENALTY · DROP</span>`, 2600);
    setupShot();
    return;
  }

  // out of bounds: stroke and distance — +1 and replay from the same spot
  if (game.course.isOB(game.ballPos.x, game.ballPos.z)) {
    game.strokes += 1;
    game.ballPos = { ...game.shotStart };
    game.lie = game.course.surfaceAt(game.ballPos.x, game.ballPos.z);
    hud.toast('<span class="t-gold">OUT OF BOUNDS</span><span class="t-sub">+1 PENALTY · REPLAY FROM ORIGINAL SPOT</span>', 3000);
    setupShot();
    return;
  }

  // normal rest
  game.lie = game.course.surfaceAt(game.ballPos.x, game.ballPos.z);
  const carry = sim.carryPos
    ? Math.hypot(sim.carryPos.x - game.shotStart.x, sim.carryPos.z - game.shotStart.z) : 0;
  const total = Math.hypot(game.ballPos.x - game.shotStart.x, game.ballPos.z - game.shotStart.z);

  if (!club().putter) hud.shotDataResult(fmtYards(carry), fmtYards(total));

  if (!club().putter && total > 15) {
    hud.toast(
      `<span class="t-gold">${fmtYards(carry)}y</span> CARRY · ${fmtYards(total)}y TOTAL` +
      `<span class="t-sub">${game.lie.toUpperCase()}</span>`, 2800);
  }
  setupShot();
}

function nextHole() {
  hud.toastHide();
  if (game.holeIdx + 1 < HOLES.length) {
    startHole(game.holeIdx + 1);
  } else {
    game.state = 'ROUND_DONE';
    hud.summaryShow(HOLES, game.scores);
  }
}

function startRange() {
  if (rangeMarkers) { rangeMarkers.forEach(m => scene.remove(m)); rangeMarkers = null; }
  game.isRange = true;
  if (game.course) { scene.remove(game.course.group); game.course.dispose(); }
  game.course = buildCourse(RANGE, assets);
  scene.add(game.course.group);
  game.holeIdx = 0;
  game.scores = [null];
  game.strokes = 0;
  hud.shotDataHide();
  const t = game.course.teePos;
  game.ballPos = { x: t.x, y: t.y + 0.0214, z: t.z };
  game.lie = SURF.TEE;
  const ang = Math.random() * Math.PI * 2;
  const spd = Math.random() * RANGE.windMax;
  game.wind = { x: Math.sin(ang) * spd, z: Math.cos(ang) * spd, speed: spd };
  tracerCount = 0;
  tracerGeo.setDrawRange(0, 0);
  hud.mapSetHole(RANGE);
  hud.show();
  // override hole card for range
  const hcHole = document.getElementById('hc-hole');
  const hcPar  = document.getElementById('hc-par');
  const hcYds  = document.getElementById('hc-yds');
  const hcName = document.getElementById('hc-name');
  if (hcHole) hcHole.textContent = 'RANGE';
  if (hcPar)  hcPar.textContent  = 'PRACTICE';
  if (hcYds)  hcYds.textContent  = '';
  if (hcName) hcName.textContent = 'DRIVING RANGE';
  const helpStrip = document.getElementById('help-strip');
  if (helpStrip && window.__liveMode) {
    helpStrip.textContent = 'RANGE · LIVE MODE — hit shots on your phone · M MUTE';
  }
  const liveWaiting = document.getElementById('live-waiting');
  if (liveWaiting && window.__liveMode) liveWaiting.classList.remove('hidden');
  setupShot();
  buildRangeMarkers();
}

function buildRangeMarkers() {
  rangeMarkers = [];
  const yardages = [50, 100, 150, 200, 250, 300];
  const ox = game.course.teePos.x, oz = game.course.teePos.z;
  for (const yd of yardages) {
    const dist = yd * 0.9144;
    const mz = oz + dist, mx = ox;
    const my = game.course.heightAt(mx, mz) + 0.07;
    const isHundred = yd % 100 === 0;
    const marker = new THREE.Mesh(
      new THREE.TorusGeometry(isHundred ? 4 : 2.5, 0.12, 6, 40),
      new THREE.MeshBasicMaterial({
        color: isHundred ? 0xffd700 : 0xffffff,
        transparent: true, opacity: isHundred ? 0.75 : 0.45,
        depthWrite: false,
      })
    );
    marker.rotation.x = -Math.PI / 2;
    marker.position.set(mx, my, mz);
    scene.add(marker);
    rangeMarkers.push(marker);
  }
}

// ---------- cameras ----------

const camTmp = new THREE.Vector3();

function camSet(px, py, pz, lx, ly, lz, snap = false, posRate = 3.2, lookRate = 5) {
  camTmp.set(px, py, pz);
  if (snap) {
    camera.position.copy(camTmp);
    game.camLook.set(lx, ly, lz);
  } else {
    camera.position.lerp(camTmp, 1 - Math.exp(-posRate * frameDt));
    game.camLook.lerp(new THREE.Vector3(lx, ly, lz), 1 - Math.exp(-lookRate * frameDt));
  }
  camera.lookAt(game.camLook);
}

function aimCamera(snap = false) {
  const d = game.aimDir;
  const putt = onGreen() || club().putter;
  const back = putt ? 4.2 : 9;
  const up = putt ? 1.5 : 3.4;
  const bx = game.ballPos.x, by = game.ballPos.y, bz = game.ballPos.z;
  const px = bx - d.x * back, pz = bz - d.z * back;
  const py = Math.max(game.course.heightAt(px, pz) + 1.0, by + up)
    + Math.sin(game.time * 0.55) * 0.05;                       // idle breathing
  const lookAhead = putt ? 12 : 45;
  const swayA = Math.sin(game.time * 0.33) * 0.5;              // slow gaze drift
  camSet(px, py, pz,
    bx + d.x * lookAhead - d.z * swayA,
    by + (putt ? 0 : 4) + Math.sin(game.time * 0.5) * 0.25,
    bz + d.z * lookAhead + d.x * swayA, snap);
}

function flightCamera() {
  const sim = game.sim;
  const pin = game.course.pinPos;
  const distPin = Math.hypot(sim.pos.x - pin.x, sim.pos.z - pin.z);

  if (!game.greenCamSet && distPin < 42 && sim.state !== 'fly') {
    game.greenCamSet = true;
  }
  if (!game.greenCamSet && distPin < 46 && sim.vel.y < 0 && sim.state === 'fly') {
    game.greenCamSet = true;
  }
  if (game.greenCamSet) {
    // broadcast green-side camera, fixed, tracking the ball
    if (!game.greenCamPos) {
      const ox = sim.pos.x - pin.x, oz = sim.pos.z - pin.z;
      const L = Math.hypot(ox, oz) || 1;
      const gx = pin.x + (ox / L) * 26 + (oz / L) * 9;
      const gz = pin.z + (oz / L) * 26 - (ox / L) * 9;
      game.greenCamPos = new THREE.Vector3(gx, game.course.heightAt(gx, gz) + 7.5, gz);
    }
    camSet(game.greenCamPos.x, game.greenCamPos.y, game.greenCamPos.z,
      sim.pos.x, sim.pos.y, sim.pos.z, false, 6, 6);
    return;
  }

  // chase camera
  const vx = sim.vel.x, vz = sim.vel.z;
  const sp = Math.hypot(vx, vz);
  const dx = sp > 0.5 ? vx / sp : game.aimDir.x;
  const dz = sp > 0.5 ? vz / sp : game.aimDir.z;
  const px = sim.pos.x - dx * 11, pz = sim.pos.z - dz * 11;
  const py = Math.max(sim.pos.y + 3.2, game.course.heightAt(px, pz) + 2.2);
  camSet(px, py, pz, sim.pos.x, sim.pos.y, sim.pos.z, false, 2.6, 8);
}

function flyoverCamera() {
  const def = HOLES[game.holeIdx];
  const pin = game.course.pinPos;
  const tee = game.course.teePos;
  const t = Math.min(game.flyT / 5.2, 1);
  const e = t * t * (3 - 2 * t);

  const dirTee = new THREE.Vector3(tee.x - pin.x, 0, tee.z - pin.z).normalize();
  const midIdx = Math.floor(def.path.length / 2);
  const mid = def.path[midIdx];

  const p0 = new THREE.Vector3(pin.x - dirTee.x * 35, pin.y + 26, pin.z - dirTee.z * 35);
  const p1 = new THREE.Vector3(mid.x + dirTee.x * 10, pin.y + 55, mid.z + dirTee.z * 10);
  const p2 = new THREE.Vector3(tee.x + dirTee.x * 24, tee.y + 13, tee.z + dirTee.z * 24);

  const a = p0.clone().lerp(p1, e);
  const b = p1.clone().lerp(p2, e);
  const pos = a.lerp(b, e);

  const lx = pin.x + (tee.x - pin.x) * e * 0.85;
  const lz = pin.z + (tee.z - pin.z) * e * 0.85;
  camSet(pos.x, pos.y, pos.z, lx, pin.y, lz, game.flyT === 0, 50, 50);

  if (t >= 1) {
    hud.introHide();
    setupShot();
    aimCamera(true);
  }
}

// ---------- input ----------

let keys = {};
let dragInfo = null;

function action() {
  // In live mode, only allow skipping flyover and advancing after a hole.
  if (window.__liveMode) {
    if (game.state === 'FLYOVER') { game.flyT = 99; }
    if (game.state === 'HOLE_DONE' && game.doneTimer > 0.8) { game.doneTimer = 99; }
    return;
  }
  switch (game.state) {
    case 'FLYOVER':
      game.flyT = 99;
      break;
    case 'AIM':
      beginMeter();
      break;
    case 'METER_POWER':
      setPower();
      break;
    case 'METER_ACCURACY':
      fire(game.meter.cursor);
      break;
    case 'HOLE_DONE':
      if (game.doneTimer > 0.8) { game.doneTimer = 99; }
      break;
    default:
      break;
  }
}

renderer.domElement.addEventListener('pointerdown', (e) => {
  SFX.unlock();
  dragInfo = { x: e.clientX, y: e.clientY, moved: 0 };
});
window.addEventListener('pointermove', (e) => {
  if (!dragInfo) return;
  const dx = e.clientX - dragInfo.x;
  dragInfo.moved += Math.abs(dx) + Math.abs(e.clientY - dragInfo.y);
  dragInfo.x = e.clientX; dragInfo.y = e.clientY;
  if (game.state === 'AIM' && Math.abs(dx) > 0) {
    rotateAim(-dx * 0.0032);
  }
});
window.addEventListener('pointerup', () => {
  if (dragInfo && dragInfo.moved < 7) action();
  dragInfo = null;
});

function rotateAim(ang) {
  const { x, z } = game.aimDir;
  const c = Math.cos(ang), s = Math.sin(ang);
  game.aimDir = { x: x * c + z * s, z: -x * s + z * c };
  updateGuides();
  refreshClubHud();
}

function changeClub(delta) {
  if (game.state !== 'AIM') return;
  game.clubIdx = (game.clubIdx + delta + CLUBS.length) % CLUBS.length;
  refreshClubHud();
  updateGuides();
  SFX.tick();
}

window.addEventListener('keydown', (e) => {
  if (e.repeat) {
    if (e.code === 'ArrowLeft' || e.code === 'ArrowRight') keys[e.code] = true;
    return;
  }
  SFX.unlock();
  switch (e.code) {
    case 'Space': e.preventDefault(); action(); break;
    case 'ArrowLeft': keys.ArrowLeft = true; break;
    case 'ArrowRight': keys.ArrowRight = true; break;
    case 'ArrowUp': e.preventDefault(); changeClub(-1); break;
    case 'ArrowDown': e.preventDefault(); changeClub(1); break;
    case 'Tab':
      e.preventDefault();
      hud.scorecardToggle(HOLES, game.scores);
      break;
    case 'KeyM':
      SFX.setMuted(!SFX.isMuted());
      break;
    default: break;
  }
});
window.addEventListener('keyup', (e) => { keys[e.code] = false; });

hud.el.clubPrev.addEventListener('click', (e) => { e.stopPropagation(); changeClub(-1); });
hud.el.clubNext.addEventListener('click', (e) => { e.stopPropagation(); changeClub(1); });
hud.el.btnStart.addEventListener('click', () => {
  if (!assets) return;
  SFX.unlock();
  hud.titleHide();
  startHole(0);
});
hud.el.btnAgain.addEventListener('click', () => {
  SFX.unlock();
  hud.summaryHide();
  game.scores = HOLES.map(() => null);
  startHole(0);
});

// ---------- per-frame update ----------

let frameDt = 1 / 60;
const clock = new THREE.Clock();

function pushTracer(p) {
  if (tracerCount >= TRACER_MAX) return;
  tracerPos[tracerCount * 3] = p.x;
  tracerPos[tracerCount * 3 + 1] = p.y;
  tracerPos[tracerCount * 3 + 2] = p.z;
  tracerCount++;
  tracerGeo.setDrawRange(0, tracerCount);
  tracerGeo.attributes.position.needsUpdate = true;
}

function updateMeter() {
  const m = game.meter;
  const putt = !!club().putter;
  if (game.state === 'METER_POWER') {
    const rate = putt ? 0.72 : 0.95;
    m.cursor += (m.dirUp ? 1 : -1) * rate * frameDt;
    if (m.cursor >= 1) { m.cursor = 1; m.dirUp = false; }
    if (m.cursor <= 0 && !m.dirUp) {
      // backed out — cancel swing
      game.state = 'AIM';
      hud.meterHide();
      return;
    }
    hud.meterUpdate({
      cursor: Math.max(m.cursor, 0), fill: Math.max(m.cursor, 0), powerMark: null,
      text: `${Math.round(m.cursor * 100)}%`,
    });
    updateGuides(Math.max(m.cursor, 0.05));
  } else if (game.state === 'METER_ACCURACY') {
    const rate = putt ? 1.05 : 1.5;
    m.cursor -= rate * frameDt;
    if (m.cursor <= -0.06) { fire(m.cursor); return; }
    hud.meterUpdate({
      cursor: Math.max(m.cursor, 0), fill: m.power, powerMark: m.power,
      text: `${Math.round(m.power * 100)}%`,
    });
  }
}

function updateFlight() {
  const sim = game.sim;
  sim.step(frameDt);

  for (const ev of sim.events.splice(0)) {
    if (ev.type === 'bounce') SFX.bounce(ev.speed);
    else if (ev.type === 'splash') SFX.splash();
    else if (ev.type === 'holed') SFX.holed();
    else if (ev.type === 'lip') hud.toast('<span class="t-gold">LIP OUT</span>', 1400);
    else if (ev.type === 'tree') { SFX.bounce(4); hud.toast('<span class="t-sub">TREE</span>', 1100); }
  }

  ball.position.set(sim.pos.x, sim.pos.y, sim.pos.z);
  pushTracer(sim.pos);
  hud.setPin(Math.hypot(sim.pos.x - game.course.pinPos.x, sim.pos.z - game.course.pinPos.z));

  const alt = sim.pos.y - game.shotGroundY;
  if (alt > game.shotApex) {
    game.shotApex = alt;
    if (!club().putter) hud.shotDataApex(game.shotApex * 3.28084);
  }

  flightCamera();

  if (sim.state === 'rest' || sim.state === 'holed' || sim.state === 'water') {
    game.greenCamPos = null;
    if (sim.state === 'holed') ball.visible = false;
    resolveShot();
  }
}

function frame() {
  requestAnimationFrame(frame);
  frameDt = Math.min(clock.getDelta(), 0.05);
  game.time += frameDt;

  if (game.course) {
    game.course.updateFlag(game.time, game.wind.speed);
    game.course.updateWater(game.time, game.wind);

    switch (game.state) {
      case 'FLYOVER':
        game.flyT += frameDt;
        flyoverCamera();
        break;
      case 'AIM':
        if (keys.ArrowLeft) rotateAim(0.85 * frameDt);
        if (keys.ArrowRight) rotateAim(-0.85 * frameDt);
        aimCamera();
        break;
      case 'METER_POWER':
      case 'METER_ACCURACY':
        updateMeter();
        aimCamera();
        break;
      case 'FLIGHT':
        updateFlight();
        break;
      case 'HOLE_DONE':
        game.doneTimer += frameDt;
        if (game.doneTimer > 3.0) nextHole();
        break;
      default:
        break;
    }

    // aiming guides: ring pulse + green-reading grid while putting
    const aiming = game.state === 'AIM' || game.state.startsWith('METER');
    if (aiming && ring.visible) {
      const ps = (ring.userData.baseScale || 1) * (1 + 0.06 * Math.sin(game.time * 2.6));
      ring.scale.set(ps, ps, ps);
      ring.material.opacity = 0.7 + 0.2 * Math.sin(game.time * 2.6);
    }
    if (game.course.greenGrid) {
      game.course.greenGrid.visible = aiming && !!club().putter;
    }

    // ball + blob shadow
    if (game.state !== 'FLIGHT' && game.state !== 'HOLE_DONE') {
      ball.position.set(game.ballPos.x, game.ballPos.y, game.ballPos.z);
    }
    if (ball.visible) {
      const gh = game.course.heightAt(ball.position.x, ball.position.z);
      const alt = Math.max(ball.position.y - gh, 0);
      blob.position.set(ball.position.x, gh + 0.02, ball.position.z);
      const s = 0.16 + alt * 0.05;
      blob.scale.set(s, s, 1);
      blob.material.opacity = Math.max(0.65 - alt * 0.012, 0.12);
      blob.visible = alt < 45;
    }

    hud.mapDraw(
      game.state === 'FLIGHT' ? game.sim.pos : game.ballPos,
      game.state === 'AIM' || game.state.startsWith('METER') ? game.aimDir : null,
      game.course.pinPos,
    );
  }

  if (sky) sky.update(game.time, camera.position);
  renderer.render(scene, camera);
}

frame();

// ---------- course selector ----------
// Hoist liveCode here so the course-selector guard below can reference it.
const liveCode = getLiveCode();

// Notify parent (course-builder tool) that the sim is ready.
window.parent?.postMessage({ type: 'SIM_READY' }, '*');

// postMessage preview mode: course-builder sends PREVIEW_HOLE with custom holes array.
window.addEventListener('message', (e) => {
  // Play page tells the sim to start (dismiss title screen / begin).
  if (e.data?.type === 'START_SIM') {
    const btn = document.getElementById('btn-start');
    if (btn && game.state === 'TITLE') btn.click();
    return;
  }

  if (e.data?.type === 'START_RANGE') {
    assetsReady.then(() => { hud.titleHide(); startRange(); });
    return;
  }

  if (!e.data || e.data.type !== 'PREVIEW_HOLE') return;
  const { holes, holeIndex = 0 } = e.data;
  if (!holes?.length) return;

  // Inject the custom hole definitions into the game.
  Object.assign(HOLES, holes);
  HOLES.length = holes.length;

  // Reset scores for the new course.
  game.scores = HOLES.map(() => null);

  // If assets aren't ready, wait for them.
  assetsReady.then(() => {
    hud.titleHide();
    startHole(Math.min(holeIndex, HOLES.length - 1));
    // Skip straight to AIM (bypass flyover) in preview mode.
    game.flyT = 99;
  });
});

// Load real courses from Supabase and populate the course selector.
const isPreview = new URLSearchParams(location.search).has('preview');
if (!isPreview && !liveCode) {
  fetchSimCourses().then(courses => {
    if (!courses.length) return;
    const select = document.getElementById('course-select');
    const wrap   = document.getElementById('course-select-wrap');
    if (!select || !wrap) return;
    courses.forEach(c => {
      const opt = document.createElement('option');
      opt.value = c.courseId;
      opt.textContent = c.courseName;
      opt._holes = c.holes;
      select.appendChild(opt);
    });
    wrap.classList.remove('hidden');
    select.addEventListener('change', () => {
      const chosen = courses.find(c => c.courseId === select.value);
      if (!chosen?.holes?.length) return;
      Object.assign(HOLES, chosen.holes);
      HOLES.length = chosen.holes.length;
      game.scores = HOLES.map(() => null);
    });
  });
}

// ---------- live sim mode ----------

if (liveCode) {
  // Live mode: disable 3-click swing; shots arrive via Supabase Realtime.
  // The TEE OFF button still loads the course and begins the flyover;
  // after that the user's phone sends real shots.

  const liveWaiting = document.getElementById('live-waiting');
  const liveStatus  = document.getElementById('live-status');
  const liveShotNum = document.getElementById('live-shot-num');
  const helpStrip   = document.getElementById('help-strip');

  // Patch the help strip text for live mode.
  if (helpStrip) helpStrip.textContent = 'LIVE MODE — hit shots on your phone · TAB CARD · M MUTE';

  // Show waiting overlay once the game leaves TITLE.
  const origTitleHide = hud.titleHide.bind(hud);
  hud.titleHide = function () {
    origTitleHide();
    if (liveWaiting) liveWaiting.classList.remove('hidden');
  };

  // Disable keyboard/pointer swing actions in live mode.
  const origAction = action;          // already defined above
  // eslint-disable-next-line no-global-assign
  window.__liveMode = true;

  const liveClub = document.getElementById('live-club');

  function updateLiveStatus(text, cls) {
    if (!liveStatus) return;
    liveStatus.textContent = text;
    liveStatus.className = 'live-status-badge ' + (cls || '');
    liveStatus.classList.remove('hidden');
  }

  function updateLiveShotNum(n) {
    if (!liveShotNum) return;
    liveShotNum.textContent = `SHOT ${n}`;
    liveShotNum.classList.remove('hidden');
  }

  function updateLiveClub(name) {
    if (!liveClub) return;
    liveClub.textContent = name;
    liveClub.classList.remove('hidden');
  }

  connectLive(liveCode,
    // onShotReceived
    function (metrics) {
      if (liveWaiting) liveWaiting.classList.add('hidden');
      if (game.state === 'AIM' || game.state === 'METER_POWER' || game.state === 'METER_ACCURACY') {
        fireLiveShot(metrics);
        updateLiveShotNum(game.strokes);
      }
    },
    // onStatusChange — only surface errors; don't show "waiting for shot" unsolicited
    function (status) {
      if (status === 'error') {
        updateLiveStatus('Connection error — reload to retry', 'live-error');
      }
      // connecting / connected states are silent; the play page handles the UX
    },
    // onPing — app tapped Connect; tell the parent page to advance to course selector
    function () {
      window.parent?.postMessage({ type: 'APP_CONNECTED' }, '*');
    },
    // onClubChanged — update center badge with current club
    function (clubName) {
      updateLiveClub(clubName);
    }
  );
}

/**
 * Fires a shot using metrics from the phone (live sim mode).
 * Bypasses the 3-click swing meter entirely.
 */
function fireLiveShot({ ballSpeedMph, vlaDegrees, backspinRpm, sidespinRpm, hlaDegrees, hlaDirection }) {
  if (!game.course) return;

  const speed = (ballSpeedMph || 100) * 0.44704; // mph → m/s

  // Adjust aim direction by HLA.
  const hlaRad = (hlaDirection === 'right' ? 1 : -1) * (hlaDegrees || 0) * Math.PI / 180;
  const ca = Math.cos(hlaRad), sa = Math.sin(hlaRad);
  const right = { x: -game.aimDir.z, z: game.aimDir.x };
  const dir = {
    x: game.aimDir.x * ca + right.x * sa,
    z: game.aimDir.z * ca + right.z * sa,
  };

  game.strokes += 1;
  hud.setStroke(game.strokes, totalToPar());
  hud.meterHide();
  hud.toastHide();
  hud.shotDataShow({ speedMph: ballSpeedMph, launchDeg: vlaDegrees || 12, spinRpm: Math.abs(backspinRpm || 4000) });
  game.shotApex = 0;
  game.shotGroundY = game.course.heightAt(game.ballPos.x, game.ballPos.z);

  game.sim = createShot({
    pos: { ...game.ballPos },
    dir,
    speed,
    launchDeg: vlaDegrees || 12,
    backspinRpm: Math.abs(backspinRpm || 4000),
    sidespinRpm: sidespinRpm || 0,
    wind: game.wind,
    course: game.course,
    pin: { x: game.course.pinPos.x, z: game.course.pinPos.z },
    mode: 'fly',
  });

  game.shotStart = { ...game.ballPos };
  tracerCount = 0;
  tracerGeo.setDrawRange(0, 0);
  game.state = 'FLIGHT';
  setGuides(false);
  SFX.strike(0.8, false);
}

// dev hooks: #play skips the title screen, #aim also skips the flyover,
// an optional digit picks the hole (#aim2 = hole 2)
{
  const m = location.hash.match(/^#(play|aim)(\d{1,2})?$/);
  if (m) {
    assetsReady.then(() => {
      hud.titleHide();
      startHole(m[2] ? Math.min(parseInt(m[2], 10) - 1, HOLES.length - 1) : 0);
      if (m[1] === 'aim') { game.flyT = 99; }
    });
  }
}
