// GSPro Web — game orchestration: scene, state machine, swing meter,
// cameras, shot lifecycle, scoring.

import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { SAOPass } from 'three/addons/postprocessing/SAOPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { CLUBS, LIE_EFFECT, fmtYards } from './clubs.js?v=gspro-2';
import { createShot, simulateCarry, SURF } from './physics.js?v=gspro-2';
import { RANGE, holeLength } from './holes.js?v=gspro-2';
import { buildCourse } from './terrain.js?v=gspro-2';
import { makeSky } from './sky.js?v=gspro-2';
import { loadAssets } from './assets.js?v=gspro-2';
import { HUD, toParStr } from './ui.js?v=gspro-2';
import { SFX } from './audio.js?v=gspro-2';
import { getLiveCode, connectLive, publishLiveState } from './live.js?v=gspro-2';
import { fetchSimCourses } from './courses.js?v=gspro-2';
import { LOCAL_COURSES, getLocalCourse } from './local-courses.js?v=gspro-2';
import { layoutIslandCourse } from './world.js?v=gspro-2';

// ---------- boot ----------

const hud = new HUD();
const launchParams = new URLSearchParams(location.search);
const launchMode = launchParams.get('mode');
const launchCourseId = launchParams.get('course') || launchParams.get('courseId') || 'pine-hollow';
let urlLaunchHandled = false;

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

// ---------- post-processing (broadcast look: subtle AO + bloom) ----------
// Multisampled target keeps MSAA through the composer (WebGL2). If anything
// in the chain fails on an exotic GPU, fall back to the direct render path.
let composer = null;
try {
  const size = renderer.getDrawingBufferSize(new THREE.Vector2());
  const target = new THREE.WebGLRenderTarget(size.x, size.y, {
    samples: 4,
    type: THREE.HalfFloatType,
  });
  composer = new EffectComposer(renderer, target);
  composer.addPass(new RenderPass(scene, camera));
  const sao = new SAOPass(scene, camera);
  sao.params.saoIntensity = 0.012;
  sao.params.saoScale = 64;
  sao.params.saoKernelRadius = 18;
  sao.params.saoBlur = true;
  composer.addPass(sao);
  const bloom = new UnrealBloomPass(new THREE.Vector2(size.x, size.y), 0.22, 0.5, 0.88);
  composer.addPass(bloom);
  composer.addPass(new OutputPass());
} catch (err) {
  console.warn('post-processing unavailable, falling back to direct render', err);
  composer = null;
}

let activeCourse = LOCAL_COURSES[0];
let selectableCourses = [...LOCAL_COURSES];

// Daily pin rotation: courses that ship multiple pin positions per green
// (hole.pins) get a deterministic daily selection, so the course changes
// day to day the way a real setup crew moves cups.
function applyDailyPins(world) {
  const day = Math.floor(Date.now() / 86400000);
  for (const hole of world.holes || []) {
    if (Array.isArray(hole.pins) && hole.pins.length > 1) {
      hole.pin = hole.pins[(day + hole.id) % hole.pins.length];
    }
  }
  return world;
}

let courseWorld = applyDailyPins(layoutIslandCourse(activeCourse.holes, activeCourse.world));
let courseHoles = courseWorld.holes;
hud.mapSetCourse(courseHoles, courseWorld);

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
  if (composer) {
    const size = renderer.getDrawingBufferSize(new THREE.Vector2());
    composer.setSize(size.x, size.y);
  }
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
  new THREE.SphereGeometry(0.034, 24, 18),
  new THREE.MeshStandardMaterial({
    color: 0xfdfdf6, roughness: 0.32, metalness: 0.0, envMapIntensity: 0.9,
  }),
);
ball.castShadow = true;

// Instant replay: ghost ball that re-flies the recorded flight path while a
// side-on broadcast camera tracks it. Toggled with R after any shot.
const replayBall = new THREE.Mesh(
  new THREE.SphereGeometry(0.05, 20, 14),
  new THREE.MeshStandardMaterial({ color: 0xfdfdf6, roughness: 0.3, emissive: 0x776633, emissiveIntensity: 0.35 }),
);
replayBall.castShadow = true;
replayBall.visible = false;

// Pitch marks: greens remember where approach shots landed this hole.
const pitchMarks = new THREE.Group();
const pitchMarkMat = new THREE.MeshBasicMaterial({
  color: 0x3c5a2e, transparent: true, opacity: 0.55, depthWrite: false,
});
const pitchMarkGeo = new THREE.CircleGeometry(0.055, 10);
function addPitchMark(x, z) {
  if (pitchMarks.children.length > 40) pitchMarks.remove(pitchMarks.children[0]);
  const m = new THREE.Mesh(pitchMarkGeo, pitchMarkMat);
  m.rotation.x = -Math.PI / 2;
  m.rotation.z = Math.random() * Math.PI;
  m.scale.set(1 + Math.random() * 0.5, 1.6 + Math.random() * 0.6, 1);
  m.position.set(x, game.course.heightAt(x, z) + 0.012, z);
  pitchMarks.add(m);
}
scene.add(ball);
scene.add(replayBall);
scene.add(pitchMarks);

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

// ---------- multi-player ghost balls ----------
// Other players' resting ball positions, rendered simultaneously with the active player's
// `ball` above. Index 0 (the account holder) never gets a ghost — they're always `ball` when
// active, and never need a ghost of themselves since only one player is "active" at a time.
const GHOST_COLORS = [0x5ac8fa, 0xff9f0a, 0xbf5af2, 0x30d158, 0xff375f];
function makeGhostLabel(text) {
  const cv = document.createElement('canvas');
  cv.width = 256; cv.height = 64;
  const c = cv.getContext('2d');
  c.fillStyle = 'rgba(10,14,10,0.72)';
  c.roundRect ? c.roundRect(0, 8, 256, 48, 14) : c.fillRect(0, 8, 256, 48);
  c.fill();
  c.font = '600 30px -apple-system, system-ui, sans-serif';
  c.fillStyle = '#fff';
  c.textAlign = 'center';
  c.textBaseline = 'middle';
  c.fillText(text, 128, 34);
  const tex = new THREE.CanvasTexture(cv);
  const mat = new THREE.SpriteMaterial({ map: tex, depthTest: false, transparent: true });
  const sprite = new THREE.Sprite(mat);
  sprite.scale.set(0.9, 0.22, 1);
  return sprite;
}
function makeGhostBall(colorHex) {
  const mesh = new THREE.Mesh(
    new THREE.SphereGeometry(0.034, 16, 12),
    new THREE.MeshStandardMaterial({ color: colorHex, roughness: 0.4, emissive: colorHex, emissiveIntensity: 0.25 }),
  );
  mesh.visible = false;
  scene.add(mesh);
  const label = makeGhostLabel('');
  label.visible = false;
  scene.add(label);
  return { mesh, label };
}
// Lazily grown pool — one ghost per non-active player, created the first time we learn a
// player's name (via the 'players' roster broadcast).
const ghostPool = [];
function ghostFor(playerIdx) {
  // playerIdx 1 → ghostPool[0], playerIdx 2 → ghostPool[1], etc. (index 0 has no ghost).
  const poolIdx = playerIdx - 1;
  while (ghostPool.length <= poolIdx) {
    ghostPool.push(makeGhostBall(GHOST_COLORS[ghostPool.length % GHOST_COLORS.length]));
  }
  return ghostPool[poolIdx];
}
function updateGhost(playerIdx, pos, visible) {
  if (playerIdx <= 0) return; // index 0 is the active `ball` mesh, never a ghost
  const g = ghostFor(playerIdx);
  g.mesh.visible = visible;
  g.label.visible = visible;
  if (pos) {
    g.mesh.position.set(pos.x, pos.y, pos.z);
    g.label.position.set(pos.x, pos.y + 0.16, pos.z);
  }
}
function refreshGhostLabel(playerIdx, name) {
  if (playerIdx <= 0) return;
  const g = ghostFor(playerIdx);
  const newLabel = makeGhostLabel(name.toUpperCase());
  newLabel.position.copy(g.label.position);
  newLabel.visible = g.label.visible;
  scene.remove(g.label);
  scene.add(newLabel);
  ghostPool[playerIdx - 1].label = newLabel;
}

// shot tracer — broadcast style: bright at the ball, fading down the tail
const TRACER_MAX = 2400;
const tracerPts = new Float32Array(TRACER_MAX * 3);   // raw flight points
// Broadcast-style tracer RIBBON: a camera-facing tapered strip (GL lines are
// stuck at 1px). Two vertices per point, billboarded in JS each repaint;
// additive blending gives the comet glow through the bloom pass.
const tracerPos = new Float32Array(TRACER_MAX * 6);
const tracerCol = new Float32Array(TRACER_MAX * 6);
const tracerIdx = new Uint32Array((TRACER_MAX - 1) * 6);
for (let i = 0; i < TRACER_MAX - 1; i++) {
  const a = i * 2;
  tracerIdx[i * 6] = a; tracerIdx[i * 6 + 1] = a + 1; tracerIdx[i * 6 + 2] = a + 2;
  tracerIdx[i * 6 + 3] = a + 1; tracerIdx[i * 6 + 4] = a + 3; tracerIdx[i * 6 + 5] = a + 2;
}
const tracerGeo = new THREE.BufferGeometry();
tracerGeo.setAttribute('position', new THREE.BufferAttribute(tracerPos, 3));
tracerGeo.setAttribute('color', new THREE.BufferAttribute(tracerCol, 3));
tracerGeo.setIndex(new THREE.BufferAttribute(tracerIdx, 1));
tracerGeo.setDrawRange(0, 0);
const tracer = new THREE.Mesh(
  tracerGeo,
  new THREE.MeshBasicMaterial({
    vertexColors: true, transparent: true, opacity: 0.85,
    blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
  }),
);
tracer.frustumCulled = false;
tracer.renderOrder = 5;
scene.add(tracer);
let tracerCount = 0;

const _tv = {
  tan: new THREE.Vector3(), view: new THREE.Vector3(),
  right: new THREE.Vector3(), pt: new THREE.Vector3(),
};
function tracerRepaint() {
  for (let i = 0; i < tracerCount; i++) {
    const t = tracerCount > 1 ? i / (tracerCount - 1) : 1;
    _tv.pt.set(tracerPts[i * 3], tracerPts[i * 3 + 1], tracerPts[i * 3 + 2]);
    const j = Math.min(i + 1, tracerCount - 1);
    const k0 = Math.max(i - 1, 0);
    _tv.tan.set(
      tracerPts[j * 3] - tracerPts[k0 * 3],
      tracerPts[j * 3 + 1] - tracerPts[k0 * 3 + 1],
      tracerPts[j * 3 + 2] - tracerPts[k0 * 3 + 2],
    );
    if (_tv.tan.lengthSq() < 1e-8) _tv.tan.set(0, 0, 1);
    _tv.view.subVectors(_tv.pt, camera.position);
    const dist = Math.max(_tv.view.length(), 2);
    _tv.right.crossVectors(_tv.view, _tv.tan);
    if (_tv.right.lengthSq() < 1e-6) {
      // Camera looking straight down the flight line: fall back to a stable
      // horizontal-ish perpendicular instead of a degenerate cross product.
      _tv.right.set(-_tv.tan.z, 0, _tv.tan.x);
      if (_tv.right.lengthSq() < 1e-6) _tv.right.set(1, 0, 0);
    }
    _tv.right.normalize();
    // Screen-proportional width (like a TV tracer): slim tail, comet head.
    const w = Math.min(2.2, Math.max(0.04, dist * (0.0022 + 0.0055 * t * t)));
    const gk = 0.22 + 0.78 * t * t;   // dim gold tail -> near-white head
    for (let sdx = 0; sdx < 2; sdx++) {
      const v = i * 2 + sdx;
      const sign = sdx === 0 ? 1 : -1;
      tracerPos[v * 3] = _tv.pt.x + _tv.right.x * w * sign;
      tracerPos[v * 3 + 1] = _tv.pt.y + _tv.right.y * w * sign;
      tracerPos[v * 3 + 2] = _tv.pt.z + _tv.right.z * w * sign;
      tracerCol[v * 3] = 0.93 * gk + 0.07;
      tracerCol[v * 3 + 1] = 0.85 * gk + 0.06;
      tracerCol[v * 3 + 2] = 0.62 * gk + 0.05;
    }
  }
  tracerGeo.setDrawRange(0, Math.max(0, (tracerCount - 1) * 6));
  tracerGeo.attributes.position.needsUpdate = true;
  tracerGeo.attributes.color.needsUpdate = true;
}

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
  scores: courseHoles.map(() => null),
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

  // Multi-player: `players[0]` is always the account holder ("You" — mirrors the live
  // ball/strokes/lie fields above while active). Other entries are populated lazily as their
  // names arrive via the 'players' roster broadcast. Single-player sessions never populate this,
  // so `players.length <= 1` throughout — every multi-player branch below is a no-op then.
  players: [],
  activePlayerIdx: 0,
};

let rangeMarkers = null;
let lastRangeShot = null;
let rangeStats = { shots: 0, totalCarry: 0, bestCarry: 0, recent: [] };
const holePickerCard = document.getElementById('hole-picker-card');
const holePicker = document.getElementById('hole-picker');
const holeGrid = document.getElementById('hole-grid');
const courseSelect = document.getElementById('course-select');
const courseSelectWrap = document.getElementById('course-select-wrap');
const rangePanel = document.getElementById('range-panel');

const club = () => CLUBS[game.clubIdx];
const onGreen = () => game.lie === SURF.GREEN;

function populateHolePicker() {
  if (!holePicker) return;
  holePicker.innerHTML = '';
  if (holeGrid) holeGrid.innerHTML = '';
  courseHoles.forEach((h, i) => {
    const opt = document.createElement('option');
    opt.value = String(i);
    opt.textContent = `${h.id}. ${h.name}`;
    holePicker.appendChild(opt);
    if (holeGrid) {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'hole-jump';
      btn.textContent = String(h.id ?? i + 1);
      btn.title = `Play hole ${h.id ?? i + 1}`;
      btn.dataset.holeIndex = String(i);
      holeGrid.appendChild(btn);
    }
  });
}

function getSelectableCourse(courseId) {
  return selectableCourses.find((course) => course.courseId === courseId)
    || getLocalCourse(courseId)
    || null;
}

function populateCourseSelect() {
  if (!courseSelect || !courseSelectWrap) return;
  courseSelect.innerHTML = '';
  selectableCourses.forEach((course) => {
    const opt = document.createElement('option');
    opt.value = course.courseId;
    opt.textContent = course.private
      ? `${course.courseName} (local)`
      : course.courseName;
    courseSelect.appendChild(opt);
  });
  courseSelect.value = activeCourse.courseId;
  courseSelectWrap.classList.remove('hidden');
}

function setTitleCourseName(courseName) {
  const titleSub = document.querySelector('.title-sub');
  if (titleSub) titleSub.textContent = `TRUECARRY · ${courseName.toUpperCase()}`;
}

function setActiveCourse(course) {
  const nextCourse = Array.isArray(course)
    ? { courseId: 'preview', courseName: 'Preview Course', holes: course, world: {} }
    : course;
  if (!nextCourse?.holes?.length) return;
  activeCourse = nextCourse;
  courseWorld = applyDailyPins(layoutIslandCourse(nextCourse.holes, nextCourse.world || {}));
  courseHoles = courseWorld.holes;
  if (game.course) {
    scene.remove(game.course.group);
    game.course.dispose();
    game.course = null;
  }
  game.scores = courseHoles.map(() => null);
  game.holeIdx = 0;
  hud.mapSetCourse(courseHoles, courseWorld);
  hud.mapSetMode('hole');
  hud.summaryHide();
  hud.scorecardHide();
  hud.toastHide();
  rangePanel?.classList.add('hidden');
  populateHolePicker();
  setHolePickerActive(0);
  setTitleCourseName(nextCourse.courseName || 'TrueCarry Course');
  if (courseSelect && courseSelect.value !== nextCourse.courseId && getSelectableCourse(nextCourse.courseId)) {
    courseSelect.value = nextCourse.courseId;
  }
}

function notifyParent(type, detail = {}) {
  window.parent?.postMessage({ type, ...detail }, '*');
}

function startCourseRound(courseId = activeCourse.courseId, holeIndex = 0) {
  const requestedCourse = courseId ? getSelectableCourse(courseId) : null;
  if (requestedCourse) setActiveCourse(requestedCourse);
  hud.titleHide();
  const idx = Math.max(0, Math.min(Number(holeIndex) || 0, courseHoles.length - 1));
  startHole(idx);
  notifyParent('SIM_LAUNCHED', { mode: 'course', courseId: activeCourse.courseId, courseName: activeCourse.courseName });
}

function startPracticeRange() {
  hud.titleHide();
  startRange();
  notifyParent('SIM_LAUNCHED', { mode: 'range', courseId: 'range', courseName: 'Practice Range' });
}

populateHolePicker();
populateCourseSelect();
setTitleCourseName(activeCourse.courseName);

function distToPin() {
  const p = game.course.pinPos;
  return Math.hypot(game.ballPos.x - p.x, game.ballPos.z - p.z);
}

function totalToPar() {
  if (game.isRange) return 0;
  let d = 0;
  courseHoles.forEach((h, i) => { if (game.scores[i] != null) d += game.scores[i] - h.par; });
  return d;
}

// Mirror the sim's current state to Supabase so a paired phone can show it live.
function pushLiveState(extra = {}) {
  if (!window.__liveMode || game.isRange) return;
  const code = getLiveCode();
  if (!code) return;
  const def = courseHoles[game.holeIdx] || {};
  const distPin = game.course ? distToPin() : 0;
  publishLiveState(code, {
    hole: def.id ?? (game.holeIdx + 1),
    par: def.par ?? null,
    yards: def.cardYards ?? null,
    hole_name: def.name ?? null,
    stroke: game.strokes,
    to_par: totalToPar(),
    distance_to_pin_yards: Math.round(distPin * 1.09361),
    sim_state: game.state,
    ...extra,
  });
}

function setHolePickerActive(idx) {
  if (holePicker) holePicker.value = String(idx);
  holeGrid?.querySelectorAll('.hole-jump').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.holeIndex === String(idx));
  });
}

function jumpToHole(idx) {
  if (game.state === 'TITLE' || !assets) {
    setHolePickerActive(idx);
    return;
  }
  hud.toastHide();
  hud.summaryHide();
  hud.scorecardHide();
  startHole(idx);
}

// ---------- hole / shot setup ----------

function teeBallPos() {
  const t = game.course.teePos;
  return { x: t.x, y: t.y + 0.0214, z: t.z };
}

// ---------- multi-player roster / turn switching ----------

/** Called once when the phone starts a multi-player session (never for single-player). */
function ensurePlayers(names) {
  if (!Array.isArray(names) || names.length < 2) return;
  names.forEach((name, i) => {
    if (!game.players[i]) {
      const isActive = i === game.activePlayerIdx;
      game.players[i] = {
        name,
        ballPos: isActive && game.ballPos ? { ...game.ballPos } : (game.course ? teeBallPos() : null),
        lie: isActive ? game.lie : SURF.TEE,
        strokes: isActive ? game.strokes : 0,
        shotStart: isActive && game.shotStart ? { ...game.shotStart } : null,
        scores: courseHoles.map(() => null),
        holedOut: false,
      };
    } else {
      game.players[i].name = name;
    }
    if (i > 0) refreshGhostLabel(i, name);
  });
  if (game.players[game.activePlayerIdx]) hud.setPlayer(game.players[game.activePlayerIdx].name);
}

/** Swaps the live ball/lie/strokes/shotStart fields to the given player's own progress,
 *  saving the outgoing player's progress first. No-op for single-player sessions. */
function switchActivePlayer(idx, name) {
  if (idx == null || game.players.length < 2 || idx === game.activePlayerIdx) return;

  const outgoing = game.players[game.activePlayerIdx];
  if (outgoing) {
    outgoing.ballPos = { ...game.ballPos };
    outgoing.lie = game.lie;
    outgoing.strokes = game.strokes;
    outgoing.shotStart = game.shotStart ? { ...game.shotStart } : null;
    if (game.activePlayerIdx > 0) updateGhost(game.activePlayerIdx, outgoing.ballPos, !outgoing.holedOut);
  }

  let incoming = game.players[idx];
  if (!incoming) {
    incoming = game.players[idx] = {
      name: name || `Player ${idx + 1}`,
      ballPos: teeBallPos(),
      lie: SURF.TEE,
      strokes: 0,
      shotStart: null,
      scores: courseHoles.map(() => null),
      holedOut: false,
    };
  } else if (name && incoming.name !== name) {
    incoming.name = name;
  }
  if (idx > 0) refreshGhostLabel(idx, incoming.name);

  game.activePlayerIdx = idx;
  game.ballPos = { ...incoming.ballPos };
  game.lie = incoming.lie;
  game.strokes = incoming.strokes;
  game.shotStart = incoming.shotStart ? { ...incoming.shotStart } : null;

  if (idx > 0) updateGhost(idx, incoming.ballPos, false);
  ball.visible = true;
  ball.position.set(game.ballPos.x, game.ballPos.y, game.ballPos.z);
  hud.setPlayer(incoming.name);
}

function startHole(idx) {
  pitchMarks.clear();
  if (rangeMarkers) { rangeMarkers.forEach(m => scene.remove(m)); rangeMarkers = null; }
  game.isRange = false;
  rangePanel?.classList.add('hidden');
  document.getElementById('range-pill')?.classList.add('hidden');
  if (idx === 0) game.scores = courseHoles.map(() => null);
  if (game.course) {
    scene.remove(game.course.group);
    game.course.dispose();
  }
  game.holeIdx = idx;
  const def = courseHoles[idx];
  setHolePickerActive(idx);
  holePickerCard?.classList.remove('hidden');
  game.course = buildCourse(def, assets);
  scene.add(game.course.group);

  game.strokes = 0;
  hud.shotDataHide();
  game.ballPos = teeBallPos();
  game.lie = SURF.TEE;

  // Multi-player: every player starts the new hole fresh at the tee, and none has holed out
  // yet. Ghosts from the previous hole are hidden until each player is swapped away again.
  game.players.forEach((p, i) => {
    if (!p) return;
    p.ballPos = { ...game.ballPos };
    p.lie = SURF.TEE;
    p.strokes = 0;
    p.shotStart = null;
    p.holedOut = false;
    if (i > 0) updateGhost(i, p.ballPos, false);
  });
  game.activePlayerIdx = 0;
  if (game.players.length > 0) hud.setPlayer(game.players[0]?.name ?? 'You');

  // wind
  const ang = Math.random() * Math.PI * 2;
  const spd = Math.random() * def.windMax;
  game.wind = { x: Math.sin(ang) * spd, z: Math.cos(ang) * spd, speed: spd };

  tracerCount = 0;
  tracerGeo.setDrawRange(0, 0);

  const yds = fmtYards(holeLength(def));
  hud.setHole(def.id, def.par, yds, def.name);
  hud.setStroke(1, totalToPar());
  hud.mapSetHole(def, idx);
  hud.show();

  // flyover
  game.state = 'FLYOVER';
  game.flyT = 0;
  hud.introShow(def.id, def.name, def.par, yds);
  ball.visible = false;
  blob.visible = false;
  setGuides(false);

  pushLiveState({ stroke: 1, last_shot: null, sim_state: 'NEW_HOLE' });
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
  hud.setPin(rem, game.course.heightAt(pin.x, pin.z) - game.ballPos.y);
  if (game.isRange) {
    const pinNum = document.getElementById('pin-num');
    const pinLabel = document.getElementById('pin-label');
    if (pinNum) pinNum.textContent = '0';
    if (pinLabel) pinLabel.textContent = 'CARRY';
  }
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

  // flyer lie: grass trapped between face and ball kills spin and the
  // shot comes out hot — a classic flyer from the rough (~1 in 3)
  const flyer = game.lie === SURF.ROUGH && !c.putter && Math.random() < 0.33;

  const speed = c.putter
    ? c.speed * power * (game.lie === SURF.GREEN || game.lie === SURF.FRINGE ? 1 : 0.55)
    : c.speed * (0.3 + 0.7 * power) * lie.speed * jitter * (flyer ? 1.06 : 1);
  const launchDeg = c.putter ? 0 : c.launch + (game.lie === SURF.ROUGH ? 1.5 : 0);
  const backspinRpm = c.putter ? 0
    : c.spin * lie.spin * (0.55 + 0.45 * power) * (flyer ? 0.6 : 1);

  // gusts: the hole wind is the average; each shot flies through a gust
  // sampled around it (±15%)
  const gust = 0.85 + Math.random() * 0.30;
  const shotWind = { x: game.wind.x * gust, z: game.wind.z * gust };

  const sideDeg = pushRad * 180 / Math.PI;
  if (c.putter) {
    hud.shotDataHide();
  } else {
    hud.shotDataShow({
      speedMph: speed * 2.237,
      clubMph: c.smash ? speed * 2.237 / c.smash : null,
      launchDeg,
      sideDeg,
      spinRpm: backspinRpm,
    });
    if (flyer) hud.toast('<span class="t-gold">FLYER LIE</span><span class="t-sub">JUMPING OUT HOT — LESS SPIN</span>', 1800);
  }
  if (game.isRange && !c.putter) {
    lastRangeShot = { speedMph: speed * 2.237, launchDeg, spinRpm: backspinRpm, apexFt: 0 };
    document.getElementById('range-pill')?.classList.add('hidden');
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
    wind: shotWind,
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
    const result = recordRangeShot({
      carry,
      total,
      finalX: sim.pos.x,
      finalZ: sim.pos.z,
      clubName: club().name,
    });
    if (!club().putter) {
      hud.shotDataResult(fmtYards(carry), fmtYards(total), {
        descentDeg: sim.descentDeg,
        offlineM: result.offline,
        hangTime: sim.hangTime,
      });
    }
    // populate last-shot pill
    const rangePill = document.getElementById('range-pill');
    if (rangePill) {
      const rs = lastRangeShot || {};
      const carryYd = fmtYards(carry), totalYd = fmtYards(total);
      rangePill.innerHTML =
        `<span class="rp-hi">${carryYd}</span><span class="rp-lo">y carry</span>` +
        ` · <span class="rp-hi">${totalYd}</span><span class="rp-lo">y total</span>` +
        ` · <span class="rp-hi">${Math.round(Math.abs(result.offline) * 1.09361)}</span><span class="rp-lo">y ${result.offline < 0 ? 'left' : 'right'}</span>` +
        (rs.speedMph > 0 ? ` · <span class="rp-hi">${Math.round(rs.speedMph)}</span><span class="rp-lo">mph</span>` : '') +
        (rs.launchDeg > 0 ? ` · <span class="rp-hi">${Number(rs.launchDeg).toFixed(1)}°</span><span class="rp-lo">launch</span>` : '') +
        (rs.spinRpm > 0 ? ` · <span class="rp-hi">${Math.round(rs.spinRpm).toLocaleString()}</span><span class="rp-lo">rpm</span>` : '') +
        (rs.apexFt > 0 ? ` · <span class="rp-hi">${Math.round(rs.apexFt)}</span><span class="rp-lo">ft apex</span>` : '');
      rangePill.classList.remove('hidden');
    }

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

  if (sim.state !== 'fly' && sim.state !== 'roll' && tracerCount > 8 && !game.lastFlight?.fresh) {
    // Keep the finished flight for instant replay (R).
    game.lastFlight = { pts: tracerPts.slice(0, tracerCount * 3), n: tracerCount, fresh: true };
    // A real carry onto the putting surface leaves a pitch mark.
    const cp = sim.carryPos;
    if (cp && game.course.surfaceAt(cp.x, cp.z) === SURF.GREEN) addPitchMark(cp.x, cp.z);
  }

  if (sim.state === 'holed') {
    const def = courseHoles[game.holeIdx];
    const active = game.players[game.activePlayerIdx];
    if (active) {
      active.scores[game.holeIdx] = game.strokes;
      active.holedOut = true;
      active.ballPos = { ...game.ballPos };
      active.strokes = game.strokes;
    } else {
      game.scores[game.holeIdx] = game.strokes;
    }

    // Multi-player: wait for every player to hole out before advancing the group to the next
    // tee. Treats a missing slot as "still playing" too, since a configured player who hasn't
    // taken a shot yet this hole would otherwise be silently skipped.
    const stillWaiting = game.players.length > 1 && game.players.some(p => !p || !p.holedOut);
    if (stillWaiting) {
      hud.toast(
        `<span class="t-gold">${scoreName(game.strokes, def.par)}</span>` +
        `<span class="t-sub">${(active?.name ?? 'YOU').toUpperCase()} · ${game.strokes} STROKES · WAITING FOR OTHERS</span>`, 0);
      game.state = 'WAITING_OTHERS';
      pushLiveState({ sim_state: 'HOLED', result: scoreName(game.strokes, def.par) });
      return;
    }

    hud.toast(
      `<span class="t-gold">${scoreName(game.strokes, def.par)}</span>` +
      `<span class="t-sub">HOLE ${def.id} · ${game.strokes} STROKES</span>`, 0);
    game.state = 'HOLE_DONE';
    game.doneTimer = 0;
    pushLiveState({ sim_state: 'HOLED', result: scoreName(game.strokes, def.par) });
    return;
  }

  if (sim.state === 'water') {
    game.strokes += 1; // penalty
    // drop at the last dry point along the flight
    let drop = game.shotStart;
    for (let i = tracerCount - 1; i >= 0; i--) {
      const x = tracerPts[i * 3], z = tracerPts[i * 3 + 2];
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

  if (!club().putter) {
    // offline: signed lateral miss vs the aim line at address
    const right = { x: -game.aimDir.z, z: game.aimDir.x };
    const offline = (game.ballPos.x - game.shotStart.x) * right.x
                  + (game.ballPos.z - game.shotStart.z) * right.z;
    hud.shotDataResult(fmtYards(carry), fmtYards(total), {
      descentDeg: sim.descentDeg,
      offlineM: offline,
      hangTime: sim.hangTime,
    });
  }

  if (!club().putter && total > 15) {
    hud.toast(
      `<span class="t-gold">${fmtYards(carry)}y</span> CARRY · ${fmtYards(total)}y TOTAL` +
      `<span class="t-sub">${game.lie.toUpperCase()}</span>`, 2800);
  }
  setupShot();
  pushLiveState({
    last_shot: {
      carryYards: Math.round(carry * 1.09361),
      totalYards: Math.round(total * 1.09361),
      lie: game.lie,
    },
  });
}

function nextHole() {
  hud.toastHide();
  if (game.holeIdx + 1 < courseHoles.length) {
    startHole(game.holeIdx + 1);
  } else {
    game.state = 'ROUND_DONE';
    hud.summaryShow(courseHoles, game.scores);
    // Round-results sync: hand the finished scorecard to the paired phone so
    // the app can enrich its saved session with the real round.
    if (liveCode) {
      const holes = courseHoles.map((h, i) => ({ hole: h.id, par: h.par, strokes: game.scores[i] }));
      const played = holes.filter((h) => h.strokes != null);
      const total = played.reduce((a, h) => a + h.strokes, 0);
      const toPar = played.reduce((a, h) => a + (h.strokes - h.par), 0);
      publishLiveState(liveCode, {
        sim_state: 'ROUND_DONE',
        round_summary: {
          courseId: activeCourse.courseId,
          courseName: activeCourse.courseName,
          holes,
          totalStrokes: total,
          toPar,
          endedAt: new Date().toISOString(),
        },
      });
    }
  }
}

function resetRangeStats() {
  rangeStats = { shots: 0, totalCarry: 0, bestCarry: 0, recent: [] };
  lastRangeShot = null;
  updateRangePanel();
}

function updateRangePanel(result = null) {
  if (!rangePanel) return;
  const setText = (id, text) => {
    const el = document.getElementById(id);
    if (el) el.textContent = text;
  };
  setText('range-shot-count', `${rangeStats.shots} shot${rangeStats.shots === 1 ? '' : 's'}`);
  setText('range-carry', result ? `${fmtYards(result.carry)}y` : '—');
  setText('range-total', result ? `${fmtYards(result.total)}y` : '—');
  setText('range-offline', result ? `${Math.round(Math.abs(result.offline) * 1.09361)}y ${result.offline < 0 ? 'L' : 'R'}` : '—');
  setText('range-apex', result?.apexFt ? `${Math.round(result.apexFt)} ft` : '—');
  setText('range-avg', rangeStats.shots ? `${fmtYards(rangeStats.totalCarry / rangeStats.shots)}y` : '—');
  setText('range-best', rangeStats.bestCarry ? `${fmtYards(rangeStats.bestCarry)}y` : '—');
  const history = document.getElementById('range-history');
  if (history) {
    history.innerHTML = rangeStats.recent
      .map((shot) => `<span title="${shot.club} · ${Math.round(Math.abs(shot.offline) * 1.09361)}y ${shot.offline < 0 ? 'L' : 'R'}">${fmtYards(shot.carry)}</span>`)
      .join('');
  }
}

function recordRangeShot({ carry, total, finalX, finalZ, clubName }) {
  const right = { x: -game.aimDir.z, z: game.aimDir.x };
  const dx = finalX - game.shotStart.x;
  const dz = finalZ - game.shotStart.z;
  const offline = dx * right.x + dz * right.z;
  const apexFt = lastRangeShot?.apexFt || 0;
  const result = { carry, total, offline, apexFt, club: clubName };
  rangeStats.shots += 1;
  rangeStats.totalCarry += carry;
  rangeStats.bestCarry = Math.max(rangeStats.bestCarry, carry);
  rangeStats.recent = [result, ...rangeStats.recent].slice(0, 12);
  updateRangePanel(result);
  return result;
}

function makeRangeLabel(text, color = '#f3ead4') {
  const canvas = document.createElement('canvas');
  canvas.width = 256;
  canvas.height = 92;
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = 'rgba(8, 14, 10, 0.72)';
  ctx.strokeStyle = 'rgba(201, 168, 106, 0.55)';
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.roundRect(10, 10, 236, 72, 10);
  ctx.fill();
  ctx.stroke();
  ctx.font = '700 34px Rajdhani, sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = color;
  ctx.fillText(text, 128, 46);
  const tex = new THREE.CanvasTexture(canvas);
  tex.anisotropy = 4;
  const sprite = new THREE.Sprite(new THREE.SpriteMaterial({
    map: tex,
    transparent: true,
    depthWrite: false,
  }));
  sprite.scale.set(11, 4, 1);
  return sprite;
}

function addRangeLine(points, color, opacity = 0.38) {
  const geo = new THREE.BufferGeometry().setFromPoints(points.map((p) => new THREE.Vector3(p.x, p.y, p.z)));
  const line = new THREE.Line(
    geo,
    new THREE.LineBasicMaterial({ color, transparent: true, opacity, depthWrite: false }),
  );
  scene.add(line);
  rangeMarkers.push(line);
  return line;
}

function addRangeDisc(x, z, radius, color, opacity = 0.22) {
  const y = game.course.heightAt(x, z) + 0.075;
  const disc = new THREE.Mesh(
    new THREE.CircleGeometry(radius, 64),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity, depthWrite: false, side: THREE.DoubleSide }),
  );
  disc.rotation.x = -Math.PI / 2;
  disc.position.set(x, y, z);
  scene.add(disc);
  rangeMarkers.push(disc);

  const ring = new THREE.Mesh(
    new THREE.TorusGeometry(radius, 0.14, 8, 72),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity: Math.min(opacity + 0.32, 0.72), depthWrite: false }),
  );
  ring.rotation.x = -Math.PI / 2;
  ring.position.set(x, y + 0.02, z);
  scene.add(ring);
  rangeMarkers.push(ring);
  return disc;
}

function addRangeFlag(x, z, color = 0xf2e6c9) {
  const y = game.course.heightAt(x, z);
  const group = new THREE.Group();
  const pole = new THREE.Mesh(
    new THREE.CylinderGeometry(0.035, 0.035, 3.2, 8),
    new THREE.MeshLambertMaterial({ color: 0xf2eee1 }),
  );
  pole.position.y = 1.6;
  const flag = new THREE.Mesh(
    new THREE.PlaneGeometry(0.9, 0.45),
    new THREE.MeshLambertMaterial({ color, side: THREE.DoubleSide }),
  );
  flag.position.set(0.45, 2.8, 0);
  group.add(pole, flag);
  group.position.set(x, y + 0.05, z);
  scene.add(group);
  rangeMarkers.push(group);
}

function startRange() {
  if (rangeMarkers) { rangeMarkers.forEach(m => scene.remove(m)); rangeMarkers = null; }
  game.isRange = true;
  resetRangeStats();
  rangePanel?.classList.remove('hidden');
  holePickerCard?.classList.add('hidden');
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
  hud.mapSetCourse([RANGE], null);
  hud.mapSetHole(RANGE, 0);
  hud.show();
  // override hole card for range
  const hcHole = document.getElementById('hc-hole');
  const hcPar  = document.getElementById('hc-par');
  const hcYds  = document.getElementById('hc-yds');
  const hcName = document.getElementById('hc-name');
  if (hcHole) hcHole.textContent = 'RANGE';
  if (hcPar)  hcPar.textContent  = 'PRACTICE';
  if (hcYds)  hcYds.textContent  = 'TARGETS';
  if (hcName) hcName.textContent = 'PRACTICE FACILITY';
  const helpStrip = document.getElementById('help-strip');
  if (helpStrip && window.__liveMode) {
    helpStrip.textContent = 'RANGE · SWING here or hit shots on your phone · V MAP · M MUTE';
  } else if (helpStrip) {
    helpStrip.textContent = 'RANGE · TARGET FIELD — drag to aim · V MAP · M MUTE';
  }
  setupShot();
  buildRangeMarkers();
}

function buildRangeMarkers() {
  rangeMarkers = [];
  const yardages = [50, 75, 100, 125, 150, 175, 200, 225, 250, 275, 300, 325, 350];
  const ox = game.course.teePos.x, oz = game.course.teePos.z;

  for (const x of [-75, -50, -25, 25, 50, 75]) {
    addRangeLine([
      { x: ox + x, y: game.course.heightAt(ox + x, oz + 30) + 0.08, z: oz + 30 },
      { x: ox + x, y: game.course.heightAt(ox + x, oz + 365) + 0.08, z: oz + 365 },
    ], x === -25 || x === 25 ? 0xd6c889 : 0xffffff, x === -25 || x === 25 ? 0.24 : 0.15);
  }

  for (const yd of yardages) {
    const dist = yd * 0.9144;
    const mz = oz + dist, mx = ox;
    const my = game.course.heightAt(mx, mz) + 0.07;
    const isHundred = yd % 100 === 0;
    addRangeLine([
      { x: ox - 85, y: game.course.heightAt(ox - 85, mz) + 0.08, z: mz },
      { x: ox + 85, y: game.course.heightAt(ox + 85, mz) + 0.08, z: mz },
    ], isHundred ? 0xd7c685 : 0xffffff, isHundred ? 0.28 : 0.12);
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
    if (yd % 50 === 0) {
      const label = makeRangeLabel(`${yd}y`, isHundred ? '#f8d978' : '#f2ead7');
      label.position.set(ox - 96, game.course.heightAt(ox - 96, mz) + 3.2, mz);
      scene.add(label);
      rangeMarkers.push(label);
    }
  }

  for (const target of RANGE.targets || []) {
    addRangeDisc(ox + target.x, oz + target.z, target.radius, target.color || 0xd7c685, 0.2);
    addRangeDisc(ox + target.x, oz + target.z, target.radius * 0.45, target.color || 0xd7c685, 0.32);
    addRangeFlag(ox + target.x, oz + target.z, target.color || 0xd7c685);
    const label = makeRangeLabel(`${target.yards}y`, '#fff3c9');
    label.position.set(ox + target.x, game.course.heightAt(ox + target.x, oz + target.z) + 5.2, oz + target.z);
    scene.add(label);
    rangeMarkers.push(label);
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


// Broadcast-crew camera hygiene: if a tree canopy sits on the camera->ball
// sightline, lift the camera until the line clears it instead of shooting
// through foliage.
function clearSightline(px, py, pz, tx, ty, tz) {
  const trees = game.course?.trees;
  if (!trees || !trees.length) return py;
  let y = py;
  for (let iter = 0; iter < 3; iter++) {
    let blocked = false;
    const dx = tx - px, dz = tz - pz;
    const len2 = dx * dx + dz * dz || 1;
    for (const t of trees) {
      const u = ((t.x - px) * dx + (t.z - pz) * dz) / len2;
      if (u <= 0.02 || u >= 0.98) continue;
      const cx = px + dx * u, cz = pz + dz * u;
      const d = Math.hypot(t.x - cx, t.z - cz);
      if (d > 3.2 * t.s + 1.5) continue;
      const canopyTop = t.h + (t.isPine ? 13.5 : 6.5) * t.s;
      const lineY = y + (ty - y) * u;
      if (lineY < canopyTop) { blocked = true; break; }
    }
    if (!blocked) break;
    y += 5;
  }
  return y;
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
      const gy = clearSightline(gx, game.course.heightAt(gx, gz) + 7.5, gz, pin.x, game.course.pinPos.y + 1, pin.z);
      game.greenCamPos = new THREE.Vector3(gx, gy, gz);
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
  let py = Math.max(sim.pos.y + 3.2, game.course.heightAt(px, pz) + 2.2);
  py = clearSightline(px, py, pz, sim.pos.x, sim.pos.y, sim.pos.z);
  camSet(px, py, pz, sim.pos.x, sim.pos.y, sim.pos.z, false, 2.6, 8);
}

function flyoverCamera() {
  const def = courseHoles[game.holeIdx];
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
  // Phone pairing is optional: the 3-click swing always works in the browser,
  // and live shots from a paired phone feed in on top via fireLiveShot().
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

// Map an app club name (e.g. "7 Iron", "SW") to a CLUBS index.
function matchClubByName(name) {
  if (!name) return -1;
  const n = name.trim().toUpperCase().replace(/\s+/g, ' ');
  let idx = CLUBS.findIndex(c => c.name === n);
  if (idx >= 0) return idx;
  idx = CLUBS.findIndex(c => c.id === n);
  if (idx >= 0) return idx;
  if (n.includes('DRIVER') || n === 'DR') return 0;
  if ((n.includes('3') && n.includes('WOOD')) || n === 'W3') return 1;
  if ((n.includes('5') && n.includes('WOOD')) || n === 'W5') return 2;
  if (n.includes('HYBRID') || n === 'HY') return 3;
  if ((n.includes('4') && n.includes('IRON')) || n === 'I4') return 4;
  if ((n.includes('5') && n.includes('IRON')) || n === 'I5') return 5;
  if ((n.includes('6') && n.includes('IRON')) || n === 'I6') return 6;
  if ((n.includes('7') && n.includes('IRON')) || n === 'I7') return 7;
  if ((n.includes('8') && n.includes('IRON')) || n === 'I8') return 8;
  if ((n.includes('9') && n.includes('IRON')) || n === 'I9') return 9;
  if (n.includes('PITCH') || n === 'PW' || n === 'P WEDGE') return 10;
  if (n.includes('GAP') || n.includes('APPROACH') || n === 'GW' || n === 'AW') return 11;
  if (n.includes('SAND') || n === 'SW' || n === 'S WEDGE') return 12;
  if (n.includes('PUTT') || n === 'PT') return 13;
  return -1;
}

function rotateAim(ang) {
  const { x, z } = game.aimDir;
  const c = Math.cos(ang), s = Math.sin(ang);
  game.aimDir = { x: x * c + z * s, z: -x * s + z * c };
  updateGuides();
  refreshClubHud();
}

function changeClub(delta) {
  // club can be changed in the browser even when a phone is paired
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
      hud.scorecardToggle(courseHoles, game.scores);
      break;
    case 'KeyV':
      e.preventDefault();
      hud.mapToggleMode();
      SFX.tick();
      break;
    case 'KeyM':
      SFX.setMuted(!SFX.isMuted());
      break;
    case 'KeyR':
      if (game.state === 'AIM' || game.state === 'HOLE_DONE') startReplay();
      break;
    default: break;
  }
});
window.addEventListener('keyup', (e) => { keys[e.code] = false; });

hud.el.clubPrev.addEventListener('click', (e) => { e.stopPropagation(); changeClub(-1); });
hud.el.clubNext.addEventListener('click', (e) => { e.stopPropagation(); changeClub(1); });
hud.el.mapToggle?.addEventListener('click', (e) => {
  e.stopPropagation();
  hud.mapToggleMode();
  SFX.tick();
});
holePicker?.addEventListener('change', () => {
  const idx = Math.max(0, Math.min(Number(holePicker.value) || 0, courseHoles.length - 1));
  jumpToHole(idx);
});
holeGrid?.addEventListener('click', (e) => {
  const btn = e.target.closest('.hole-jump');
  if (!btn) return;
  e.stopPropagation();
  const idx = Math.max(0, Math.min(Number(btn.dataset.holeIndex) || 0, courseHoles.length - 1));
  jumpToHole(idx);
});
courseSelect?.addEventListener('change', () => {
  const chosen = getSelectableCourse(courseSelect.value);
  if (!chosen?.holes?.length) return;
  setActiveCourse(chosen);
  if (game.state !== 'TITLE') {
    assetsReady.then(() => startHole(0));
  }
});
hud.el.btnStart.addEventListener('click', () => {
  if (!assets) return;
  SFX.unlock();
  const idx = holePicker ? Math.max(0, Math.min(Number(holePicker.value) || 0, courseHoles.length - 1)) : 0;
  startCourseRound(activeCourse.courseId, idx);
});
hud.el.btnAgain.addEventListener('click', () => {
  SFX.unlock();
  hud.summaryHide();
  game.scores = courseHoles.map(() => null);
  startHole(0);
});

// ---------- per-frame update ----------

let frameDt = 1 / 60;
const clock = new THREE.Clock();

function pushTracer(p) {
  if (tracerCount >= TRACER_MAX) return;
  tracerPts[tracerCount * 3] = p.x;
  tracerPts[tracerCount * 3 + 1] = p.y;
  tracerPts[tracerCount * 3 + 2] = p.z;
  tracerCount++;
  tracerRepaint();
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


function startReplay() {
  const f = game.lastFlight;
  if (!f || f.n < 8 || game.state === 'REPLAY') return;
  f.fresh = false;
  game.replay = { t: 0, prevState: game.state };
  game.state = 'REPLAY';
  replayBall.visible = true;
  hud.toast('<span class="t-gold">REPLAY</span>', 1200);
  SFX.tick();
}

function updateReplay() {
  const f = game.lastFlight;
  const r = game.replay;
  if (!f || !r) { game.state = 'AIM'; return; }
  r.t += frameDt;
  const idx = Math.min(r.t * 60, f.n - 1);       // points were pushed per frame
  const i0 = Math.floor(idx);
  const i1 = Math.min(i0 + 1, f.n - 1);
  const u = idx - i0;
  const bx = f.pts[i0 * 3] + (f.pts[i1 * 3] - f.pts[i0 * 3]) * u;
  const by = f.pts[i0 * 3 + 1] + (f.pts[i1 * 3 + 1] - f.pts[i0 * 3 + 1]) * u;
  const bz = f.pts[i0 * 3 + 2] + (f.pts[i1 * 3 + 2] - f.pts[i0 * 3 + 2]) * u;
  replayBall.position.set(bx, by, bz);

  // Side-on broadcast frame: perpendicular to the flight line, wide enough
  // to hold the whole arc, lifted above the apex.
  const sx = f.pts[0], sz = f.pts[2];
  const ex = f.pts[(f.n - 1) * 3], ez = f.pts[(f.n - 1) * 3 + 2];
  const mx = (sx + ex) / 2, mz = (sz + ez) / 2;
  const dx = ex - sx, dz = ez - sz;
  const L = Math.hypot(dx, dz) || 1;
  let apex = 0;
  for (let i = 0; i < f.n; i++) apex = Math.max(apex, f.pts[i * 3 + 1]);
  // Tower-cam framing: tree-lined corridors are only ~35m wide, so a wide
  // perpendicular camera lands inside the pines. Instead sit INSIDE the
  // corridor — behind the flight midpoint, nudged to the clearer side, and
  // above the apex looking down the line (Augusta tower-camera style).
  const side = Math.min(15, Math.max(9, L * 0.12));
  const back = Math.min(60, Math.max(18, L * 0.3));
  const clearance = (cx2, cz2) => {
    let d = 1e9;
    for (const t of game.course.trees || []) {
      d = Math.min(d, Math.hypot(t.x - cx2, t.z - cz2));
      if (d < 2) break;
    }
    return d;
  };
  const baseX = mx - (dx / L) * back;
  const baseZ = mz - (dz / L) * back;
  const aX = baseX - (dz / L) * side, aZ = baseZ + (dx / L) * side;
  const bX = baseX + (dz / L) * side, bZ = baseZ - (dx / L) * side;
  const useA = clearance(aX, aZ) >= clearance(bX, bZ);
  const px = useA ? aX : bX;
  const pz = useA ? aZ : bZ;
  const py = Math.max(apex * 0.85 + 8, game.course.heightAt(px, pz) + 6);
  camSet(px, clearSightline(px, py, pz, bx, by, bz), pz, bx, by, bz, false, 3.5, 5);

  if (idx >= f.n - 1) {
    r.hold = (r.hold || 0) + frameDt;
    if (r.hold > 0.8) {
      replayBall.visible = false;
      game.state = r.prevState === 'REPLAY' ? 'AIM' : r.prevState;
      game.replay = null;
    }
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
    else if (ev.type === 'tree') {
      if (ev.graze) {
        SFX.bounce(2);
        hud.toast('<span class="t-sub">BRUSH</span>', 900);
      } else {
        SFX.bounce(4);
        hud.toast('<span class="t-sub">TREE</span>', 1100);
      }
    }
  }

  ball.position.set(sim.pos.x, sim.pos.y, sim.pos.z);
  pushTracer(sim.pos);

  if (game.isRange) {
    const pinNum = document.getElementById('pin-num');
    const pinLabel = document.getElementById('pin-label');
    if (pinNum && pinLabel) {
      const d = Math.hypot(sim.pos.x - game.shotStart.x, sim.pos.z - game.shotStart.z);
      pinNum.textContent = fmtYards(d);
      pinLabel.textContent = sim.carryPos ? 'TOTAL' : 'CARRY';
    }
  } else {
    hud.setPin(Math.hypot(sim.pos.x - game.course.pinPos.x, sim.pos.z - game.course.pinPos.z));
  }

  const alt = sim.pos.y - game.shotGroundY;
  if (alt > game.shotApex) {
    game.shotApex = alt;
    if (!club().putter) hud.shotDataApex(game.shotApex * 3.28084);
    if (lastRangeShot) lastRangeShot.apexFt = game.shotApex * 3.28084;
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
      case 'REPLAY':
        updateReplay();
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
  if (composer) composer.render();
  else renderer.render(scene, camera);
}

frame();

// ---------- course selector ----------
// Hoist liveCode here so the course-selector guard below can reference it.
const liveCode = getLiveCode();

// Notify parent (website host/course-builder tool) that the sim runtime is ready.
notifyParent('SIM_READY', {
  courses: selectableCourses.map((course) => ({
    courseId: course.courseId,
    courseName: course.courseName,
  })),
});

// postMessage preview mode: course-builder sends PREVIEW_HOLE with custom holes array.
window.addEventListener('message', (e) => {
  // Play page tells the sim to start. Works from any state (course switching).
  if (e.data?.type === 'START_SIM') {
    assetsReady.then(() => {
      startCourseRound(e.data.courseId || activeCourse.courseId, e.data.holeIndex || 0);
    });
    return;
  }

  if (e.data?.type === 'START_RANGE') {
    assetsReady.then(() => {
      startPracticeRange();
    });
    return;
  }

  // Play page is ending the session (user exited on the laptop) — flag the
  // shared live state so a paired phone knows the round is over.
  if (e.data?.type === 'END_SESSION') {
    if (liveCode) publishLiveState(liveCode, { sim_state: 'ENDED' });
    return;
  }

  if (!e.data || e.data.type !== 'PREVIEW_HOLE') return;
  const { holes, holeIndex = 0 } = e.data;
  if (!holes?.length) return;

  setActiveCourse({ courseId: 'preview', courseName: 'Preview Course', holes, world: {} });

  // If assets aren't ready, wait for them.
  assetsReady.then(() => {
    hud.titleHide();
    startHole(Math.min(holeIndex, courseHoles.length - 1));
    // Skip straight to AIM (bypass flyover) in preview mode.
    game.flyT = 99;
  });
});

assetsReady.then(() => {
  if (urlLaunchHandled) return;
  if (launchMode === 'range') {
    urlLaunchHandled = true;
    startPracticeRange();
    return;
  }
  if (launchMode === 'course') {
    urlLaunchHandled = true;
    startCourseRound(launchCourseId, launchParams.get('hole') || 0);
  }
});

// Load real courses from Supabase and append them after local/dev courses.
const isPreview = new URLSearchParams(location.search).has('preview');
if (!isPreview && !liveCode && !launchMode) {
  fetchSimCourses().then(courses => {
    if (!courses.length) return;
    const seen = new Set(selectableCourses.map((course) => course.courseId));
    selectableCourses = [
      ...selectableCourses,
      ...courses.filter((course) => course?.holes?.length && !seen.has(course.courseId)),
    ];
    populateCourseSelect();
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
  if (helpStrip) helpStrip.textContent = 'SWING here or hit shots on your phone · V MAP · TAB CARD · M MUTE';

  // Phone is optional — no blocking "waiting for phone" overlay. A paired phone
  // simply feeds shots in; the browser swing works the whole time.

  // Disable keyboard/pointer swing actions in live mode.
  const origAction = action;          // already defined above
  // eslint-disable-next-line no-global-assign
  window.__liveMode = true;

  // Persistent connection badge: shows the pairing code until a phone connects,
  // then flips to a live "phone connected" indicator.
  const liveBadge = document.getElementById('live-badge');
  let livePhoneConnected = false;
  function updateLiveBadge() {
    if (!liveBadge) return;
    if (livePhoneConnected) {
      liveBadge.innerHTML = '<span class="lb-dot"></span>PHONE CONNECTED';
      liveBadge.className = 'live-badge connected';
    } else {
      liveBadge.innerHTML = `<span class="lb-ico">📱</span>CODE <b>${liveCode}</b> · CONNECT YOUR PHONE`;
      liveBadge.className = 'live-badge';
    }
    liveBadge.classList.remove('hidden');
  }
  updateLiveBadge();

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


// Swing replay PiP: the phone sends a small composite of the real swing
// after each live shot; show it beside the flight for a few seconds.
function showSwingPip(b64) {
  let pip = document.getElementById('swing-pip');
  if (!pip) {
    pip = document.createElement('div');
    pip.id = 'swing-pip';
    pip.innerHTML = '<span class="swing-pip-label">YOUR SWING</span><img alt="Your swing replay">';
    document.body.appendChild(pip);
  }
  pip.querySelector('img').src = 'data:image/jpeg;base64,' + b64;
  pip.classList.add('show');
  clearTimeout(showSwingPip._t);
  showSwingPip._t = setTimeout(() => pip.classList.remove('show'), 9000);
}

  connectLive(liveCode,
    // onShotReceived
    function (metrics) {
      livePhoneConnected = true; updateLiveBadge();
      if (liveWaiting) liveWaiting.classList.add('hidden');
      const ready = game.state === 'AIM' || game.state === 'METER_POWER'
        || game.state === 'METER_ACCURACY' || game.state === 'WAITING_OTHERS';
      if (ready) {
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
      livePhoneConnected = true; updateLiveBadge();
      window.parent?.postMessage({ type: 'APP_CONNECTED' }, '*');
    },
    // onClubChanged — sync club selection from app
    function (clubName) {
      updateLiveClub(clubName);
      const idx = matchClubByName(clubName);
      if (idx >= 0) {
        game.clubIdx = idx;
        refreshClubHud();
        if (game.state === 'AIM') updateGuides();
      }
    },
    // onSessionEnd — the paired phone left the live session
    function () {
      livePhoneConnected = false;
      updateLiveBadge();
      updateLiveStatus('Phone disconnected — re-enter the code on your phone', '');
      window.parent?.postMessage({ type: 'APP_DISCONNECTED' }, '*');
    },
    // onSwingImage — picture-in-picture of the player's real swing
    showSwingPip,
    // onPlayersReceived — multi-player roster, sent once at the start of a multi-player
    // session (single-player sessions never send this event).
    ensurePlayers
  );
}

/**
 * Fires a shot using metrics from the phone (live sim mode).
 * Bypasses the 3-click swing meter entirely.
 */
function fireLiveShot({ ballSpeedMph, vlaDegrees, backspinRpm, sidespinRpm, hlaDegrees, hlaDirection, playerIndex, playerName }) {
  if (!game.course) return;

  // Multi-player: swap in this shot's player's own ball/lie/strokes before firing, so it
  // continues from wherever THEIR ball actually rests (not whoever hit last). No-op for
  // single-player sessions or repeat shots by the same already-active player.
  switchActivePlayer(playerIndex, playerName);

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
  if (game.isRange) {
    lastRangeShot = { speedMph: ballSpeedMph, launchDeg: vlaDegrees || 12, spinRpm: Math.abs(backspinRpm || 0), apexFt: 0 };
    document.getElementById('range-pill')?.classList.add('hidden');
  }
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

// dev hooks: #range starts practice; #play skips title; #aim also skips flyover,
// an optional digit picks the hole (#aim2 = hole 2).
{
  const m = location.hash.match(/^#(range|play|aim)(\d{1,2})?$/);
  if (m) {
    assetsReady.then(() => {
      hud.titleHide();
      if (m[1] === 'range') {
        startRange();
        return;
      }
      startHole(m[2] ? Math.min(parseInt(m[2], 10) - 1, courseHoles.length - 1) : 0);
      if (m[1] === 'aim') { game.flyT = 99; }
    });
  }
}
