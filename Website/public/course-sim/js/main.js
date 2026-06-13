// TrueCarry_Course — main game orchestration.
// Loads pinchbrook.json, builds world, manages shot lifecycle for all 18 holes.

import * as THREE from 'three';
import { EffectComposer }   from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass }       from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass }  from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass }       from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass }       from 'three/addons/postprocessing/ShaderPass.js';
import { FXAAShader }       from 'three/addons/shaders/FXAAShader.js';
import { CLUBS, LIE_EFFECT, fmtYards }          from './clubs.js';
import { SFX }                                   from './audio.js';
import { HUD, toParStr }                         from './hud.js';
import { buildWorld, updateWorld, heightAt, surfaceAt, slopeAt, SURF, SURF_PROPS, holeCameraPos, drawMinimapBase, setTreeFade } from './terrain.js';
import { loadAssets }                            from './assets.js';
import { makeSky }                               from './sky.js';
import { createShot, stepFly, playsLike, setWind, SURF as PHYS_SURF } from './physics.js';
import { buildGreenMesh, buildBreakArrows, removeBreakArrows, createPuttingBar } from './green.js';
import { recordPosition, clearTrajectory, hasTrajectory, startReplay, updateReplay, showReplayButton, hideReplayButton, isReplaying, skipReplay } from './replay.js';
import { recordLanding, drawDispersion, getTendency, getDispersion }  from './dispersion.js';
import { getLiveCode, connectLive }              from './live.js';

// ---------- Bootstrap ----------
const hud = new HUD();

const renderer = new THREE.WebGLRenderer({ antialias: false, powerPreference: 'high-performance' });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.15;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.domElement.className = 'gl';
document.getElementById('app').prepend(renderer.domElement);

const scene  = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 0.5, 4000);

let sky = null;  // set after assets load

// ── Post-processing composer ──────────────────────────────────────────────────
let composer, fxaaPass, bloomPass;

function buildComposer() {
  composer = new EffectComposer(renderer);
  composer.addPass(new RenderPass(scene, camera));

  // Subtle bloom — makes grass highlights and water shimmer
  bloomPass = new UnrealBloomPass(
    new THREE.Vector2(window.innerWidth, window.innerHeight),
    0.22,   // strength
    0.5,    // radius
    0.88,   // threshold — only very bright specular highlights
  );
  composer.addPass(bloomPass);

  // FXAA antialiasing — lightweight, single-pass
  fxaaPass = new ShaderPass(FXAAShader);
  fxaaPass.material.uniforms['resolution'].value.set(
    1 / window.innerWidth, 1 / window.innerHeight,
  );
  composer.addPass(fxaaPass);

  composer.addPass(new OutputPass());
}

window.addEventListener('resize', () => {
  const W = window.innerWidth, H = window.innerHeight;
  camera.aspect = W / H;
  camera.updateProjectionMatrix();
  renderer.setSize(W, H);
  composer?.setSize(W, H);
  if (fxaaPass) fxaaPass.material.uniforms['resolution'].value.set(1/W, 1/H);
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

function refreshMinimap() {
  const canvas = document.getElementById('minimap');
  if (!canvas || !courseData) return;
  const result = drawMinimapBase(courseData, canvas, game.holeIdx);
  minimapBase = result;
  _minimapToC = result.toC;
}

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
    buildComposer();

    // Build all green meshes (undulation)
    for (const hole of courseData.holes) {
      const gm = buildGreenMesh(hole, scene);
      if (gm) greenMeshes.push(gm);
    }

    // Minimap
    refreshMinimap();

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

    // Auto-enter explore mode when ?explore is in the URL
    if (new URLSearchParams(location.search).has('explore')) {
      // Place camera at a nice overview position, then enter free-fly
      camera.position.set(100, 80, 50);
      camera.lookAt(200, 60, -100);
      enterFreeFly();
    }

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

  // Camera at front of tee box, eye level
  const cam = holeCameraPos(hole);
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
  _aimIndicator?.classList.add('hidden');
  aimLine.visible = false;
  removeBreakArrows(scene);
  hideReplayButton();
  clearTrajectory();

  // Intro overlay
  refreshMinimap();

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
  _aimIndicator?.classList.remove('hidden');
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
  _aimIndicator?.classList.add('hidden');
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

const _aimNeedle = document.getElementById('aim-needle');
const _aimOffset = document.getElementById('aim-offset');
const _aimIndicator = document.getElementById('aim-indicator');

function updateAimLine() {
  if (state !== STATE.SETUP) return;
  const [bx, bz] = [game.ballPos.x, game.ballPos.z];
  const by = heightAt(bx, bz) + 0.1;
  aimLine.position.set(bx + Math.sin(aimAngle) * 5, by, bz + Math.cos(aimAngle) * 5);
  aimLine.rotation.set(0, -aimAngle, Math.PI / 2);
  aimLine.visible = true;

  // Update arc compass
  const hole = currentHole();
  const [gx, gz] = hole.green.center;
  const pinAngle = Math.atan2(gx - bx, gz - bz);
  const offset = aimAngle - pinAngle;
  const deg = Math.round(offset * 180 / Math.PI);
  // Needle: clamped to ±80° visual, pivot at (60,57)
  const clamp = Math.max(-80, Math.min(80, deg));
  const rad = clamp * Math.PI / 180;
  const nx = 60 + Math.sin(rad) * 47;
  const ny = 57 - Math.cos(rad) * 47;
  _aimNeedle.setAttribute('x2', nx.toFixed(1));
  _aimNeedle.setAttribute('y2', ny.toFixed(1));
  _aimNeedle.setAttribute('stroke', Math.abs(deg) < 5 ? '#44ff77' : Math.abs(deg) < 15 ? '#ffcc33' : '#ff5533');
  _aimOffset.textContent = deg === 0 ? '0°' : (deg > 0 ? `+${deg}°R` : `${-deg}°L`);
  _aimOffset.style.color = Math.abs(deg) < 5 ? '#44ff77' : Math.abs(deg) < 15 ? '#ffcc33' : '#ff5533';
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

// ---------- Free-fly explore mode ----------
let freeFly = false;
let ffYaw = 0, ffPitch = -0.15;
let ffHoleIdx = 0;  // for hole cycling
const ffKeys    = {};
const ffDir     = new THREE.Vector3();
const ffRight   = new THREE.Vector3();
const ffMove    = new THREE.Vector3();
let ffDragging  = false, ffLastX = 0, ffLastY = 0;

const ffHint = document.createElement('div');
ffHint.style.cssText = [
  'position:fixed', 'top:14px', 'left:50%', 'transform:translateX(-50%)',
  'background:rgba(0,0,0,0.78)', 'color:#fff', 'font:bold 13px system-ui',
  'padding:9px 22px', 'border-radius:22px', 'z-index:9999',
  'pointer-events:none', 'display:none', 'white-space:nowrap',
].join(';');
document.body.appendChild(ffHint);

function ffUpdateHint() {
  if (!courseData) return;
  const h = courseData.holes[ffHoleIdx];
  const dist = Math.round(Math.hypot(h.green.center[0]-h.tee[0], h.green.center[1]-h.tee[1]) * 1.09361);
  ffHint.textContent = `EXPLORE  ·  H${h.number} PAR ${h.par} · ${dist} YDS  ·  [ ] cycle holes  ·  WASD+drag to fly  ·  F to exit`;
}

function ffSnapToHole(idx) {
  if (!courseData) return;
  ffHoleIdx = ((idx % courseData.holes.length) + courseData.holes.length) % courseData.holes.length;
  const cam = holeCameraPos(courseData.holes[ffHoleIdx]);
  camera.position.set(cam.cx, cam.cy, cam.cz);
  const fwd = new THREE.Vector3(cam.tx - cam.cx, cam.ty - cam.cy, cam.tz - cam.cz).normalize();
  ffYaw   = Math.atan2(fwd.x, fwd.z);
  ffPitch = Math.asin(Math.max(-0.99, Math.min(0.99, fwd.y)));
  ffUpdateHint();
}

function enterFreeFly() {
  freeFly = true;
  ffHint.style.display = 'block';
  _aimIndicator?.classList.add('hidden');
  aimLine.visible = false;
  const fwd = new THREE.Vector3();
  camera.getWorldDirection(fwd);
  ffYaw   = Math.atan2(fwd.x, fwd.z);
  ffPitch = Math.asin(Math.max(-0.99, Math.min(0.99, fwd.y)));
  ffHoleIdx = game.holeIdx;
  ffUpdateHint();
}
function exitFreeFly() {
  freeFly = false;
  ffDragging = false;
  ffHint.style.display = 'none';
  if (state === STATE.SETUP) { _aimIndicator?.classList.remove('hidden'); updateAimLine(); }
}

document.addEventListener('keydown', e => {
  ffKeys[e.code] = true;
  if (e.code === 'KeyF')   freeFly ? exitFreeFly() : enterFreeFly();
  if (e.code === 'Escape' && freeFly) exitFreeFly();
  if (freeFly && e.code === 'BracketLeft')  ffSnapToHole(ffHoleIdx - 1);
  if (freeFly && e.code === 'BracketRight') ffSnapToHole(ffHoleIdx + 1);
});
document.addEventListener('keyup', e => { ffKeys[e.code] = false; });

// Click+drag mouse look — no pointer lock required
renderer.domElement.addEventListener('mousedown', e => {
  if (freeFly) { ffDragging = true; ffLastX = e.clientX; ffLastY = e.clientY; }
});
window.addEventListener('mouseup', () => { ffDragging = false; });
window.addEventListener('mousemove', e => {
  if (!freeFly || !ffDragging) return;
  ffYaw   -= (e.clientX - ffLastX) * 0.003;
  ffPitch -= (e.clientY - ffLastY) * 0.003;
  ffPitch  = Math.max(-1.48, Math.min(1.48, ffPitch));
  ffLastX  = e.clientX;
  ffLastY  = e.clientY;
});

function tickFreeFly(dt) {
  const speed = (ffKeys['ShiftLeft'] || ffKeys['ShiftRight']) ? 80 : 22;
  ffDir.set(
    Math.sin(ffYaw) * Math.cos(ffPitch),
    Math.sin(ffPitch),
    Math.cos(ffYaw) * Math.cos(ffPitch),
  );
  ffRight.set(Math.cos(ffYaw), 0, -Math.sin(ffYaw));
  ffMove.set(0, 0, 0);
  if (ffKeys['KeyW'] || ffKeys['ArrowUp'])    ffMove.addScaledVector(ffDir,    speed * dt);
  if (ffKeys['KeyS'] || ffKeys['ArrowDown'])  ffMove.addScaledVector(ffDir,   -speed * dt);
  if (ffKeys['KeyA'] || ffKeys['ArrowLeft'])  ffMove.addScaledVector(ffRight, -speed * dt);
  if (ffKeys['KeyD'] || ffKeys['ArrowRight']) ffMove.addScaledVector(ffRight,  speed * dt);
  if (ffKeys['KeyE']) ffMove.y +=  speed * dt;
  if (ffKeys['KeyQ']) ffMove.y += -speed * dt;
  camera.position.add(ffMove);
  camera.lookAt(camera.position.clone().add(ffDir));
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

  // Dissolve tree canopies when camera is inside one
  setTreeFade(camera.position.x, camera.position.z, courseData?.trees);

  // Free-fly explore mode — takes over camera and skips game logic
  if (freeFly) {
    tickFreeFly(dt);
    if (sky) sky.update(t, { x: camera.position.x, z: camera.position.z });
    composer ? composer.render() : renderer.render(scene, camera);
    return;
  }

  // Sky shadow frustum tracks ball
  if (sky && game.ballPos) sky.update(t, { x: game.ballPos.x, z: game.ballPos.z });

  // Replay mode
  if (isReplaying()) {
    updateReplay(camera);
    composer ? composer.render() : renderer.render(scene, camera);
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

  composer ? composer.render() : renderer.render(scene, camera);
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
  // Redraw base for current hole then ball dot
  if (minimapBase) drawMinimapBase(courseData, canvas, game.holeIdx);
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
