// TrueCarry_Course — main game orchestration.
// Loads pinchbrook.json, builds world, manages shot lifecycle for all 18 holes.

import * as THREE from 'three';
import { CLUBS, LIE_EFFECT, fmtYards }          from './clubs.js';
import { SFX }                                   from './audio.js';
import { HUD, toParStr }                         from './hud.js';
import { buildWorld, updateWorld, heightAt, surfaceAt, slopeAt, SURF, SURF_PROPS, holeCameraPos, drawMinimapBase } from './terrain.js';
import { loadAssets }                            from './assets.js';
import { makeSky }                               from './sky.js';
import { createShot, stepFly, playsLike, setWind, SURF as PHYS_SURF } from './physics.js';
import { buildGreenMesh, buildBreakArrows, removeBreakArrows, createPuttingBar } from './green.js';
import { recordPosition, clearTrajectory, hasTrajectory, startReplay, updateReplay, showReplayButton, hideReplayButton, isReplaying, skipReplay } from './replay.js';
import { recordLanding, drawDispersion, getTendency, getDispersion }  from './dispersion.js';
import { getLiveCode, connectLive }              from './live.js';

// ---------- Bootstrap ----------
const hud = new HUD();

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
renderer.domElement.className = 'gl';
document.getElementById('app').prepend(renderer.domElement);

const scene  = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 0.5, 4000);

let sky = null;  // set after assets load

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

// ---------- State ----------
const STATE = { TITLE:'TITLE', INTRO:'INTRO', SETUP:'SETUP', SWING:'SWING',
                FLYING:'FLYING', ROLLING:'ROLLING', RESOLVING:'RESOLVING',
                PUTTING:'PUTTING', RESULT:'RESULT' };

let courseData  = null;
let state       = STATE.TITLE;
let minimapBase = null;  // { toC }
let greenMeshes = [];

const game = {
  holeIdx:  0,
  stroke:   1,
  scores:   Array(18).fill(null),
  ballPos:  { x: 0, y: 0, z: 0 },
  clubIdx:  0,
  lie:      'tee',
  wind:     { speed: 0, dir: 0 },
  isLive:   false,
  liveCode: null,
  carryMeters: 0,
  totalMeters: 0,
};

let sim = null;
let pendingLiveShot = null;

// Meter state
const meter = { phase: 0, pct: 0, dir: 1, snapped: false, snapPct: 0, speed: 0.85 };
const METER_SPEED = 0.85; // fraction per second

// Aim
let aimAngle = 0;  // radians, 0 = toward green

// Putting bar
let puttBar = null;

// Minimap canvas context helper
let _minimapToC = null;

// Ball mesh
const ballGeo = new THREE.SphereGeometry(0.0214, 8, 6);
const ballMat = new THREE.MeshLambertMaterial({ color: 0xffffff });
const ballMesh = new THREE.Mesh(ballGeo, ballMat);
ballMesh.castShadow = true;
scene.add(ballMesh);

// Aim line (arrow pointing toward green)
const aimLineGeo = new THREE.CylinderGeometry(0.05, 0.05, 10, 4);
const aimLineMat = new THREE.MeshLambertMaterial({ color: 0xffff00, transparent: true, opacity: 0.7 });
const aimLine = new THREE.Mesh(aimLineGeo, aimLineMat);
aimLine.visible = false;
scene.add(aimLine);

// ---------- Load course ----------
async function loadCourse() {
  const res = await fetch('./courses/pinchbrook.json');
  if (!res.ok) throw new Error('Failed to load course data');
  return res.json();
}

// ---------- Boot ----------
async function boot() {
  try {
    // Load assets + course data in parallel
    const [assets, data] = await Promise.all([
      loadAssets(renderer),
      loadCourse(),
    ]);
    courseData = data;

    sky = makeSky(scene, renderer, assets);
    buildWorld(courseData, scene, assets);

    // Build all green meshes (undulation)
    for (const hole of courseData.holes) {
      const gm = buildGreenMesh(hole, scene);
      if (gm) greenMeshes.push(gm);
    }

    // Minimap
    const minimapCanvas = document.getElementById('minimap');
    if (minimapCanvas) {
      const result = drawMinimapBase(courseData, minimapCanvas);
      minimapBase = result;
      _minimapToC = result.toC;
    }

    // Putting bar
    puttBar = createPuttingBar(document.getElementById('app'));

    // Live mode
    game.liveCode = getLiveCode();
    if (game.liveCode) {
      game.isLive = true;
      connectLive(
        game.liveCode,
        onLiveShotReceived,
        onLiveStatus,
        onLivePing,
        onLiveClub,
      );
    }

    // Set wind
    const windSpeed = courseData.meta?.windSpeed ?? (Math.random() * 10);
    const windDir   = Math.random() * 360;
    game.wind = { speed: windSpeed, dir: windDir };
    setWind(windSpeed, windDir);
    hud.setWind(windSpeed, windDir);

    hud.showTitle();
    state = STATE.TITLE;

    document.getElementById('btn-start')?.addEventListener('click', startRound);
    setupControls();

  } catch (err) {
    console.error('Boot failed:', err);
    document.title = 'ERR: ' + err.message;
  }
}

// ---------- Round lifecycle ----------
function startRound() {
  hud.hideTitle();
  game.holeIdx = 0;
  game.scores  = Array(18).fill(null);
  startHole();
}

function startHole() {
  const hole = currentHole();
  game.stroke = 1;
  game.lie    = 'tee';

  // Position ball on tee
  const [tx, tz] = hole.tee;
  const ty = heightAt(tx, tz);
  game.ballPos = { x: tx, y: ty, z: tz };
  ballMesh.position.set(tx, ty + 0.022, tz);

  // Aim toward green by default
  const [gx, gz] = hole.green.center;
  aimAngle = Math.atan2(gx - tx, gz - tz);

  // Camera behind tee
  const cam = holeCameraPos(hole, 18);
  camera.position.set(cam.cx, cam.cy, cam.cz);
  camera.lookAt(cam.tx, cam.ty, cam.tz);

  // HUD
  const yardage = holeYardage(hole);
  hud.setHole(hole.number, hole.par, yardage, courseData.meta?.name);
  hud.setStroke(1, scoreStr());
  const playsY = playsLike(
    Math.hypot(gx - tx, gz - tz),
    heightAt(tx, tz),
    heightAt(gx, gz)
  );
  hud.setPin(fmtYards(Math.hypot(gx - tx, gz - tz)), playsY, 'TEE');
  hud.setPinLabel('TO PIN');
  hud.setClub(CLUBS[game.clubIdx].name, null);

  hud.hideShotData();
  hud.hidePuttMode();
  removeBreakArrows(scene);
  hideReplayButton();
  clearTrajectory();

  // Intro overlay
  hud.showIntro(`Hole ${hole.number}`, hole.par, yardage);
  setTimeout(() => { hud.hideIntro(); setupShot(); }, 2200);

  state = STATE.INTRO;
}

function setupShot() {
  hud.showHUD();
  hud.setStroke(game.stroke, scoreStr());

  const hole = currentHole();
  const [gx, gz] = hole.green.center;
  const [bx, bz] = [game.ballPos.x, game.ballPos.z];
  const dist = Math.hypot(gx - bx, gz - bz);
  const playsY = playsLike(dist, heightAt(bx, bz), heightAt(gx, gz));
  hud.setPin(fmtYards(dist), playsY, game.lie);

  // Show putting mode if on green
  if (game.lie === 'green') {
    state = STATE.PUTTING;
    hud.showPuttMode(courseData.meta?.stimp ?? 10);
    buildBreakArrows(hole, scene);
    hud.showHUD();
    return;
  }

  state = STATE.SETUP;
  hud.showMeter();
  meter.phase = 0; meter.pct = 0; meter.dir = 1; meter.snapped = false;
  updateAimLine();
}

function fire(power, putter = false) {
  if (state !== STATE.SETUP && state !== STATE.PUTTING) return;
  const hole  = currentHole();
  const club  = CLUBS[game.clubIdx];
  const lie   = LIE_EFFECT[game.lie] || LIE_EFFECT.rough;

  const speed = club.speed * lie.speed * (putter ? power : Math.max(power, 0.12));
  const speedMph = speed * 2.23694;
  const vla = club.launch;
  const backspin = club.spin * lie.spin;
  const sidespin = (aimAngle - Math.atan2(
    hole.green.center[0] - game.ballPos.x,
    hole.green.center[1] - game.ballPos.z
  )) * 800;

  SFX.strike(power, putter);
  hud.hideShotData();
  hud.hideMeter();
  hud.hidePuttMode();
  hideReplayButton();
  clearTrajectory();

  const hlaDeg = (aimAngle - Math.atan2(
    hole.green.center[0] - game.ballPos.x,
    hole.green.center[1] - game.ballPos.z
  )) * (180 / Math.PI);

  sim = createShot({
    ballSpeedMph: speedMph,
    vlaDegrees:   vla * (putter ? 0.5 : 1),
    backspin,
    sidespin:     putter ? 0 : sidespin,
    hlaDegrees:   hlaDeg,
    windSpeedMph: game.wind.speed,
    windDirDeg:   game.wind.dir,
    lie:          game.lie,
    startX: game.ballPos.x,
    startY: 0.02,
    startZ: game.ballPos.z,
    stimp:  courseData.meta?.stimp ?? 10,
  });

  state = STATE.FLYING;
  aimLine.visible = false;
}

function resolveShot() {
  state = STATE.RESOLVING;
  const surf = surfaceAt(sim.pos.x, sim.pos.z);
  game.lie = surf;
  game.ballPos = { x: sim.pos.x, y: sim.pos.y, z: sim.pos.z };

  const hole = currentHole();
  const [gx, gz] = hole.green.center;

  // Check holed
  const distToPin = Math.hypot(sim.pos.x - gx, sim.pos.z - gz);
  const onGreen = surf === SURF.GREEN;

  if (distToPin < 0.5) {
    // Holed!
    SFX.holed();
    hud.toast('<span class="t-hi">⛳ IN THE CUP!</span>', 2500);
    game.scores[game.holeIdx] = game.stroke;
    setTimeout(() => nextHole(), 2800);
    return;
  }

  // Record landing for dispersion
  const carry = sim.carryPos;
  if (carry) {
    const cx = carry.x - hole.tee[0], cz = carry.z - hole.tee[1];
    const toPinX = gx - carry.x, toPinZ = gz - carry.z;
    recordLanding(CLUBS[game.clubIdx].name, toPinX, toPinZ);
  }

  // Carry / total
  if (sim.carryPos) {
    const cDist = Math.hypot(sim.carryPos.x - hole.tee[0], sim.carryPos.z - hole.tee[1]);
    game.carryMeters = cDist;
  }
  const tDist = Math.hypot(sim.pos.x - hole.tee[0], sim.pos.z - hole.tee[1]);
  game.totalMeters = tDist;

  // Show shot data
  hud.showShotData({
    speed:  Math.round(sim.carryPos ? Math.hypot(sim.vel.x, sim.vel.z) * 2.23694 : 0),
    launch: '—',
    spin:   Math.round(sim.spin?.rate ?? 0),
    apex:   Math.round(sim.apexFt ?? 0),
    carry:  fmtYards(game.carryMeters),
    total:  fmtYards(game.totalMeters),
  });

  // Offer replay
  if (hasTrajectory()) showReplayButton();

  // Water/OOB handling
  if (surf === SURF.WATER) {
    SFX.splash();
    hud.toast('<span class="t-sub">WATER</span>', 1500);
    game.stroke += 2; // stroke + penalty
    setTimeout(() => reteeFromPenalty(), 1800);
    return;
  }

  // Dispersion tendency hint
  const tendency = getTendency(CLUBS[game.clubIdx].name);
  if (tendency) {
    setTimeout(() => hud.toast(`<span class="t-sub">Tendency: ${tendency}</span>`, 2000), 1500);
  }

  game.stroke++;

  // Move to next shot or putting
  if (onGreen) {
    game.lie = 'green';
    setTimeout(() => setupShot(), 1200);
  } else {
    setTimeout(() => { if (!isReplaying()) setupShot(); }, 800);
  }
}

function reteeFromPenalty() {
  const hole = currentHole();
  const [tx, tz] = hole.tee;
  game.ballPos = { x: tx, y: heightAt(tx, tz), z: tz };
  game.lie = 'tee';
  setupShot();
}

function nextHole() {
  if (game.holeIdx >= 17) {
    endRound();
    return;
  }
  game.holeIdx++;
  startHole();
}

function endRound() {
  const total = game.scores.reduce((s, v) => s + (v || 0), 0);
  const par   = courseData.holes.reduce((s, h) => s + h.par, 0);
  hud.showScorecard();
  hud.renderScorecard(courseData.holes, game.scores);
  state = STATE.RESULT;
}

// ---------- Helpers ----------
function currentHole() {
  return courseData.holes[game.holeIdx];
}

function holeYardage(hole) {
  const [tx, tz] = hole.tee, [gx, gz] = hole.green.center;
  return fmtYards(Math.hypot(gx - tx, gz - tz));
}

function scoreStr() {
  const total = game.scores.reduce((s, v) => s + (v || 0), 0);
  const par   = courseData.holes.slice(0, game.holeIdx).reduce((s, h) => s + h.par, 0);
  return toParStr(total - par);
}

function matchClubByName(name) {
  if (!name) return -1;
  const n = name.toUpperCase().trim();
  for (let i = 0; i < CLUBS.length; i++) {
    if (CLUBS[i].name.includes(n) || n.includes(CLUBS[i].id) || n.includes(CLUBS[i].name)) return i;
  }
  return -1;
}

// ---------- Controls ----------
function setupControls() {
  // Keyboard
  document.addEventListener('keydown', onKey);

  // Space / click → swing or advance meter
  renderer.domElement.addEventListener('click', onSwingInput);
  document.addEventListener('keydown', e => { if (e.code === 'Space') { e.preventDefault(); onSwingInput(); } });

  // Aim with left/right
  // Putt bar: space/click holds, release fires
  document.getElementById('putt-bar')?.addEventListener('mousedown', () => puttBar?.onPress());
  document.addEventListener('mouseup', () => {
    if (state === STATE.PUTTING && puttBar) {
      const power = puttBar.onRelease();
      fire(power, true);
    }
  });

  // Replay button
  document.getElementById('replay-btn')?.addEventListener('click', () => {
    startReplay(camera, () => { if (state !== STATE.PUTTING) setupShot(); });
  });
  document.getElementById('replay-skip')?.addEventListener('click', skipReplay);

  // Break arrows toggle
  document.getElementById('break-btn')?.addEventListener('click', () => {
    const hole = currentHole();
    if (document.getElementById('break-btn')?.textContent === 'SHOW BREAK') {
      buildBreakArrows(hole, scene);
      hud.showBreakArrows();
    } else {
      removeBreakArrows(scene);
      hud.hideBreakArrows();
    }
  });

  // Scorecard toggle
  document.addEventListener('keydown', e => {
    if (e.key === 'Tab') { e.preventDefault(); hud.showScorecard(); hud.renderScorecard(courseData.holes, game.scores); }
  });
  document.getElementById('scorecard')?.addEventListener('click', () => hud.hideScorecard());
}

function onKey(e) {
  if (e.code === 'ArrowLeft')  { aimAngle -= 0.03; updateAimLine(); }
  if (e.code === 'ArrowRight') { aimAngle += 0.03; updateAimLine(); }
  if (e.code === 'ArrowUp'   && !game.isLive) { game.clubIdx = Math.max(0, game.clubIdx - 1); refreshClub(); }
  if (e.code === 'ArrowDown' && !game.isLive) { game.clubIdx = Math.min(CLUBS.length - 2, game.clubIdx + 1); refreshClub(); }
}

function onSwingInput() {
  if (state === STATE.SETUP) {
    if (meter.phase === 0) {
      meter.phase = 1; meter.dir = 1; // start
    } else if (meter.phase === 1) {
      meter.snapped = true; meter.snapPct = meter.pct;
      meter.phase = 2; meter.dir = -1; // return
    } else if (meter.phase === 2) {
      const power = meter.snapPct * (1 - Math.abs(meter.pct - meter.snapPct) * 0.5);
      fire(power);
    }
  }
}

function refreshClub() {
  hud.setClub(CLUBS[game.clubIdx].name, null);
  SFX.tick();
}

function updateAimLine() {
  if (state !== STATE.SETUP) return;
  const [bx, bz] = [game.ballPos.x, game.ballPos.z];
  const by = heightAt(bx, bz) + 0.1;
  aimLine.position.set(bx + Math.sin(aimAngle) * 5, by, bz + Math.cos(aimAngle) * 5);
  aimLine.rotation.set(0, -aimAngle, Math.PI / 2);
  aimLine.visible = true;
}

// ---------- Live mode ----------
function onLiveShotReceived(payload) {
  if (state !== STATE.SETUP && state !== STATE.PUTTING) return;
  pendingLiveShot = payload;

  const speed = payload.ballSpeedMph;
  const vla   = payload.vlaDegrees;
  const back  = payload.backspinRpm ?? 2500;
  const side  = payload.sidespinRpm ?? 0;
  const hla   = payload.hlaDegrees ?? 0;

  const hole = currentHole();
  const [gx, gz] = hole.green.center;
  const [bx, bz] = [game.ballPos.x, game.ballPos.z];
  const baseAngle = Math.atan2(gx - bx, gz - bz);

  SFX.strike(speed / 165);

  sim = createShot({
    ballSpeedMph: speed,
    vlaDegrees:   vla,
    backspin:     back,
    sidespin:     side,
    hlaDegrees:   baseAngle * (180 / Math.PI) + hla,
    windSpeedMph: game.wind.speed,
    windDirDeg:   game.wind.dir,
    lie:          game.lie,
    startX: bx, startY: 0.02, startZ: bz,
    stimp:  courseData.meta?.stimp ?? 10,
  });

  state = STATE.FLYING;
  hud.hideShotData();
  clearTrajectory();
  aimLine.visible = false;
  game.stroke++;
}

function onLiveStatus(s) { /* could show badge */ }
function onLivePing() {
  // App connected — show connected state
  hud.toast('App connected ✓', 1200);
}
function onLiveClub(name) {
  const idx = matchClubByName(name);
  if (idx >= 0) { game.clubIdx = idx; refreshClub(); }
}

// ---------- Animation loop ----------
const clock = new THREE.Clock();
const MAX_SIM_STEPS = 30;

function animate() {
  requestAnimationFrame(animate);
  const dt = clock.getDelta();
  const t  = clock.elapsedTime;

  // Animate world (water, tree sway, cloud shadows)
  const windRad = game.wind.dir * (Math.PI / 180);
  updateWorld(t, { x: Math.sin(windRad) * game.wind.speed * 0.44704, z: Math.cos(windRad) * game.wind.speed * 0.44704 });

  // Sky shadow frustum tracks ball
  if (sky && game.ballPos) sky.update(t, { x: game.ballPos.x, z: game.ballPos.z });

  // Replay mode
  if (isReplaying()) {
    updateReplay(camera);
    renderer.render(scene, camera);
    return;
  }

  // Meter animation
  if (state === STATE.SETUP && meter.phase > 0) {
    meter.pct += meter.dir * METER_SPEED * dt;
    if (meter.pct >= 1) { meter.pct = 1; meter.dir = -1; }
    if (meter.pct <= 0) { meter.pct = 0; meter.dir = 1; }
    hud.setMeter(meter.pct, meter.snapped && meter.phase === 2);
  }

  // Physics
  if (state === STATE.FLYING || state === STATE.ROLLING) {
    const stepsThisFrame = Math.min(Math.round(dt * 240), MAX_SIM_STEPS);
    const wasInFlight = sim.inFlight;

    for (let i = 0; i < stepsThisFrame; i++) {
      stepFly(sim, { stimp: courseData.meta?.stimp ?? 10 });

      // Record trajectory (every 4 substeps while airborne)
      if (sim.inFlight && i % 4 === 0) recordPosition(sim.pos);

      // Events
      for (const ev of sim.events) handleEvent(ev);
      sim.events = [];

      if (!sim.inFlight && Math.hypot(sim.vel.x, sim.vel.z) < 0.05) {
        // Ball stopped
        ballMesh.position.set(sim.pos.x, sim.pos.y, sim.pos.z);
        updateMinimapBall();
        resolveShot();
        return;
      }
    }

    if (wasInFlight && !sim.inFlight) state = STATE.ROLLING;

    ballMesh.position.set(sim.pos.x, sim.pos.y, sim.pos.z);
    updateMinimapBall();

    // Chase camera during flight
    if (sim.inFlight) {
      const tgt = new THREE.Vector3(sim.pos.x, sim.pos.y + 3, sim.pos.z);
      const behind = new THREE.Vector3(
        sim.pos.x - Math.sin(aimAngle) * 12,
        sim.pos.y + 8,
        sim.pos.z - Math.cos(aimAngle) * 12,
      );
      camera.position.lerp(behind, 0.04);
      camera.lookAt(tgt);
    }

    // HUD distance update during flight
    const hole = currentHole();
    const [gx, gz] = hole.green.center;
    const dist = Math.hypot(sim.pos.x - gx, sim.pos.z - gz);
    hud.setPinNum(fmtYards(dist));
    if (sim.inFlight) hud.setPinLabel('TO PIN');
  }

  renderer.render(scene, camera);
}

function handleEvent(ev) {
  if (ev.type === 'land') {
    SFX.bounce(mag(sim.vel));
    const toastMap = { bunker: '⚠ BUNKER', water: '💧 WATER', green: '📍 GREEN' };
    const msg = toastMap[ev.surface];
    if (msg) hud.toast(`<span class="t-sub">${msg}</span>`, 1100);
  } else if (ev.type === 'water') {
    SFX.splash();
    hud.toast('<span class="t-sub">WATER</span>', 1200);
  } else if (ev.type === 'plugged') {
    hud.toast('<span class="t-sub">PLUGGED</span>', 1100);
  } else if (ev.type === 'tree') {
    SFX.bounce(ev.graze ? 2 : 5);
    hud.toast(ev.graze ? '<span class="t-sub">BRUSH</span>' : '<span class="t-sub">TREE</span>', 900);
  }
}

function mag(v) { return Math.hypot(v.x || 0, v.z || 0); }

function updateMinimapBall() {
  if (!_minimapToC) return;
  const canvas = document.getElementById('minimap');
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  // Redraw base then ball dot
  if (minimapBase) drawMinimapBase(courseData, canvas);
  const [cx, cz] = _minimapToC(game.ballPos.x, game.ballPos.z);
  ctx.beginPath();
  ctx.arc(cx, cz, 4, 0, Math.PI * 2);
  ctx.fillStyle = '#ffffff';
  ctx.fill();

  // Active hole marker
  const hole = currentHole();
  const [gx, gz] = _minimapToC(hole.green.center[0], hole.green.center[1]);
  ctx.beginPath();
  ctx.arc(gx, gz, 3, 0, Math.PI * 2);
  ctx.fillStyle = '#ffd700';
  ctx.fill();
}

// ---------- Message bus (from website iframe) ----------
window.addEventListener('message', ({ data }) => {
  if (!data?.type) return;
  if (data.type === 'START_COURSE' && courseData) {
    startRound();
  }
});

// ---------- Start ----------
boot().then(() => animate());
