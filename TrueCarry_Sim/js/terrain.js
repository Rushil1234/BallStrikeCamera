// Course construction: a single analytic height/surface field per hole
// drives BOTH the rendered mesh and the physics, so what you see is what
// the ball plays off.
//
// Visuals: PBR texture splatting (real grass/rough/sand photos re-tinted by
// designed vertex colors), photo branch-card trees, reflective water, and a
// tree-line backdrop. Visual construction is gated on `document` + loaded
// assets so the field logic also runs headless (jsc/Node) for testing.

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js?v=gspro-14';
import { Water } from 'three/addons/objects/Water.js?v=gspro-14';
import { makeFbm, makeRng } from './noise.js?v=gspro-14';
import { SURF } from './physics.js?v=gspro-14';

const VISUAL = typeof document !== 'undefined';

const sstep = (e0, e1, x) => {
  const t = Math.min(Math.max((x - e0) / (e1 - e0), 0), 1);
  return t * t * (3 - 2 * t);
};
const lerp = (a, b, t) => a + (b - a) * t;

// ---------- shape helpers ----------

function ellipseVal(s, x, z) {
  const dx = x - s.cx, dz = z - s.cz;
  const c = Math.cos(s.rot || 0), sn = Math.sin(s.rot || 0);
  const lx = dx * c + dz * sn;
  const lz = -dx * sn + dz * c;
  return (lx / s.rx) ** 2 + (lz / s.rz) ** 2;
}

function distToPolyline(pts, x, z) {
  let best = Infinity, bestAlong = 0, along = 0;
  for (let i = 0; i < pts.length - 1; i++) {
    const ax = pts[i].x, az = pts[i].z, bx = pts[i + 1].x, bz = pts[i + 1].z;
    const abx = bx - ax, abz = bz - az;
    const L2 = abx * abx + abz * abz;
    const t = L2 ? Math.min(Math.max(((x - ax) * abx + (z - az) * abz) / L2, 0), 1) : 0;
    const px = ax + abx * t, pz = az + abz * t;
    const d = Math.hypot(x - px, z - pz);
    const segLen = Math.sqrt(L2);
    if (d < best) { best = d; bestAlong = along + segLen * t; }
    along += segLen;
  }
  return { dist: best, along: bestAlong, total: along };
}

function pointInPolygon(pts, x, z) {
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const pi = pts[i], pj = pts[j];
    const crosses = ((pi.z > z) !== (pj.z > z))
      && (x < (pj.x - pi.x) * (z - pi.z) / ((pj.z - pi.z) || 1e-9) + pi.x);
    if (crosses) inside = !inside;
  }
  return inside;
}

function inFeaturePolys(features, x, z) {
  for (const f of features || []) {
    if ((f.points?.length || 0) >= 3 && pointInPolygon(f.points, x, z)) return true;
  }
  return false;
}

function lineIntersectsBounds(points, bounds, pad = 0) {
  for (const p of points || []) {
    if (p.x >= bounds.minX - pad && p.x <= bounds.maxX + pad
      && p.z >= bounds.minZ - pad && p.z <= bounds.maxZ + pad) return true;
  }
  return false;
}

function elevationAtWorld(elevation, x, z) {
  if (!elevation?.values || !elevation.worldBounds) return null;
  const b = elevation.worldBounds;
  // Clamp instead of bailing: at 1:1 elevation a hard fallback outside the
  // grid becomes a cliff wall across any hole near the DEM edge.
  const cx2 = Math.min(b.maxX, Math.max(b.minX, x));
  const cz2 = Math.min(b.maxZ, Math.max(b.minZ, z));
  const u = (cx2 - b.minX) / ((b.maxX - b.minX) || 1) * (elevation.width - 1);
  const v = (cz2 - b.minZ) / ((b.maxZ - b.minZ) || 1) * (elevation.height - 1);
  const x0 = Math.floor(u), z0 = Math.floor(v);
  const x1 = Math.min(elevation.width - 1, x0 + 1);
  const z1 = Math.min(elevation.height - 1, z0 + 1);
  const tx = u - x0, tz = v - z0;
  const at = (gx, gz) => elevation.values[gz * elevation.width + gx];
  const a = lerp(at(x0, z0), at(x1, z0), tx);
  const c = lerp(at(x0, z1), at(x1, z1), tx);
  const meters = lerp(a, c, tz);
  if (!Number.isFinite(meters)) return null;
  return (meters - (elevation.base || 0)) * (elevation.scale || 0.42);
}

// ---------- splatted PBR ground material ----------
// vertex colors carry the designed hue (stripes, depth tints); the photo
// textures are normalized by their mean so they contribute structure only.

function splatMaterial(assets) {
  const g = assets.ground;
  const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1.0, metalness: 0 });
  // Grazing-angle sky reflection was washing open fairways to milk.
  mat.envMapIntensity = 0.22;
  mat.envMapIntensity = 0.3;   // tame grazing-angle sky reflection washout
  mat.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, {
      uGrassD: { value: g.grassD }, uGrassN: { value: g.grassN }, uGrassR: { value: g.grassR },
      uRoughD: { value: g.roughD }, uRoughN: { value: g.roughN }, uRoughR: { value: g.roughR },
      uSandD: { value: g.sandD }, uSandN: { value: g.sandN }, uSandR: { value: g.sandR },
      uGrassMean: { value: g.grassMean },
      uRoughMean: { value: g.roughMean },
      uSandMean: { value: g.sandMean },
      uTime: { value: 0 },
      uWindVec: { value: new THREE.Vector2(1, 0) },
    });
    mat.userData.shader = shader;
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', `#include <common>
        attribute vec4 splat;
        varying vec4 vSplat;
        varying vec3 vWPos;`)
      .replace('#include <begin_vertex>', `#include <begin_vertex>
        vSplat = splat;
        vWPos = (modelMatrix * vec4(transformed, 1.0)).xyz;`);
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', `#include <common>
        varying vec4 vSplat;
        varying vec3 vWPos;
        uniform sampler2D uGrassD, uGrassN, uGrassR, uRoughD, uRoughN, uRoughR, uSandD, uSandN, uSandR;
        uniform vec3 uGrassMean, uRoughMean, uSandMean;
        uniform float uTime;
        uniform vec2 uWindVec;
        vec2 uvFair() { return vWPos.xz * 0.27; }
        vec2 uvGreen() { return vWPos.xz * 0.9; }
        vec2 uvRough() { return vWPos.xz * 0.16; }
        vec2 uvSand() { return vWPos.xz * 0.55; }
        // Anti-tiling grass: a base tile broken up by a large-scale multiply
        // (kills the visible repeat) plus a fine octave for close-up blades.
        vec3 grassTex(vec2 uv) {
          vec3 base  = texture2D(uGrassD, uv).rgb;
          vec3 macro = texture2D(uGrassD, uv * 0.19 + 3.1).rgb;
          vec3 fine  = texture2D(uGrassD, uv * 3.4 + 0.7).rgb;
          vec3 detiled = base * macro * 2.0;
          return mix(detiled, detiled * fine * 1.7, 0.32) / uGrassMean;
        }
        vec3 roughTex(vec2 uv) {
          vec3 base  = texture2D(uRoughD, uv).rgb;
          vec3 macro = texture2D(uRoughD, uv * 0.21 + 5.3).rgb;
          return (base * macro * 2.0) / uRoughMean;
        }`)
      .replace('#include <color_fragment>', `#include <color_fragment>
        {
          vec3 gA = grassTex(uvFair());
          vec3 gB = grassTex(uvGreen());
          vec3 grassC = mix(gA, gB, vSplat.w);
          vec3 roughC = roughTex(uvRough());
          vec3 sandC  = texture2D(uSandD, uvSand()).rgb / uSandMean;
          vec3 structure = grassC * vSplat.x + roughC * vSplat.y + sandC * vSplat.z;
          // Manicured turf keeps more of its crisp texture; rough softens.
          float texAmt = mix(0.78, 0.92, vSplat.w);
          structure = mix(vec3(1.0), structure, texAmt);
          diffuseColor.rgb *= clamp(structure, 0.25, 1.9);

          // drifting cloud shadows
          vec2 cuv = vWPos.xz * 0.0011 + uWindVec * uTime * 0.0022 + vec2(0.0, uTime * 0.0006);
          float cn = texture2D(uRoughD, cuv).g * 0.62
                   + texture2D(uRoughD, cuv * 2.7 + 0.41).g * 0.38;
          diffuseColor.rgb *= 1.0 - 0.24 * smoothstep(0.48, 0.78, cn);
        }`)
      .replace('#include <roughnessmap_fragment>', `
        float roughnessFactor = roughness;
        {
          // Real micro-roughness per surface: tight-mown grass sheens in low
          // sun, sand and deep rough stay matte.
          float rG = texture2D(uGrassR, uvFair()).g;
          float rR = texture2D(uRoughR, uvRough()).g;
          float rS = texture2D(uSandR, uvSand()).g;
          float w = clamp(vSplat.x + vSplat.y + vSplat.z, 0.0, 1.0);
          float blended = rG * vSplat.x + rR * vSplat.y + rS * vSplat.z;
          blended = mix(blended, blended * 0.9, vSplat.w * vSplat.x);
          // Floor at 0.8: lower values let the sun's specular lobe paint a
          // huge bright veil across mid-distance fairways at grazing angles.
          roughnessFactor = mix(1.0, clamp(blended, 0.8, 1.0), w);
        }`)
      .replace('#include <normal_fragment_maps>', `
        {
          vec3 nT = texture2D(uGrassN, uvFair()).xyz * (vSplat.x * (1.0 - vSplat.w * 0.7))
                  + texture2D(uGrassN, uvGreen()).xyz * (vSplat.x * vSplat.w * 0.7)
                  + texture2D(uRoughN, uvRough()).xyz * vSplat.y
                  + texture2D(uSandN, uvSand()).xyz * vSplat.z;
          vec3 mapN = nT * 2.0 - 1.0;
          mapN.xy *= 1.18;
          mapN = normalize(mapN);
          vec3 eyePos = -vViewPosition;
          vec3 q0 = dFdx(eyePos);
          vec3 q1 = dFdy(eyePos);
          vec2 st0 = dFdx(uvFair());
          vec2 st1 = dFdy(uvFair());
          vec3 Nn = normalize(normal);
          vec3 Tt = normalize(q0 * st1.t - q1 * st0.t);
          vec3 Bb = -normalize(cross(Nn, Tt));
          normal = normalize(mat3(Tt, Bb, Nn) * mapN);
        }`);
  };
  return mat;
}

// ---------- branch-card trees ----------
// Trees are built the way games do it: a bark-textured trunk plus dozens of
// alpha-tested cards cut from real photographed branch textures.

// sub-rectangles of usable sprigs/clusters inside the Poly Haven atlases
const PINE_SPRIG = { u0: 0.030, v0: 0.550, u1: 0.225, v1: 0.985 };
const LEAF_RECT_A = { u0: 0.010, v0: 0.270, u1: 0.440, v1: 0.740 };
const LEAF_RECT_B = { u0: 0.040, v0: 0.005, u1: 0.420, v1: 0.460 };

function cardGeo(w, h, rect) {
  const g = new THREE.PlaneGeometry(w, h);
  g.translate(0, h / 2, 0);              // pivot at the stem
  const uv = g.attributes.uv;
  for (let i = 0; i < uv.count; i++) {
    uv.setXY(i,
      rect.u0 + uv.getX(i) * (rect.u1 - rect.u0),
      rect.v0 + uv.getY(i) * (rect.v1 - rect.v0));
  }
  return g;
}

const _m4 = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _eu = new THREE.Euler();
function placed(geo, px, py, pz, rx, ry, rz, s = 1) {
  const g = geo.clone();
  _eu.set(rx, ry, rz, 'YXZ');
  _q.setFromEuler(_eu);
  _m4.compose(new THREE.Vector3(px, py, pz), _q, new THREE.Vector3(s, s, s));
  g.applyMatrix4(_m4);
  return g;
}

function normalsUp(geo) {
  const n = geo.attributes.normal;
  for (let i = 0; i < n.count; i++) n.setXYZ(i, 0, 1, 0);
  return geo;
}

// Southern loblolly pine: a tall bare pole with an irregular crown in the top
// third only — the signature silhouette of Georgia parkland courses. The crown
// is built as a billowing ellipsoidal cloud of drooping fronds rather than a
// radial star of upward spikes, so it reads as a rounded 3D volume from the
// tee instead of a sparse dark blob.
function loblollyCanopy(seed, dense) {
  const rng = makeRng(seed);
  const sprig = cardGeo(3.2, 4.7, PINE_SPRIG);
  const cards = [];
  const CY = 12.1;                 // crown centre height
  const rH = 2.65, rV = 2.85;      // crown radii (horizontal / vertical)
  const N = dense ? 82 : 60;
  for (let i = 0; i < N; i++) {
    // point on an ellipsoid shell (surface-biased for a full silhouette, with
    // some interior fill so gaps don't punch through to sky)
    const az = rng() * Math.PI * 2;
    const el = Math.acos(1 - 2 * rng());        // uniform over the sphere
    const shell = 0.62 + 0.4 * rng();
    const se = Math.sin(el);
    const px = se * Math.cos(az) * rH * shell;
    const pz = se * Math.sin(az) * rH * shell;
    const py = CY + Math.cos(el) * rV * shell;
    // frond faces outward and droops down-and-out like real pine foliage
    const yaw = az + (rng() - 0.5) * 0.9;
    const pitch = -0.45 - rng() * 0.55;
    const s = (1.15 - 0.35 * shell) * (0.82 + rng() * 0.42);
    cards.push(placed(sprig, px, py, pz, pitch, yaw, (rng() - 0.5) * 0.6, s));
  }
  // a conical peak so the crown tapers to a pine tip, not a round ball
  cards.push(placed(sprig, 0, CY + rV + 0.35, 0, -0.2, rng() * Math.PI, 0, 0.95));
  cards.push(placed(sprig, 0, CY + rV + 0.1, 0, -0.22, rng() * Math.PI + 1.2, 0, 0.88));
  return bakeCanopyAO(normalsUp(mergeGeometries(cards)));
}

function bakeCanopyAO(geo) {
  // Fake self-occlusion: vertices toward the canopy interior darken. This is
  // what makes card foliage read as a volume instead of a paper cutout.
  geo.computeBoundingBox();
  const bb = geo.boundingBox;
  const c = bb.getCenter(new THREE.Vector3());
  const maxR = bb.getSize(new THREE.Vector3()).length() * 0.5 || 1;
  const pos = geo.attributes.position;
  const col = new Float32Array(pos.count * 3);
  for (let i = 0; i < pos.count; i++) {
    const dx = pos.getX(i) - c.x, dy = pos.getY(i) - c.y, dz = pos.getZ(i) - c.z;
    const r = Math.min(1, Math.hypot(dx, dy, dz) / maxR);
    const v = 0.74 + 0.26 * r;   // 0.58 floor read as burnt-black against the sun
    col[i * 3] = v; col[i * 3 + 1] = v; col[i * 3 + 2] = v;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  return geo;
}

function pineCanopy(seed, dense) {
  const rng = makeRng(seed);
  const sprig = cardGeo(2.5, 3.9, PINE_SPRIG);
  const cards = [];
  for (let y = 2.0; y <= 8.4; y += (dense ? 0.44 : 0.62)) {
    const t = (y - 2.0) / 6.4;
    const n = Math.round((dense ? 11 : 9) - 3.5 * t);
    const s = 1.3 - 0.65 * t;
    const ring = 0.2 + (1 - t) * 1.05;   // broad conic base tapering to a point
    for (let i = 0; i < n; i++) {
      const yaw = (i / n) * Math.PI * 2 + rng() * 1.2;
      const pitch = -(Math.PI / 2) + 0.34 + rng() * 0.24;  // fan out, slight droop
      const rad = ring * (0.45 + 0.6 * rng());
      cards.push(placed(sprig, Math.cos(yaw) * rad, y + (rng() - 0.5) * 0.3, Math.sin(yaw) * rad, pitch, yaw, 0, s * (0.85 + rng() * 0.3)));
    }
  }
  // upright crown
  cards.push(placed(sprig, 0, 8.4, 0, -0.06, rng() * Math.PI, 0, 0.9));
  cards.push(placed(sprig, 0, 8.35, 0, -0.06, rng() * Math.PI + Math.PI / 2, 0, 0.82));
  return bakeCanopyAO(normalsUp(mergeGeometries(cards)));
}

// Flowering dogwood: a small tiered understory tree with flat horizontal
// blossom layers. Wired via the parkland flora system and tinted white / pale
// pink per instance — Augusta's dogwoods bank the tree line with the azaleas.
function dogwoodCanopy(seed) {
  const rng = makeRng(seed);
  const a = cardGeo(3.0, 3.0, LEAF_RECT_A);
  const b = cardGeo(2.8, 2.8, LEAF_RECT_B);
  const cards = [];
  const layers = [
    { y: 3.9, r: 2.5, n: 9 },
    { y: 4.8, r: 2.1, n: 8 },
    { y: 5.5, r: 1.5, n: 6 },
    { y: 6.0, r: 0.8, n: 4 },
  ];
  for (const L of layers) {
    for (let i = 0; i < L.n; i++) {
      const az = (i / L.n) * Math.PI * 2 + rng() * 0.9;
      const r = L.r * (0.5 + 0.55 * rng());
      cards.push(placed(
        rng() < 0.5 ? a : b,
        Math.cos(az) * r, L.y + (rng() - 0.5) * 0.4, Math.sin(az) * r,
        (rng() - 0.72) * 0.5,          // near-flat, slight down-droop → tiered look
        rng() * Math.PI * 2,
        (rng() - 0.5) * 0.4,
        0.72 + rng() * 0.42,
      ));
    }
  }
  return bakeCanopyAO(normalsUp(mergeGeometries(cards)));
}

function leafCanopy(seed, dense) {
  const rng = makeRng(seed);
  const a = cardGeo(3.4, 3.4, LEAF_RECT_A);
  const b = cardGeo(3.1, 3.3, LEAF_RECT_B);
  const cards = [];
  const CY = 5.4;
  for (let i = 0; i < (dense ? 70 : 44); i++) {
    const az = rng() * Math.PI * 2;
    const elev = (rng() - 0.28) * 1.85;
    // bias radius toward the shell so the crown reads as a full rounded dome
    const r = 1.05 + Math.sqrt(rng()) * 1.75;
    const px = Math.cos(az) * Math.cos(elev) * r;
    const pz = Math.sin(az) * Math.cos(elev) * r;
    const py = CY + Math.sin(elev) * r * 0.82;
    cards.push(placed(
      rng() < 0.5 ? a : b,
      px, py - 1.4, pz,
      (rng() - 0.6) * 1.1, rng() * Math.PI * 2, (rng() - 0.5) * 0.7,
      0.8 + rng() * 0.5,
    ));
  }
  return bakeCanopyAO(normalsUp(mergeGeometries(cards)));
}

function trunkGeo(rTop, rBot, h, vRepeat) {
  const g = new THREE.CylinderGeometry(rTop, rBot, h, 8, 1, true);
  g.translate(0, h / 2, 0);
  const uv = g.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setY(i, uv.getY(i) * vRepeat);
  return g;
}

let _treeKit = null;
function treeKit(assets) {
  if (_treeKit) return _treeKit;
  const t = assets.trees;
  const swayShaders = [];
  // gentle wind sway: displace canopy vertices, phase keyed off the
  // instance's world position so the forest doesn't move in lockstep
  const addSway = (mat) => {
    mat.onBeforeCompile = (shader) => {
      shader.uniforms.uTime = { value: 0 };
      shader.uniforms.uWind = { value: 1 };
      swayShaders.push(shader);
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', `#include <common>
          uniform float uTime;
          uniform float uWind;`)
        .replace('#include <begin_vertex>', `#include <begin_vertex>
          {
            #ifdef USE_INSTANCING
              float ph = instanceMatrix[3].x * 0.73 + instanceMatrix[3].z * 1.11;
            #else
              float ph = 0.0;
            #endif
            float reach = max(transformed.y - 1.5, 0.0);
            float sway = sin(uTime * (0.9 + 0.25 * sin(ph)) + ph)
                       * (0.006 + 0.004 * uWind) * reach;
            transformed.x += sway;
            transformed.z += sway * 0.6;
            transformed.y += sin(uTime * 1.7 + ph * 1.3) * 0.008 * reach;
          }`);
    };
    return mat;
  };
  // Foliage cards are lit with a self-illumination floor keyed off their own
  // texture: pure Lambert renders every backlit / shadow-side leaf near-black
  // (the "black tree silhouette" look). Feeding the diffuse map back in as a
  // low-intensity emissive means leaves always keep their real green/brown, the
  // way sun-through-canopy scattering reads in real life — while the Lambert
  // term still adds directional highlights on the sunlit side.
  const canopyMat = (map, cut) => addSway(new THREE.MeshLambertMaterial({
    map, alphaTest: cut, side: THREE.DoubleSide, vertexColors: true,
    emissive: 0xffffff, emissiveMap: map, emissiveIntensity: 0.32,
  }));
  // Dogwood blossoms keep the self-illum floor idea, but with a flat pale-pink
  // emissive instead of the green leaf-card emissiveMap — otherwise the green
  // self-illum tints every blossom mint and no diffuse multiplier can whiten it.
  const dogwoodMat = () => addSway(new THREE.MeshLambertMaterial({
    map: t.leafCard, alphaTest: 0.4, side: THREE.DoubleSide, vertexColors: true,
    emissive: 0xf6e6ec, emissiveIntensity: 0.24,
  }));
  const depthMat = (map, cut) => new THREE.MeshDepthMaterial({
    depthPacking: THREE.RGBADepthPacking, map, alphaTest: cut,
  });
  _treeKit = {
    canopies: [
      { geo: pineCanopy(11), mat: canopyMat(t.pineCard, 0.52), depth: depthMat(t.pineCard, 0.52), trunk: 'pine' },
      { geo: pineCanopy(47), mat: canopyMat(t.pineCard, 0.52), depth: depthMat(t.pineCard, 0.52), trunk: 'pine' },
      { geo: leafCanopy(23), mat: canopyMat(t.leafCard, 0.4), depth: depthMat(t.leafCard, 0.4), trunk: 'leaf' },
      { geo: leafCanopy(89), mat: canopyMat(t.leafCard, 0.4), depth: depthMat(t.leafCard, 0.4), trunk: 'leaf' },
      { geo: loblollyCanopy(31), mat: canopyMat(t.pineCard, 0.52), depth: depthMat(t.pineCard, 0.52), trunk: 'pineTall' },
      { geo: loblollyCanopy(73), mat: canopyMat(t.pineCard, 0.52), depth: depthMat(t.pineCard, 0.52), trunk: 'pineTall' },
      // 6-8: dense near-LOD canopies for corridor trees (GSPro step 3b)
      { geo: pineCanopy(19, true), mat: canopyMat(t.pineCard, 0.52), depth: depthMat(t.pineCard, 0.52), trunk: 'pine' },
      { geo: leafCanopy(57, true), mat: canopyMat(t.leafCard, 0.4), depth: depthMat(t.leafCard, 0.4), trunk: 'leaf' },
      { geo: loblollyCanopy(91, true), mat: canopyMat(t.pineCard, 0.52), depth: depthMat(t.pineCard, 0.52), trunk: 'pineTall' },
      // 9: flowering dogwood (parkland flora only; tinted white/pink per instance)
      { geo: dogwoodCanopy(43), mat: dogwoodMat(), depth: depthMat(t.leafCard, 0.4), trunk: 'leaf' },
    ],
    trunks: {
      pine: { geo: trunkGeo(0.07, 0.30, 8.6, 3), mat: new THREE.MeshLambertMaterial({ map: t.pineBark }) },
      leaf: { geo: trunkGeo(0.14, 0.36, 4.8, 2), mat: new THREE.MeshLambertMaterial({ map: t.leafBark }) },
      pineTall: { geo: trunkGeo(0.10, 0.38, 14.4, 5), mat: new THREE.MeshLambertMaterial({ map: t.pineBark }) },
    },
    swayShaders,
  };
  return _treeKit;
}

// ---------- course field + meshes ----------

function islandPlateGeometry(bounds, y, seed = 1) {
  const cx = (bounds.minX + bounds.maxX) / 2;
  const cz = (bounds.minZ + bounds.maxZ) / 2;
  const rx = (bounds.maxX - bounds.minX) * 0.52;
  const rz = (bounds.maxZ - bounds.minZ) * 0.52;
  const seg = 128;
  const positions = new Float32Array((seg + 2) * 3);
  const indices = [];
  positions[0] = cx; positions[1] = y; positions[2] = cz;
  for (let i = 0; i <= seg; i++) {
    const a = (i / seg) * Math.PI * 2;
    const wobble = 1
      + Math.sin(a * 3.0 + seed * 0.01) * 0.035
      + Math.sin(a * 8.0 + seed * 0.017) * 0.025;
    const k = i + 1;
    positions[k * 3] = cx + Math.cos(a) * rx * wobble;
    positions[k * 3 + 1] = y;
    positions[k * 3 + 2] = cz + Math.sin(a) * rz * wobble;
    if (i < seg) indices.push(0, k, k + 1);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setIndex(indices);
  geo.computeVertexNormals();
  return geo;
}

function coastalPlateGeometry(bounds, coastline, y) {
  const pts = coastline?.land || [];
  if (!pts.length) return islandPlateGeometry(bounds, y, 17);
  const cx = pts.reduce((a, p) => a + p.x, 0) / pts.length;
  const cz = pts.reduce((a, p) => a + p.z, 0) / pts.length;
  const positions = new Float32Array((pts.length + 1) * 3);
  const indices = [];
  positions[0] = cx; positions[1] = y; positions[2] = cz;
  pts.forEach((p, i) => {
    const k = i + 1;
    positions[k * 3] = p.x;
    positions[k * 3 + 1] = y;
    positions[k * 3 + 2] = p.z;
    indices.push(0, k, i === pts.length - 1 ? 1 : k + 1);
  });
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setIndex(indices);
  geo.computeVertexNormals();
  return geo;
}

function lakePlateGeometry(water, y) {
  const seg = 96;
  const positions = new Float32Array((seg + 2) * 3);
  const indices = [];
  const c = Math.cos(water.rot || 0), s = Math.sin(water.rot || 0);
  positions[0] = water.cx; positions[1] = y; positions[2] = water.cz;
  for (let i = 0; i <= seg; i++) {
    const a = (i / seg) * Math.PI * 2;
    const lx = Math.cos(a) * water.rx;
    const lz = Math.sin(a) * water.rz;
    const k = i + 1;
    positions[k * 3] = water.cx + lx * c + lz * s;
    positions[k * 3 + 1] = y;
    positions[k * 3 + 2] = water.cz - lx * s + lz * c;
    if (i < seg) indices.push(0, k, k + 1);
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setIndex(indices);
  geo.computeVertexNormals();
  return geo;
}

function ribbonGeometry(points, width, yAt) {
  const pts = points || [];
  if (pts.length < 2) return new THREE.BufferGeometry();
  const positions = new Float32Array(pts.length * 2 * 3);
  const indices = [];
  for (let i = 0; i < pts.length; i++) {
    const prev = pts[Math.max(0, i - 1)];
    const next = pts[Math.min(pts.length - 1, i + 1)];
    const dx = next.x - prev.x;
    const dz = next.z - prev.z;
    const len = Math.hypot(dx, dz) || 1;
    const nx = -dz / len;
    const nz = dx / len;
    const y = typeof yAt === 'function' ? yAt(pts[i].x, pts[i].z, i) : yAt;
    const k = i * 6;
    positions[k] = pts[i].x + nx * width * 0.5;
    positions[k + 1] = y;
    positions[k + 2] = pts[i].z + nz * width * 0.5;
    positions[k + 3] = pts[i].x - nx * width * 0.5;
    positions[k + 4] = y;
    positions[k + 5] = pts[i].z - nz * width * 0.5;
    if (i < pts.length - 1) {
      const a = i * 2;
      indices.push(a, a + 2, a + 1, a + 1, a + 2, a + 3);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setIndex(indices);
  geo.computeVertexNormals();
  return geo;
}

function offsetPolyline(points, offset, closed = false) {
  const pts = points || [];
  if (pts.length < 2) return [];
  return pts.map((p, i) => {
    const prev = pts[i === 0 ? (closed ? pts.length - 1 : 0) : i - 1];
    const next = pts[i === pts.length - 1 ? (closed ? 0 : pts.length - 1) : i + 1];
    const dx = next.x - prev.x;
    const dz = next.z - prev.z;
    const len = Math.hypot(dx, dz) || 1;
    return { x: p.x - (dz / len) * offset, z: p.z + (dx / len) * offset };
  });
}

function smoothPolyline(points, iterations = 2, closed = false) {
  let pts = (points || []).map((p) => ({ x: p.x, z: p.z }));
  if (pts.length < 3) return pts;
  for (let it = 0; it < iterations; it++) {
    const next = [];
    const count = closed ? pts.length : pts.length - 1;
    if (!closed) next.push(pts[0]);
    for (let i = 0; i < count; i++) {
      const a = pts[i];
      const b = pts[(i + 1) % pts.length];
      next.push({
        x: a.x * 0.75 + b.x * 0.25,
        z: a.z * 0.75 + b.z * 0.25,
      });
      next.push({
        x: a.x * 0.25 + b.x * 0.75,
        z: a.z * 0.25 + b.z * 0.75,
      });
    }
    if (!closed) next.push(pts[pts.length - 1]);
    pts = next;
  }
  return pts;
}

function coastlineOutsideNormal(points, i, landPts) {
  const pts = points || [];
  const prev = pts[Math.max(0, i - 1)];
  const next = pts[Math.min(pts.length - 1, i + 1)];
  const dx = next.x - prev.x;
  const dz = next.z - prev.z;
  const len = Math.hypot(dx, dz) || 1;
  let nx = -dz / len;
  let nz = dx / len;
  const p = pts[i];
  if (pointInPolygon(landPts, p.x + nx * 16, p.z + nz * 16)) {
    nx = -nx; nz = -nz;
  }
  return { x: nx, z: nz };
}

function cliffWallGeometry(points, landPts, topAt, bottomY) {
  const pts = points || [];
  if (pts.length < 2) return new THREE.BufferGeometry();
  const positions = new Float32Array(pts.length * 2 * 3);
  const colors = new Float32Array(pts.length * 2 * 3);
  const indices = [];
  const topC = new THREE.Color(0x806744);
  const lowC = new THREE.Color(0x3d342c);
  for (let i = 0; i < pts.length; i++) {
    const n = coastlineOutsideNormal(pts, i, landPts);
    const x = pts[i].x + n.x * 3.5;
    const z = pts[i].z + n.z * 3.5;
    const topY = topAt(pts[i].x, pts[i].z) - 0.25;
    const lowY = bottomY - 0.35 - (i % 3) * 0.35;
    const k = i * 6;
    positions[k] = x; positions[k + 1] = topY; positions[k + 2] = z;
    positions[k + 3] = x + n.x * 18; positions[k + 4] = lowY; positions[k + 5] = z + n.z * 18;
    colors[k] = topC.r; colors[k + 1] = topC.g; colors[k + 2] = topC.b;
    colors[k + 3] = lowC.r; colors[k + 4] = lowC.g; colors[k + 5] = lowC.b;
    if (i < pts.length - 1) {
      const a = i * 2;
      indices.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  geo.setIndex(indices);
  geo.computeVertexNormals();
  return geo;
}

function coastalCartPath(path, side, offset) {
  return offsetPolyline(path || [], side * offset, false);
}

export function buildCourse(hole, assets) {
  const fbmBase = makeFbm(hole.seed, 4);
  const fbmDetail = makeFbm(hole.seed * 7 + 3, 3);
  const fbmGreen = makeFbm(hole.seed * 13 + 5, 3);

  // Each green gets a consistent overall tilt (direction + magnitude derived
  // deterministically from its position) so putts have a real, readable break
  // rather than a table-flat surface. Amplitude ~1-2% — genuine but fair.
  const gTiltAng = fbmGreen(hole.green.cx * 0.01 + 3, hole.green.cz * 0.01 - 7) * Math.PI * 2;
  const gTiltMag = 0.005 + Math.abs(fbmGreen(hole.green.cx * 0.02 - 5, hole.green.cz * 0.02 + 9)) * 0.006;
  const gTiltCos = Math.cos(gTiltAng) * gTiltMag;
  const gTiltSin = Math.sin(gTiltAng) * gTiltMag;

  const path = hole.path;
  const tee = path[0];
  const fhw = hole.fairwayHalf;
  const osm = hole.osm || {};
  const osmFairways = osm.fairways || [];
  const osmGreens = osm.greens || [];
  const osmTees = osm.tees || [];
  const osmBunkers = osm.bunkers || [];
  const isCoastal = hole.island?.profile === 'coastal';
  const elevation = isCoastal ? hole.island?.elevation : null;
  const visualZones = hole.island?.visualZones || {};
  const visualWoods = visualZones.woods || [];
  const visualSand = visualZones.sand || [];
  const visualScrub = visualZones.scrub || [];
  const forest = visualZones.forest || null;
  const forestFloor = visualZones.forestFloor || null;
  const dunes = visualZones.dunes || null;
  // Open coastal links (St Andrews) are essentially treeless — the scenery is
  // the town skyline, gorse, dunes and the sea, not a forest. Gorse flora is the
  // links tell; an explicit `treeless` flag can override either way.
  const treeless = visualZones.treeless ?? (visualZones.flora === 'gorse');
  const bunkerDepthMult = visualZones.bunkerDepth || 1;
  const forestFloorStart = forestFloor?.start ?? 26;
  const rawCoastLandPts = isCoastal ? (hole.island?.coastline?.land || []) : [];
  const rawCoastEdgePts = isCoastal ? (hole.island?.coastline?.beach || rawCoastLandPts) : [];
  const coastLandPts = smoothPolyline(rawCoastLandPts, 3, true);
  const coastEdgePts = smoothPolyline(rawCoastEdgePts, 3, false);
  const hasOcean = coastLandPts.length >= 3 && coastEdgePts.length >= 2;

  const proceduralBaseAt = hole.isRange
    ? (x, z) => fbmBase(x * 0.003, z * 0.003) * 0.35
    : (x, z) => fbmBase(x * 0.0065, z * 0.0065) * 4.5 + fbmBase(x * 0.018 + 50, z * 0.018) * 1.1;

  const baseAt = (x, z) => {
    const dem = elevationAtWorld(elevation, x, z);
    if (dem === null) return proceduralBaseAt(x, z);
    const broad = fbmBase(x * 0.0032 + 18, z * 0.0032 - 11) * 0.9;
    const detail = fbmBase(x * 0.014 + 50, z * 0.014) * 0.32;
    return dem + broad + detail;
  };

  // water level: relative to terrain near the water features
  let waterLevel = -100;
  let hasWater = hole.water.length > 0 || hasOcean;
  if (hasWater) {
    let minBase = Infinity;
    for (const w of hole.water) {
      if (w.type === 'pond') minBase = Math.min(minBase, baseAt(w.cx, w.cz));
      else for (const p of w.pts) minBase = Math.min(minBase, baseAt(p.x, p.z));
    }
    for (const p of coastEdgePts) minBase = Math.min(minBase, baseAt(p.x, p.z));
    if (!Number.isFinite(minBase)) minBase = Math.min(baseAt(tee.x, tee.z), baseAt(hole.green.cx, hole.green.cz));
    waterLevel = hasOcean ? minBase - 7.2 : minBase - 0.45;
  }
  const bedH = waterLevel - 1.1;

  // A point that must always stay full-height land — the playing corridor and
  // any mapped course surface — even where it sits right on the cliff edge.
  function courseForcedLand(x, z, p = null) {
    const info = p || distToPolyline(path, x, z);
    if (info.dist < fhw + 13) return true;
    if (inFeaturePolys(osmFairways, x, z) || inFeaturePolys(osmGreens, x, z)
      || inFeaturePolys(osmTees, x, z) || inFeaturePolys(osmBunkers, x, z)) return true;
    if (ellipseVal(hole.green, x, z) < 3.0) return true;
    if (Math.hypot(x - tee.x, z - tee.z) < 22) return true;
    return false;
  }

  function coastalPlayableLand(x, z, p = null) {
    if (!hasOcean) return true;
    if (pointInPolygon(coastLandPts, x, z)) return true;
    return courseForcedLand(x, z, p);
  }

  function waterMask(x, z) {
    let m = 0, core = false;
    if (hasOcean) {
      const land = coastalPlayableLand(x, z);
      const coastDist = distToPolyline(coastEdgePts, x, z).dist;
      if (!land) {
        m = 1;
        core = true;
      } else {
        m = Math.max(m, sstep(20, 0, coastDist) * 0.25);
      }
    }
    for (const w of hole.water) {
      if (w.type === 'pond') {
        const v = ellipseVal(w, x, z);
        m = Math.max(m, sstep(1.45, 0.8, v));
        if (v < 1.0) core = true;
      } else {
        const half = w.width / 2;
        const { dist } = distToPolyline(w.pts, x, z);
        m = Math.max(m, sstep(half + 8, half - 1, dist));
        if (dist < half) core = true;
      }
    }
    return { m, core };
  }

  function heightAt(x, z) {
    const p = distToPolyline(path, x, z);
    const fairMask = Math.max(sstep(fhw + 20, fhw - 5, p.dist), inFeaturePolys(osmFairways, x, z) ? 1 : 0);

    // --- shaped LAND height (computed everywhere; clamped to seabed below) ---
    let h = baseAt(x, z);
    if (hasOcean) {
      const coastDist = distToPolyline(coastEdgePts, x, z).dist;
      const bluff = sstep(130, 14, coastDist) * (1 - fairMask * 0.78);
      h += bluff * (2.8 + fbmDetail(x * 0.018 + 22, z * 0.018 - 6) * 0.9);
      h += sstep(52, 6, coastDist) * fbmDetail(x * 0.055 + 9, z * 0.055 + 14) * 1.5;
      const greenProtected = ellipseVal(hole.green, x, z) < 3.2 || inFeaturePolys(osmGreens, x, z);
      const shoreTaper = sstep(38, 0, coastDist) * (1 - fairMask) * (greenProtected ? 0 : 1);
      const shoreShelf = waterLevel + 2.0 + fbmDetail(x * 0.025 - 4, z * 0.025 + 3) * 0.45;
      h = lerp(h, Math.max(shoreShelf, h - 3.5), shoreTaper * 0.72);
    }
    h += fbmDetail(x * 0.05, z * 0.05) * 0.85 * (1 - fairMask);  // bumpy rough
    h += fairMask * 0.15;                                        // slight fairway crown
    h += fairMask * fbmBase(x * 0.008 + 130, z * 0.008 - 90) * 0.8; // long, gentle fairway heave
    if (dunes) {
      // links mounding: 30-60m humps and hollows that run THROUGH fairways
      // (softened), the defining ground game of seaside golf
      const dn = fbmBase(x * (dunes.freq || 0.02) + 71, z * (dunes.freq || 0.02) - 37);
      h += dn * (dunes.amp || 1.3) * (1 - fairMask * 0.55);
    }

    // green plateau with gentle internal contours
    const gv = ellipseVal(hole.green, x, z);
    const osmGreen = inFeaturePolys(osmGreens, x, z);
    if (gv < 3.2 || osmGreen) {
      const gm = osmGreen ? 1 : 1 - sstep(1.05, 2.6, gv);
      const gcx = hole.green.cx, gcz = hole.green.cz;
      const tilt = (x - gcx) * gTiltCos + (z - gcz) * gTiltSin; // overall pitch
      const swale = fbmGreen(x * 0.035 + 11, z * 0.035 - 4) * 0.11; // broad rolls
      const micro = fbmGreen(x * 0.12, z * 0.12) * 0.03;           // fine texture
      const greenH = baseAt(gcx, gcz) + 0.4 + tilt + swale + micro;
      h = lerp(h, greenH, gm);
    }

    // tee pad
    const td = Math.hypot(x - tee.x, z - tee.z);
    const osmTee = inFeaturePolys(osmTees, x, z);
    if (td < 16 || osmTee) {
      const tm = osmTee ? 1 : 1 - sstep(7, 15, td);
      h = lerp(h, baseAt(tee.x, tee.z) + 0.45, tm);
    }

    // bunkers: bowl + soft lip
    if (inFeaturePolys(osmBunkers, x, z)) {
      h -= 0.75 * bunkerDepthMult;
    }
    for (const b of hole.bunkers) {
      const bv = ellipseVal(b, x, z);
      if (bv < 2.2) {
        const t = Math.max(0, 1 - bv);
        h -= b.depth * Math.pow(t, 1.25);
        h += 0.13 * Math.exp(-((bv - 1.18) ** 2) / 0.03);
      }
    }

    // water carve (after fairway so the creek cuts through)
    if (hole.water.length > 0) {
      const { m } = waterMask(x, z);
      if (m > 0) h = lerp(h, bedH, m * 0.95);
    }

    // --- smooth coastline ---
    // Blend the shaped land down to the seabed across a soft, noise-warped band
    // that straddles the shore. Because it's a continuous function of a signed
    // distance (not a hard inside/outside flip), the grid mesh slopes gently into
    // the sea instead of stair-stepping at the polygon edge. Course surfaces are
    // pinned to full land height so greens/tees never sink at clifftop holes.
    if (hasOcean) {
      const seabed = waterLevel - 1.8 - fbmDetail(x * 0.018, z * 0.018) * 0.45;
      let t;
      if (courseForcedLand(x, z, p)) {
        t = 1;
      } else {
        const coastDist = distToPolyline(coastEdgePts, x, z).dist;
        const wob = fbmDetail(x * 0.06 + 3, z * 0.06 - 7) * 4.5;        // organic edge
        const signed = (pointInPolygon(coastLandPts, x, z) ? 1 : -1) * coastDist + wob;
        t = sstep(-9, 12, signed);                                     // 21m smooth shore band
      }
      h = lerp(seabed, h, t);
    }
    return h;
  }

  function surfaceAt(x, z) {
    const p = distToPolyline(path, x, z);
    if (hasOcean && !coastalPlayableLand(x, z, p)) return SURF.WATER;
    if (hasWater) {
      const { core } = waterMask(x, z);
      if (core && heightAt(x, z) <= waterLevel + 0.06) return SURF.WATER;
    }
    for (const b of hole.bunkers) {
      if (ellipseVal(b, x, z) < 1) return SURF.SAND;
    }
    if (inFeaturePolys(osmBunkers, x, z)) return SURF.SAND;
    if (inFeaturePolys(osmGreens, x, z)) return SURF.GREEN;
    if (inFeaturePolys(osmTees, x, z)) return SURF.TEE;
    const gv = ellipseVal(hole.green, x, z);
    if (gv <= 1.0) return SURF.GREEN;
    if (gv <= 1.6) return SURF.FRINGE;
    if (Math.hypot(x - tee.x, z - tee.z) < 7) return SURF.TEE;
    if (inFeaturePolys(osmFairways, x, z)) return SURF.FAIRWAY;
    if (p.dist < fhw) return SURF.FAIRWAY;
    return SURF.ROUGH;
  }

  function normalAt(x, z) {
    const e = 0.4;
    const hx = heightAt(x + e, z) - heightAt(x - e, z);
    const hz = heightAt(x, z + e) - heightAt(x, z - e);
    const inv = 1 / Math.hypot(hx / (2 * e), 1, hz / (2 * e));
    return { x: -hx / (2 * e) * inv, y: inv, z: -hz / (2 * e) * inv };
  }

  // point at distance s along the playing line
  function pointAtAlong(s) {
    let acc = 0;
    for (let i = 0; i < path.length - 1; i++) {
      const a = path[i], b = path[i + 1];
      const L = Math.hypot(b.x - a.x, b.z - a.z);
      if (acc + L >= s) {
        const t = (s - acc) / L;
        return { x: a.x + (b.x - a.x) * t, z: a.z + (b.z - a.z) * t };
      }
      acc += L;
    }
    return { ...path[path.length - 1] };
  }

  const pathInfo = (x, z) => distToPolyline(path, x, z);

  // out of bounds: a white-stake corridor around the playing line.
  // Judged where the ball comes to rest, like the real rule.
  const obDist = fhw + (hole.obMargin ?? 55);
  const isOB = (x, z) => distToPolyline(path, x, z).dist > obDist;

  // ---------- bounds ----------
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  const stretch = (x, z, m) => {
    minX = Math.min(minX, x - m); maxX = Math.max(maxX, x + m);
    minZ = Math.min(minZ, z - m); maxZ = Math.max(maxZ, z + m);
  };
  for (const p of path) stretch(p.x, p.z, 0);
  for (const b of hole.bunkers) stretch(b.cx, b.cz, Math.max(b.rx, b.rz));
  for (const list of [osmFairways, osmGreens, osmTees, osmBunkers]) {
    for (const f of list) {
      for (const p of f.points || []) stretch(p.x, p.z, 8);
    }
  }
  for (const w of hole.water) {
    if (w.type === 'pond') stretch(w.cx, w.cz, Math.max(w.rx, w.rz));
    else for (const p of w.pts) stretch(p.x, p.z, w.width);
  }
  const MARGIN = 90;
  minX -= MARGIN; maxX += MARGIN; minZ -= MARGIN; maxZ += MARGIN;
  if (hole.isRange && hole.rangeScenery) {
    const padX = hole.rangeScenery.boundsPadX ?? 170;
    minX = Math.min(minX, tee.x - padX);
    maxX = Math.max(maxX, tee.x + padX);
    minZ = Math.min(minZ, tee.z - 55);
    maxZ = Math.max(maxZ, path[path.length - 1].z + (hole.rangeScenery.backPad ?? 110));
  }
  const localBounds = { minX, maxX, minZ, maxZ };
  const worldPaths = isCoastal
    ? (hole.island?.paths || []).filter((p) => lineIntersectsBounds(p.points, localBounds, 40))
    : [];

  const pinPos = {
    x: hole.pin.x,
    z: hole.pin.z,
    y: heightAt(hole.pin.x, hole.pin.z),
  };
  const teeH = heightAt(tee.x, tee.z);

  // ---------- visuals (browser only) ----------
  let group = null;
  let updateFlag = () => {};
  let updateWater = () => {};
  const flatWaters = [];
  let oceanMesh = null;
  let spots = [];

  if (VISUAL && assets) {
    group = new THREE.Group();

    if (hole.island?.bounds && !hole.isRange) {
      let localMinH = Infinity;
      for (let sx = 0; sx <= 5; sx++) {
        for (let sz = 0; sz <= 5; sz++) {
          const x = minX + (maxX - minX) * (sx / 5);
          const z = minZ + (maxZ - minZ) * (sz / 5);
          localMinH = Math.min(localMinH, heightAt(x, z));
        }
      }
      const baseY = (hole.island.profile === 'coastal' && hasOcean)
        ? waterLevel - 0.45
        : localMinH - 0.7;
      const ib = hole.island.bounds;
      const icx = (ib.minX + ib.maxX) / 2;
      const icz = (ib.minZ + ib.maxZ) / 2;
      const iw = ib.maxX - ib.minX;
      const ih = ib.maxZ - ib.minZ;
      if (hole.island.profile === 'coastal' && hasOcean) {
        // A vast, reflective ocean stretching to the horizon — the course sits
        // on a coastal headland, not a tidy little island pond.
        const ocean = new Water(new THREE.PlaneGeometry(26000, 26000), {
          // 256 reflection: this plane re-renders the whole scene every frame,
          // so it was the single biggest cost on the coastal course. Distant
          // rippled water doesn't need a sharp mirror — 256 is plenty and cuts
          // the per-frame reflection cost to a quarter.
          textureWidth: 256,
          textureHeight: 256,
          waterNormals: assets.waterN,
          sunDirection: assets.sunDir.clone(),
          sunColor: 0xffffff,
          waterColor: 0x1a4f6b,
          distortionScale: 2.6,
          fog: true,
        });
        ocean.rotation.x = -Math.PI / 2;
        ocean.position.set(icx, waterLevel - 0.02, icz);
        // Push the ocean's depth back so the tint plate above it always wins the
        // depth test — otherwise the two 26,000 m coplanar planes z-fight and the
        // whole sea flickers as the camera moves.
        ocean.material.polygonOffset = true;
        ocean.material.polygonOffsetFactor = 3;
        ocean.material.polygonOffsetUnits = 3;
        group.add(ocean);
        oceanMesh = ocean;
        // Deep-blue tint plate: keeps the Pacific reading blue instead of a
        // silver sky mirror when viewed down the coast.
        const oceanTint = new THREE.Mesh(
          new THREE.PlaneGeometry(26000, 26000),
          new THREE.MeshBasicMaterial({ color: 0x134a68, transparent: true, opacity: 0.58, depthWrite: false, fog: true }),
        );
        oceanTint.rotation.x = -Math.PI / 2;
        oceanTint.position.set(icx, waterLevel + 0.015, icz);
        oceanTint.renderOrder = 1;
        group.add(oceanTint);
      } else if (hole.island.profile === 'coastal') {
        // Inland real-data course: forested land to the horizon, no sea.
        const landSkirt = new THREE.Mesh(
          new THREE.PlaneGeometry(26000, 26000),
          new THREE.MeshLambertMaterial({ color: 0x2b4f27 }),
        );
        landSkirt.rotation.x = -Math.PI / 2;
        landSkirt.position.set(icx, baseY - 0.05, icz);
        group.add(landSkirt);
      } else {
        const islandWater = new THREE.Mesh(
          new THREE.PlaneGeometry(iw + 650, ih + 650),
          new THREE.MeshBasicMaterial({ color: 0x123241 }),
        );
        islandWater.rotation.x = -Math.PI / 2;
        islandWater.position.set(icx, baseY - 0.05, icz);
        group.add(islandWater);
      }

      const islandBase = new THREE.Mesh(
        hole.island.profile === 'coastal'
          ? coastalPlateGeometry(ib, hole.island.coastline, baseY)
          : islandPlateGeometry(ib, baseY, hole.seed),
        new THREE.MeshLambertMaterial({ color: 0x254d2d }),
      );
      islandBase.receiveShadow = true;
      group.add(islandBase);

      const lakeMat = new THREE.MeshBasicMaterial({
        color: 0x1f6f8c,
        transparent: true,
        opacity: 0.82,
        depthWrite: false,
      });
      for (const w of hole.island.water || []) {
        if (w.type !== 'pond') continue;
        const lake = new THREE.Mesh(lakePlateGeometry(w, baseY + 0.035), lakeMat);
        group.add(lake);
      }
    }

    // terrain mesh: vertex colors (hue design) + splat weights (texture mix)
    const CELL = hasOcean ? 1.15 : 1.7;
    const nx = Math.min(hasOcean ? 620 : 440, Math.ceil((maxX - minX) / CELL));
    const nz = Math.min(hasOcean ? 660 : 480, Math.ceil((maxZ - minZ) / CELL));
    const geo = new THREE.BufferGeometry();
    const positions = new Float32Array((nx + 1) * (nz + 1) * 3);
    const colors = new Float32Array((nx + 1) * (nz + 1) * 3);
    const splats = new Float32Array((nx + 1) * (nz + 1) * 4);

    // Turf palette is per-course overridable so each venue keeps its own
    // signature (e.g. Augusta's hyper-vibrant emerald + white sand vs a links'
    // muted fescue). Defaults reproduce the original parkland look.
    const C = {
      fairA: new THREE.Color(visualZones.fairA ?? 0x568f3f), fairB: new THREE.Color(visualZones.fairB ?? 0x447c31),
      firstCut: new THREE.Color(visualZones.firstCut ?? 0x4c8237),
      fringe: new THREE.Color(visualZones.fringe ?? 0x467c38),
      greenA: new THREE.Color(visualZones.greenA ?? 0x67a64f), greenB: new THREE.Color(visualZones.greenB ?? 0x5d9b46),
      tee: new THREE.Color(visualZones.teeColor ?? 0x5c9d48),
      rough: new THREE.Color(visualZones.roughColor ?? 0x3b662e),
      deep: new THREE.Color(visualZones.deepColor ?? 0x2c4f22),
      sand: new THREE.Color(visualZones.sandColor ?? 0xd5c28c),
      bed: new THREE.Color(0x31464a),
      beach: new THREE.Color(0xb9ab82),
      scrub: new THREE.Color(0x626c51),
      rock: new THREE.Color(0x51463a),
    };
    const strawColor = new THREE.Color(forestFloor?.color ?? 0x8a6742);
    const _dryBank = new THREE.Color(0x7a7f45);
    const tmp = new THREE.Color();

    let vi = 0;
    for (let iz = 0; iz <= nz; iz++) {
      for (let ix = 0; ix <= nx; ix++) {
        const x = minX + (maxX - minX) * (ix / nx);
        const z = minZ + (maxZ - minZ) * (iz / nz);
        const h = heightAt(x, z);
        positions[vi * 3] = x;
        positions[vi * 3 + 1] = h;
        positions[vi * 3 + 2] = z;

        const surf = surfaceAt(x, z);
        const p = pathInfo(x, z);
        const inMappedSand = visualSand.length > 0 && inFeaturePolys(visualSand, x, z);
        const inMappedScrub = visualScrub.length > 0 && inFeaturePolys(visualScrub, x, z);
        const coastDist = hasOcean ? distToPolyline(coastEdgePts, x, z).dist : Infinity;
        let sg = 0, sr = 0, ss = 0, sw = 0;   // grass, rough, sand, tight-mow
        // Terrain steepness (rise/run) from the DEM — drives cliff rock.
        let slopeMag = 0;
        if (elevation) {
          const _se0 = elevationAtWorld(elevation, x, z);
          if (_se0 != null) {
            const _sex = (elevationAtWorld(elevation, x + 1.6, z) ?? _se0) - _se0;
            const _sez = (elevationAtWorld(elevation, x, z + 1.6) ?? _se0) - _se0;
            slopeMag = Math.hypot(_sex, _sez) / 1.6;
          }
        }

        if (hasWater && h < waterLevel + 0.05 && waterMask(x, z).m > 0.45) {
          tmp.copy(C.bed); sr = 1;
        } else if (surf === SURF.SAND) {
          ss = 1;
          let bv = 9;
          for (const b of hole.bunkers) bv = Math.min(bv, ellipseVal(b, x, z));
          if (bv > 1.3) {
            // polygon sand beyond any fitted ellipse: neutral wash
            tmp.copy(C.sand).multiplyScalar(0.97);
          } else {
            // sculpted dish: bright raked centre, shadowed ring under the lip
            const rim = sstep(0.5, 1.0, Math.min(bv, 1));
            tmp.copy(C.sand).multiplyScalar(1.07 - 0.32 * rim);
          }
        } else if (surf === SURF.GREEN || surf === SURF.TEE) {
          if (surf === SURF.TEE) {
            tmp.copy(C.tee);
            // Lived-in tee box: faint darker divot scuffs from iron play.
            const scuff = fbmDetail(x * 1.7 + 12, z * 1.7);
            if (scuff > 0.36) tmp.multiplyScalar(1 - 0.09 * sstep(0.36, 0.58, scuff));
          } else {
            // Double-cut checkerboard mow: soft-edged bands in two perpendicular
            // directions (lighter greenA vs darker greenB) plus a faint sheen so
            // it reads as a manicured stripe pattern, not a hard tiled checker.
            const gsx = sstep(-0.34, 0.34, Math.sin(x / 2.3 * Math.PI));
            const gsz = sstep(-0.34, 0.34, Math.sin(z / 2.3 * Math.PI));
            const checkT = gsx * gsz + (1 - gsx) * (1 - gsz);
            tmp.copy(C.greenB).lerp(C.greenA, checkT);
            tmp.multiplyScalar(1 + 0.035 * (checkT - 0.5) * 2);
            // faint ball-mark speckle on the putting surface
            const bm = fbmDetail(x * 2.1 + 41, z * 2.1);
            if (bm > 0.52) tmp.multiplyScalar(1 - 0.05 * sstep(0.52, 0.72, bm));
          }
          sg = 1; sw = 1;
        } else if (surf === SURF.FRINGE) {
          // Fringe collar: pull slightly toward the green tone and carry a hint
          // of tight-mow sheen so the green -> fringe -> fairway handoff blends
          // instead of stepping.
          const gv = ellipseVal(hole.green, x, z);
          tmp.copy(C.fringe).lerp(C.greenB, 0.22 * (1 - sstep(1.0, 1.35, gv)));
          sg = 1; sw = 0.55;
        } else if (surf === SURF.FAIRWAY) {
          // Directional mowing stripes down the line of play: soft-edged
          // light/dark bands (~6.5 m) with a subtle brightness sheen so they
          // read crisply but naturally rather than as flat colour swaps.
          const band = Math.sin(p.along / 6.5 * Math.PI);
          const stripeT = sstep(-0.44, 0.44, band);
          tmp.copy(C.fairB).lerp(C.fairA, stripeT);
          tmp.multiplyScalar(1 + 0.05 * (stripeT - 0.5) * 2);
          sg = 1;
        } else if (p.dist < fhw + 3.5) {
          // First cut collar: blend the mown fairway tone (carrying a faint echo
          // of the stripe) out toward the first-cut/rough colour across the band.
          const ft = sstep(fhw - 1.0, fhw + 3.5, p.dist);
          const band = Math.sin(p.along / 6.5 * Math.PI);
          const stripeT = sstep(-0.44, 0.44, band);
          tmp.copy(C.fairB).lerp(C.fairA, stripeT).lerp(C.firstCut, 0.5 + 0.5 * ft);
          sg = lerp(0.85, 0.55, ft); sr = lerp(0.15, 0.45, ft);
        } else if (inMappedSand) {
          tmp.copy(C.beach); ss = 0.68; sr = 0.32;
        } else if (inMappedScrub) {
          tmp.copy(C.scrub); sr = 1;
        } else if (hasOcean && coastDist < 30 && !inFeaturePolys(osmFairways, x, z) && !inFeaturePolys(osmGreens, x, z)) {
          tmp.copy(C.rock).lerp(C.rough, sstep(2, 30, coastDist)); sr = 1;
        } else {
          const t = sstep(fhw + 10, fhw + 45, p.dist);
          tmp.copy(C.rough).lerp(C.deep, t);
          sr = 1;
          // Hills read as hills: steep banks dry out and crests catch light.
          const slope = Math.min(1, slopeMag * 1.4);
          if (slope > 0.12) {
            tmp.lerp(_dryBank, Math.min(0.4, (slope - 0.12) * 0.75));
          }
          if (forestFloor && p.dist > fhw + forestFloorStart) {
            // Pine-straw carpet under the tree lines (parkland courses).
            const ft = sstep(fhw + forestFloorStart, fhw + forestFloorStart + 24, p.dist)
              * (0.5 + 0.5 * sstep(-0.3, 0.35, fbmDetail(x * 0.016 + 7, z * 0.016)));
            tmp.lerp(strawColor, ft * 0.85);
            ss = ft * 0.55;
            sr = 1 - ss;
          }
        }
        // Cliff faces: near-vertical terrain is bare rock, not stretched grass.
        if (slopeMag > 0.55 && surf !== SURF.GREEN && surf !== SURF.TEE
            && surf !== SURF.FAIRWAY && surf !== SURF.FRINGE) {
          const rockT = Math.min(0.9, (slopeMag - 0.55) * 1.15);
          const cliff = new THREE.Color(0x6b5d4a).lerp(new THREE.Color(0x8a7a63),
            fbmDetail(x * 0.08, z * 0.08) * 0.5 + 0.5);
          tmp.lerp(cliff, rockT);
          sr = 1; ss = 0; sg = 0; sw = 0;
        }
        if (surf !== SURF.SAND && ss === 0) {
          let bv = 9;
          for (const b of hole.bunkers) bv = Math.min(bv, ellipseVal(b, x, z));
          if (bv > 1 && bv < 1.5) {
            // raised grass lip catching light around the bunker edge
            const lip = 1 - Math.abs(bv - 1.2) / 0.3;
            if (lip > 0) tmp.multiplyScalar(1 + 0.13 * lip);
          } else if (bv >= 1.5 && bv < 3.2) {
            // Soft AO: turf just outside the lip sits in the bunker's shadow,
            // giving the hazard depth. Fades out over ~2 units.
            tmp.multiplyScalar(1 - 0.10 * (1 - sstep(1.5, 3.2, bv)));
          }
        }
        // Manicured turf stays smooth; only rough gets real mottling — the
        // uniform noise was making greens/fairways look blotchy. A very
        // large-scale octave adds gentle sun-and-shade patches to open turf.
        const mottle = (surf === SURF.GREEN || surf === SURF.TEE) ? 0.15
          : (surf === SURF.FAIRWAY || surf === SURF.FRINGE) ? 0.4 : 1.0;
        const broad = (surf === SURF.GREEN || surf === SURF.TEE) ? 0
          : fbmDetail(x * 0.0125 + 61, z * 0.0125) * 0.055;
        const vmod = 1 + (fbmDetail(x * 0.11 + 31, z * 0.11) * 0.07
          + fbmDetail(x * 0.031 + 7, z * 0.031) * 0.045) * mottle
          + broad * (surf === SURF.FAIRWAY ? 0.6 : 1.0);
        colors[vi * 3] = tmp.r * vmod;
        colors[vi * 3 + 1] = tmp.g * vmod;
        colors[vi * 3 + 2] = tmp.b * vmod;
        splats[vi * 4] = sg; splats[vi * 4 + 1] = sr;
        splats[vi * 4 + 2] = ss; splats[vi * 4 + 3] = sw;
        vi++;
      }
    }

    const indices = [];
    for (let iz = 0; iz < nz; iz++) {
      for (let ix = 0; ix < nx; ix++) {
        const a = iz * (nx + 1) + ix;
        const b = a + 1;
        const c = a + (nx + 1);
        const d = c + 1;
        indices.push(a, c, b, b, c, d);
      }
    }
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    geo.setAttribute('splat', new THREE.BufferAttribute(splats, 4));
    geo.setIndex(indices);
    geo.computeVertexNormals();

    const terrain = new THREE.Mesh(geo, splatMaterial(assets));
    terrain.receiveShadow = true;
    group.add(terrain);

    if (hasOcean || worldPaths.length) {
      const pathMat = new THREE.MeshStandardMaterial({
        color: 0x2e302c,
        roughness: 0.92,
        metalness: 0,
        transparent: true,
        opacity: 0.94,
      });
      const visiblePaths = worldPaths.length
        ? worldPaths
        : [
            { points: coastalCartPath(path, -1, fhw + 12), width: 3.2 },
            { points: coastalCartPath(path, 1, fhw + 18), width: 2.2 },
          ];
      for (const pth of visiblePaths.slice(0, 18)) {
        if ((pth.points?.length || 0) < 2) continue;
        const pathMesh = new THREE.Mesh(
          ribbonGeometry(pth.points, pth.width || 3.2, (x, z) => heightAt(x, z) + 0.052),
          pathMat,
        );
        pathMesh.receiveShadow = true;
        group.add(pathMesh);
      }
    }

    if (hasOcean) {
      // No separate cliff-wall mesh: the terrain now slopes smoothly into the
      // sea, so a vertical rock wall would just re-introduce the hard faceted
      // edge. Foam at the waterline + scattered rocks sell the shoreline instead.
      const foamMat = new THREE.MeshBasicMaterial({
        color: 0xf4fbff,
        transparent: true,
        opacity: 0.72,
        depthWrite: false,
        side: THREE.DoubleSide,
      });
      const foamNear = new THREE.Mesh(
        ribbonGeometry(coastEdgePts, 8, waterLevel + 0.035),
        foamMat,
      );
      const foamOffshore = new THREE.Mesh(
        ribbonGeometry(offsetPolyline(coastEdgePts, 16, false), 5, waterLevel + 0.045),
        foamMat.clone(),
      );
      foamOffshore.material.opacity = 0.38;
      foamNear.renderOrder = 2; foamOffshore.renderOrder = 2;   // sit above the ocean tint
      group.add(foamNear, foamOffshore);

      const coastRng = makeRng(hole.seed * 101 + 19);
      const rockGeo = new THREE.DodecahedronGeometry(1, 1);
      const rockMat = new THREE.MeshStandardMaterial({ color: 0x34312a, roughness: 0.96, metalness: 0.02 });
      const rockCount = Math.min(120, Math.max(36, coastEdgePts.length * 5));
      const rocks = new THREE.InstancedMesh(rockGeo, rockMat, rockCount);
      const rm = new THREE.Matrix4();
      const rq = new THREE.Quaternion();
      const re = new THREE.Euler();
      const rp = new THREE.Vector3();
      const rs = new THREE.Vector3();
      for (let i = 0; i < rockCount; i++) {
        const idx = Math.floor(coastRng() * (coastEdgePts.length - 1));
        const a = coastEdgePts[idx];
        const b = coastEdgePts[idx + 1] || a;
        const t = coastRng();
        const n = coastlineOutsideNormal(coastEdgePts, idx, coastLandPts);
        const x = lerp(a.x, b.x, t) + n.x * (12 + coastRng() * 42);
        const z = lerp(a.z, b.z, t) + n.z * (12 + coastRng() * 42);
        re.set(coastRng() * Math.PI, coastRng() * Math.PI, coastRng() * Math.PI);
        rq.setFromEuler(re);
        rp.set(x, waterLevel + 0.1 + coastRng() * 1.4, z);
        const s = 1.4 + coastRng() * 5.6;
        rs.set(s * (0.8 + coastRng() * 0.7), s * (0.35 + coastRng() * 0.55), s * (0.8 + coastRng() * 0.7));
        rm.compose(rp, rq, rs);
        rocks.setMatrixAt(i, rm);
      }
      rocks.instanceMatrix.needsUpdate = true;
      rocks.castShadow = true;
      rocks.receiveShadow = true;
      group.add(rocks);

      const scrubGeo = new THREE.SphereGeometry(1, 8, 6);
      const scrubMat = new THREE.MeshLambertMaterial({ color: 0x6d7562 });
      const scrubCount = 120;
      const scrub = new THREE.InstancedMesh(scrubGeo, scrubMat, scrubCount);
      for (let i = 0; i < scrubCount; i++) {
        const idx = Math.floor(coastRng() * (coastEdgePts.length - 1));
        const a = coastEdgePts[idx];
        const b = coastEdgePts[idx + 1] || a;
        const t = coastRng();
        const n = coastlineOutsideNormal(coastEdgePts, idx, coastLandPts);
        const x = lerp(a.x, b.x, t) - n.x * (12 + coastRng() * 62);
        const z = lerp(a.z, b.z, t) - n.z * (12 + coastRng() * 62);
        if (!coastalPlayableLand(x, z) || distToPolyline(path, x, z).dist < fhw + 8) {
          rm.makeScale(0.001, 0.001, 0.001);
          scrub.setMatrixAt(i, rm);
          continue;
        }
        re.set(0, coastRng() * Math.PI * 2, 0);
        rq.setFromEuler(re);
        rp.set(x, heightAt(x, z) + 0.22, z);
        const s = 1.0 + coastRng() * 2.8;
        rs.set(s * 1.9, s * 0.45, s * 1.25);
        rm.compose(rp, rq, rs);
        scrub.setMatrixAt(i, rm);
      }
      scrub.instanceMatrix.needsUpdate = true;
      scrub.castShadow = true;
      scrub.receiveShadow = true;
      group.add(scrub);
    }

    // ---------- reflective water ----------
    const waters = [];
    for (const w of hole.water) {
      let cx, cz, sx, sz;
      if (w.type === 'pond') {
        cx = w.cx; cz = w.cz;
        sx = Math.max(w.rx, w.rz) * 2 + 24; sz = sx;
      } else {
        let wMinX = Infinity, wMaxX = -Infinity, wMinZ = Infinity, wMaxZ = -Infinity;
        for (const p of w.pts) {
          wMinX = Math.min(wMinX, p.x); wMaxX = Math.max(wMaxX, p.x);
          wMinZ = Math.min(wMinZ, p.z); wMaxZ = Math.max(wMaxZ, p.z);
        }
        cx = (wMinX + wMaxX) / 2; cz = (wMinZ + wMaxZ) / 2;
        sx = wMaxX - wMinX + w.width * 2 + 20;
        sz = wMaxZ - wMinZ + w.width * 2 + 20;
      }
      if (waters.length >= 1 || w.type === 'channel') {
        // cheap non-reflective plate: dark, slightly glossy, no scene re-render
        const flatNorm = assets.waterN.clone();
        flatNorm.wrapS = flatNorm.wrapT = THREE.RepeatWrapping;
        flatNorm.repeat.set(sx / 18, sz / 18);
        const flat = new THREE.Mesh(
          new THREE.PlaneGeometry(sx, sz),
          new THREE.MeshStandardMaterial({
            color: new THREE.Color(visualZones.waterColor ?? 0x0e3526).multiplyScalar(0.7),
            roughness: 0.14, metalness: 0.05, envMapIntensity: 0.7,
            normalMap: flatNorm, normalScale: new THREE.Vector2(0.55, 0.55),
          }),
        );
        flatWaters.push(flatNorm);
        flat.rotation.x = -Math.PI / 2;
        flat.position.set(cx, waterLevel, cz);
        group.add(flat);
        continue;
      }
      const water = new Water(new THREE.PlaneGeometry(sx, sz), {
        textureWidth: 384,
        textureHeight: 384,
        waterNormals: assets.waterN,
        sunDirection: assets.sunDir.clone(),
        sunColor: 0xffffff,
        waterColor: visualZones.waterColor ?? 0x0e3526,
        distortionScale: 2.2,
        fog: true,
      });
      water.rotation.x = -Math.PI / 2;
      water.position.set(cx, waterLevel, cz);
      group.add(water);
      waters.push(water);
      if (visualZones.waterColor != null) {
        // The reflective shader reads silver from tee height; a translucent
        // tint plate keeps ponds/creeks reading as deep water.
        const tint = new THREE.Mesh(
          new THREE.PlaneGeometry(sx, sz),
          new THREE.MeshBasicMaterial({
            color: visualZones.waterColor,
            transparent: true,
            opacity: 0.45,
            depthWrite: false,
            fog: true,
          }),
        );
        tint.rotation.x = -Math.PI / 2;
        tint.position.set(cx, waterLevel + 0.03, cz);
        group.add(tint);
      }
    }
    // (combined animation hook assigned after trees/birds are built)

    // ---------- landmark bridges (Swilcan-style stone arch) ----------
    for (const b of visualZones.bridges || []) {
      if (b.x < minX || b.x > maxX || b.z < minZ || b.z > maxZ) continue;
      const stone = new THREE.MeshStandardMaterial({ color: 0x9a917e, roughness: 0.95 });
      const bridgeGrp = new THREE.Group();
      const span = b.span || 14;
      const deckW = 2.6;
      const groundY = waterLevel + 0.15;
      const rise = 1.1;
      // Arched deck: short segments along a shallow parabola.
      const SEGS = 9;
      for (let i = 0; i < SEGS; i++) {
        const t0 = i / SEGS - 0.5;
        const t1 = (i + 1) / SEGS - 0.5;
        const y0 = groundY + rise * (1 - 4 * t0 * t0);
        const y1 = groundY + rise * (1 - 4 * t1 * t1);
        const segLen = Math.hypot((t1 - t0) * span, y1 - y0) + 0.06;
        const seg = new THREE.Mesh(new THREE.BoxGeometry(deckW, 0.32, segLen), stone);
        seg.position.set(0, (y0 + y1) / 2, ((t0 + t1) / 2) * span);
        seg.rotation.x = -Math.atan2(y1 - y0, (t1 - t0) * span);
        seg.castShadow = true;
        seg.receiveShadow = true;
        bridgeGrp.add(seg);
        // low stone parapets
        for (const sideX of [-deckW / 2 + 0.12, deckW / 2 - 0.12]) {
          const par = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.34, segLen), stone);
          par.position.set(sideX, (y0 + y1) / 2 + 0.3, ((t0 + t1) / 2) * span);
          par.rotation.x = seg.rotation.x;
          par.castShadow = true;
          bridgeGrp.add(par);
        }
      }
      // solid abutments at each bank
      for (const end of [-1, 1]) {
        const ab = new THREE.Mesh(new THREE.BoxGeometry(deckW + 0.5, 1.3, 1.6), stone);
        ab.position.set(0, groundY - 0.35, end * (span / 2 + 0.5));
        ab.castShadow = true;
        ab.receiveShadow = true;
        bridgeGrp.add(ab);
      }
      bridgeGrp.position.set(b.x, 0, b.z);
      bridgeGrp.rotation.y = (b.rot || 0) + Math.PI / 2;   // deck runs ACROSS the burn
      group.add(bridgeGrp);
    }

    // ---------- town edge: real building footprints + boundary walls ----------
    // Instanced (2 draw calls for all buildings, 1 for walls), no shadow
    // casting, sizes clamped — the previous per-mesh version was both the
    // frame-rate hit and the "grey warehouse" look.
    if ((visualZones.buildings || []).length) {
      const blds = visualZones.buildings.filter((b) =>
        [b.x, b.z, b.w, b.d, b.h].every(Number.isFinite)
        && b.x >= minX - 60 && b.x <= maxX + 60 && b.z >= minZ - 60 && b.z <= maxZ + 60
        // never inside the playing corridor — an OSM footprint mapped over
        // the tee put the camera INSIDE a roof (sky went black)
        && distToPolyline(path, b.x, b.z).dist > fhw + Math.max(b.w, b.d) * 0.6 + 6);
      if (blds.length) {
        const bodyGeo = new THREE.BoxGeometry(1, 1, 1);
        const roofGeo = new THREE.CylinderGeometry(0.02, 0.72, 1, 4, 1);
        const bodyMat = new THREE.MeshLambertMaterial({ color: 0xffffff });
        const roofMat = new THREE.MeshLambertMaterial({ color: 0x4a4742 });
        const bodies = new THREE.InstancedMesh(bodyGeo, bodyMat, blds.length);
        const roofs = new THREE.InstancedMesh(roofGeo, roofMat, blds.length);
        const facades = [0x8f8271, 0x7d7264, 0x97887a, 0x857a6c, 0x6e655a];
        const m4 = new THREE.Matrix4();
        const q = new THREE.Quaternion();
        const up = new THREE.Vector3(0, 1, 0);
        const col = new THREE.Color();
        blds.forEach((b, i) => {
          const w2 = Math.min(46, b.w), d2 = Math.min(46, b.d);
          const gy = heightAt(b.x, b.z);
          const bodyH = Math.min(13, Math.max(3.5, b.h * 0.72));
          q.setFromAxisAngle(up, Number.isFinite(b.rot) ? b.rot : 0);
          m4.compose(new THREE.Vector3(b.x, gy + bodyH / 2, b.z), q, new THREE.Vector3(w2, bodyH, d2));
          bodies.setMatrixAt(i, m4);
          bodies.setColorAt(i, col.setHex(facades[i % facades.length]));
          const roofH = Math.min(4.5, Math.max(1.2, b.h * 0.26));
          q.setFromAxisAngle(up, (Number.isFinite(b.rot) ? b.rot : 0) + Math.PI / 4);
          m4.compose(new THREE.Vector3(b.x, gy + bodyH + roofH / 2, b.z), q, new THREE.Vector3(w2 * 1.02, roofH, d2 * 1.02));
          roofs.setMatrixAt(i, m4);
        });
        bodies.instanceMatrix.needsUpdate = true;
        if (bodies.instanceColor) bodies.instanceColor.needsUpdate = true;
        roofs.instanceMatrix.needsUpdate = true;
        bodies.receiveShadow = true;
        group.add(bodies);
        group.add(roofs);
      }
      const segs = [];
      for (const run of visualZones.walls || []) {
        for (let i = 0; i < run.length - 1; i++) {
          const a = run[i], c = run[i + 1];
          if ((a.x < minX - 40 && c.x < minX - 40) || (a.x > maxX + 40 && c.x > maxX + 40)
            || (a.z < minZ - 40 && c.z < minZ - 40) || (a.z > maxZ + 40 && c.z > maxZ + 40)) continue;
          const len = Math.hypot(c.x - a.x, c.z - a.z);
          if (len >= 0.5) segs.push([a, c, len]);
        }
      }
      if (segs.length) {
        const wallMesh = new THREE.InstancedMesh(
          new THREE.BoxGeometry(1, 1, 1),
          new THREE.MeshLambertMaterial({ color: 0x6d675c }),
          segs.length,
        );
        const m4 = new THREE.Matrix4();
        const q = new THREE.Quaternion();
        const up = new THREE.Vector3(0, 1, 0);
        segs.forEach(([a, c, len], i) => {
          const mx2 = (a.x + c.x) / 2, mz2 = (a.z + c.z) / 2;
          q.setFromAxisAngle(up, Math.atan2(c.x - a.x, c.z - a.z));
          m4.compose(new THREE.Vector3(mx2, heightAt(mx2, mz2) + 0.4, mz2), q, new THREE.Vector3(0.35, 0.8, len + 0.1));
          wallMesh.setMatrixAt(i, m4);
        });
        wallMesh.instanceMatrix.needsUpdate = true;
        group.add(wallMesh);
      }
    }

    // ---------- 3D rough grass: instanced swaying tufts (GSPro step 2) ----------
    if (visualZones.grass3d !== false && !hole.isRange) {
      // tuft geometry: a fan of fine tapered blades with a mid-bend, so each
      // reads as a curved leaf rather than a flat spike. Vertex colours run a
      // base->tip gradient, with per-blade hue jitter (some blades drier/yellow)
      // for a richer, less uniform clump. Kept cheap: ~7 blades, 2 tris each.
      const gPos = [], gCol = [], gIdx = [];
      const baseC = new THREE.Color(0x3a5827);
      const tipLush = new THREE.Color(0x8fbb5c);
      const tipDry = new THREE.Color(0xa8ad63);
      const NB = 7;
      const bTmp = new THREE.Color();
      for (let bIdx = 0; bIdx < NB; bIdx++) {
        const a = (bIdx / NB) * Math.PI * 2 + bIdx * 0.9;
        const ca = Math.cos(a), sa = Math.sin(a);
        const rad = 0.015 + (bIdx % 3) * 0.022;              // fan out into a clump
        const tall = (bIdx % 4 === 0) ? 1.55 : 1.0;          // an occasional flag blade
        const w = 0.016, hgt = (0.10 + (bIdx % 3) * 0.028) * tall;
        const bend = 0.045 + (bIdx % 2) * 0.02;
        const midH = hgt * 0.55, midW = w * 0.62;
        const bx = ca * rad, bz = sa * rad;
        // mid + tip offsets carry the blade over into a gentle arc
        const mx = bx + bend * 0.45 * ca, mz = bz + bend * 0.45 * sa;
        const tx = bx + bend * ca, tz = bz + bend * sa;
        const o = gPos.length / 3;
        gPos.push(
          bx - w * ca, 0, bz - w * sa,           // 0 base L
          bx + w * ca, 0, bz + w * sa,           // 1 base R
          mx - midW * ca, midH, mz - midW * sa,  // 2 mid L
          mx + midW * ca, midH, mz + midW * sa,  // 3 mid R
          tx, hgt, tz,                            // 4 tip
        );
        // drier blades near the clump edge, lush ones central & tall
        const dry = (bIdx % 4 === 0) ? 0.15 : (bIdx % 3) * 0.28;
        bTmp.copy(tipLush).lerp(tipDry, dry);
        gCol.push(
          baseC.r, baseC.g, baseC.b,
          baseC.r, baseC.g, baseC.b,
          baseC.r * 1.12, baseC.g * 1.12, baseC.b * 1.1,
          baseC.r * 1.12, baseC.g * 1.12, baseC.b * 1.1,
          bTmp.r, bTmp.g, bTmp.b,
        );
        gIdx.push(o, o + 2, o + 1,  o + 1, o + 2, o + 3,  o + 2, o + 4, o + 3);
      }
      const tuftGeo = new THREE.BufferGeometry();
      tuftGeo.setAttribute('position', new THREE.Float32BufferAttribute(gPos, 3));
      tuftGeo.setAttribute('color', new THREE.Float32BufferAttribute(gCol, 3));
      tuftGeo.setIndex(gIdx);
      tuftGeo.computeVertexNormals();

      const grassMat = new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide });
      group.userData.grassMat = grassMat;
      grassMat.userData.uniforms = { uTime: { value: 0 } };
      grassMat.onBeforeCompile = (sh) => {
        sh.uniforms.uTime = grassMat.userData.uniforms.uTime;
        sh.vertexShader = 'uniform float uTime;\n' + sh.vertexShader.replace(
          '#include <begin_vertex>',
          `#include <begin_vertex>
          {
            float wx = instanceMatrix[3][0], wz = instanceMatrix[3][2];
            float sway = sin(uTime * 1.6 + wx * 0.37 + wz * 0.29) * 0.05
                       + sin(uTime * 3.1 + wx * 0.83) * 0.02;
            transformed.x += sway * transformed.y * 4.0;
            transformed.z += sway * 0.6 * transformed.y * 4.0;
          }`
        );
      };

      const MAX_TUFTS = 15000;
      const gRng = makeRng(hole.seed * 31 + 7);
      const hCache = new Map();
      const cachedH = (x, z) => {
        const k = ((x * 0.66) | 0) * 100000 + ((z * 0.66) | 0);
        let v = hCache.get(k);
        if (v === undefined) { v = heightAt(x, z); hCache.set(k, v); }
        return v;
      };
      const mats = [];
      const m4 = new THREE.Matrix4();
      const q = new THREE.Quaternion();
      const up = new THREE.Vector3(0, 1, 0);
      const cols = [];
      const cTmp = new THREE.Color();
      for (let seg = 0; seg < path.length - 1 && mats.length < MAX_TUFTS; seg++) {
        const a2 = path[seg], b2 = path[seg + 1];
        const segLen = Math.hypot(b2.x - a2.x, b2.z - a2.z) || 1;
        const dirX = (b2.x - a2.x) / segLen, dirZ = (b2.z - a2.z) / segLen;
        const perpX = -dirZ, perpZ = dirX;
        for (let d = 0; d < segLen && mats.length < MAX_TUFTS; d += 1.1) {
        const cX = a2.x + dirX * d, cZ = a2.z + dirZ * d;
        for (let k2 = 0; k2 < 4; k2++) {
          if (mats.length >= MAX_TUFTS) break;
          const side = gRng() < 0.5 ? -1 : 1;
          const lat = fhw * 0.9 + gRng() * 42;
          // denser just off the fairway, sparser deep
          if (gRng() < (lat - fhw) / 55) continue;
          const dx2 = cX + side * lat * perpX + (gRng() - 0.5) * 2;
          const dz2 = cZ + side * lat * perpZ + (gRng() - 0.5) * 2;
          const su = surfaceAt(dx2, dz2);
          if (su === SURF.SAND || su === SURF.GREEN || su === SURF.TEE || su === SURF.WATER) continue;
          const hh = cachedH(dx2, dz2);
          if (hh < waterLevel + 0.2) continue;
          q.setFromAxisAngle(up, gRng() * Math.PI * 2);
          const sc = 0.7 + gRng() * 0.55;
          m4.compose(new THREE.Vector3(dx2, hh, dz2), q, new THREE.Vector3(sc, sc * (0.8 + gRng() * 0.6), sc));
          mats.push(m4.clone());
          // Richer clump-to-clump variation: mostly green, but a fraction dry
          // out toward hay-gold (deeper into the rough), and lightness varies
          // so the rough never reads as one flat carpet.
          const r1 = gRng();
          if (r1 < 0.16) {
            // dried hay tuft — warmer hue, lower saturation
            cTmp.setHSL(0.16 + gRng() * 0.04, 0.34, 0.44 + gRng() * 0.12);
          } else {
            cTmp.setHSL(0.24 + gRng() * 0.05, 0.40 + gRng() * 0.14, 0.38 + gRng() * 0.16);
          }
          cols.push(cTmp.clone());
        }
        }
      }
      if (mats.length) {
        const tufts = new THREE.InstancedMesh(tuftGeo, grassMat, mats.length);
        mats.forEach((m, i) => { tufts.setMatrixAt(i, m); tufts.setColorAt(i, cols[i]); });
        tufts.instanceMatrix.needsUpdate = true;
        if (tufts.instanceColor) tufts.instanceColor.needsUpdate = true;
        tufts.receiveShadow = true;
        group.add(tufts);
      }
    }

    // ---------- trees: instanced branch-card trees ----------
    const rng = makeRng(hole.seed * 31 + 7);
    spots = [];
    const candidates = treeless ? 0 : Math.floor((hasOcean ? 960 : (forest ? 3200 : 1700)) * (hole.treeDensity || 1));
    const maxRandomTrees = hasOcean ? 245 : (forest ? 950 : 460);
    for (let i = 0; i < candidates && spots.length < maxRandomTrees; i++) {
      const x = minX + 14 + rng() * (maxX - minX - 28);
      const z = minZ + 14 + rng() * (maxZ - minZ - 28);
      const p = pathInfo(x, z);
      const mappedWood = inFeaturePolys(visualWoods, x, z);
      if (p.dist < fhw + 11) continue;
      if (inFeaturePolys(osmFairways, x, z) || inFeaturePolys(osmGreens, x, z)
        || inFeaturePolys(osmTees, x, z) || inFeaturePolys(osmBunkers, x, z)) continue;
      if (ellipseVal(hole.green, x, z) < 3.0) continue;
      if (Math.hypot(x - tee.x, z - tee.z) < 20) continue;
      if (hasWater && waterMask(x, z).m > 0.05) continue;
      if (visualSand.length && inFeaturePolys(visualSand, x, z)) continue;
      if (hasOcean && !mappedWood && p.dist > fhw + 72 && rng() < 0.72) continue;
      if (forest && p.dist > fhw + 95 && rng() < 0.45) continue; // wall hugs the corridor
      if (!forest && fbmDetail(x * 0.02 + 90, z * 0.02) < -0.12) continue; // clearings
      const pineShare = forest?.pineShare ?? (hasOcean ? 0.78 : 0.6);
      // Per-instance foliage colour: one draw controls overall lightness, a
      // second a warm<->cool bias. Correlating them (instead of three
      // independent channels) breaks the flat green wall into a believable mix
      // of lighter/deeper and warmer/cooler crowns while keeping green dominant.
      const lv = 0.76 + rng() * 0.46;              // brightness 0.76..1.22
      const warm = (rng() - 0.42) * 0.34;          // + warm/yellow, - cool/blue
      let tint = forest
        ? [lv * (1 + warm) * 0.98, lv * 1.18, lv * (1 - warm * 0.8) * 0.9]
        : hasOcean
          ? [lv * (1 + warm) * 0.74, lv * 0.9, lv * (1 - warm * 0.6) * 0.76]
          : [lv * (1 + warm) * 1.0, lv * 1.02, lv * (1 - warm * 0.7) * 0.98];
      // Distant trees soften into atmosphere: lift toward a pale, desaturated
      // haze so the far treeline melts into the sky rather than popping.
      const dTee = Math.hypot(x - tee.x, z - tee.z);
      const haze = Math.min(0.55, Math.max(0, (dTee - 240) / 620));
      if (haze > 0) {
        tint = [
          tint[0] + (1.22 - tint[0]) * haze,
          tint[1] + (1.24 - tint[1]) * haze,
          tint[2] + (1.3 - tint[2]) * haze,
        ];
      }
      spots.push({
        x, z, h: heightAt(x, z),
        s: forest
          ? (forest.scaleMin ?? 0.85) + rng() * (forest.scaleRange ?? 1.25)
          : (mappedWood ? 0.86 + rng() * 1.08 : 0.58 + rng() * 0.82),
        ry: rng() * Math.PI * 2,
        tilt: (rng() - 0.5) * 0.08,
        kind: rng() < pineShare
          ? (forest ? (rng() < 0.5 ? 4 : 5) : (rng() < 0.5 ? 0 : 1))
          : (rng() < 0.5 ? 2 : 3),
        tint,
      });
    }
    const DOGWOOD = 9;
    if (visualZones.flora === 'azalea' || visualZones.flora === 'gorse') {
      // Flowering underplanting along the corridor edges (never in play):
      // azalea pinks/whites for parkland, whin-bush green-and-gold for links.
      const gorse = visualZones.flora === 'gorse';
      const aRng = makeRng(hole.seed * 97 + 13);
      // Dogwood blossom tints: pure white to pale pink. The leaf card is
      // green-dominant, so a true white needs the green multiplier held low
      // while red+blue are pushed hard — otherwise green clamps first and the
      // blossom reads mint, not white.
      const dogwoodTints = [
        [4.7, 2.2, 4.9], [4.9, 2.3, 4.6], [5.2, 2.0, 4.4], [4.6, 2.15, 5.1],
      ];
      let dogwoods = 0;
      // Foliage texture is green-heavy, so warm tones need strong multipliers.
      const palette = gorse
        ? [
            [0.5, 0.75, 0.35], [0.42, 0.62, 0.3], [2.6, 2.1, 0.35],
            [0.55, 0.8, 0.4], [2.4, 1.9, 0.3],
          ]
        : [
            // Augusta azaleas + dogwoods: hot pink, crimson, pure white, and
            // magenta. Multipliers are pushed hard (and blue-biased) so the tint
            // reads true pink over the green foliage card, not muddy orange.
            [3.1, 0.5, 1.5], [3.0, 0.3, 0.85], [2.7, 2.55, 2.7],
            [3.0, 0.6, 1.9], [2.6, 1.5, 2.0],
          ];
      // Augusta's azaleas grow in big flowering banks against the tree line and
      // behind greens, so parkland gets many more, larger clumps than the sparse
      // links whin. Cluster seeds spawn a tight burst of blooms for that mass.
      const maxPlaced = gorse ? 200 : 360;
      const bandMax = gorse ? 60 : 54;
      let placed = 0;
      for (let i = 0; i < 6000 && placed < maxPlaced; i++) {
        const x = minX + 14 + aRng() * (maxX - minX - 28);
        const z = minZ + 14 + aRng() * (maxZ - minZ - 28);
        const p = pathInfo(x, z);
        if (p.dist < fhw + 8 || p.dist > fhw + bandMax) continue;
        if (inFeaturePolys(osmFairways, x, z) || inFeaturePolys(osmGreens, x, z)
          || inFeaturePolys(osmTees, x, z) || inFeaturePolys(osmBunkers, x, z)) continue;
        if (ellipseVal(hole.green, x, z) < 2.2) continue;
        if (hasWater && waterMask(x, z).m > 0.05) continue;
        // Dogwoods: standing flowering trees scattered through the azalea banks
        // along the tree line (parkland only). One per seed occasionally, sited
        // toward the outer edge of the flowering band so they read as small
        // trees in front of the pines, not in the azalea foreground.
        if (!gorse && dogwoods < 54 && p.dist > fhw + 18 && aRng() < 0.2) {
          spots.push({
            x, z, h: heightAt(x, z),
            s: 0.58 + aRng() * 0.36,
            ry: aRng() * Math.PI * 2,
            tilt: (aRng() - 0.5) * 0.06,
            kind: DOGWOOD,
            tint: dogwoodTints[Math.floor(aRng() * dogwoodTints.length)].slice(),
          });
          dogwoods++;
          placed++;
          continue;
        }
        // A clump: one dominant colour, several blooms tightly grouped.
        const clumpN = gorse ? 1 : (2 + Math.floor(aRng() * 4));
        const tint = palette[Math.floor(aRng() * palette.length)];
        for (let c = 0; c < clumpN && placed < maxPlaced; c++) {
          const ox = c === 0 ? 0 : (aRng() - 0.5) * 3.4;
          const oz = c === 0 ? 0 : (aRng() - 0.5) * 3.4;
          spots.push({
            x: x + ox, z: z + oz, h: heightAt(x + ox, z + oz),
            s: gorse ? (0.15 + aRng() * 0.16) : (0.26 + aRng() * 0.36),
            ry: aRng() * Math.PI * 2,
            tilt: 0,
            kind: aRng() < 0.5 ? 2 : 3,
            tint: [tint[0], tint[1], tint[2]],
          });
          placed++;
        }
      }
    }
    if (hasOcean) {
      const coastTreeRng = makeRng(hole.seed * 211 + 5);
      const maxCoastalTrees = Math.min(120, 42 + (hole.id === 7 || hole.id === 8 || hole.id === 17 || hole.id === 18 ? 34 : 0));
      let made = 0;
      for (let i = 0; i < coastEdgePts.length * 7 && made < maxCoastalTrees && spots.length < 560; i++) {
        const idx = Math.floor(coastTreeRng() * (coastEdgePts.length - 1));
        const a = coastEdgePts[idx];
        const b = coastEdgePts[idx + 1] || a;
        const n = coastlineOutsideNormal(coastEdgePts, idx, coastLandPts);
        const t = coastTreeRng();
        const x = lerp(a.x, b.x, t) - n.x * (32 + coastTreeRng() * 135);
        const z = lerp(a.z, b.z, t) - n.z * (32 + coastTreeRng() * 135);
        const p = pathInfo(x, z);
        if (!coastalPlayableLand(x, z, p)) continue;
        if (p.dist < fhw + 20 || ellipseVal(hole.green, x, z) < 5.0 || Math.hypot(x - tee.x, z - tee.z) < 28) continue;
        if (inFeaturePolys(osmFairways, x, z) || inFeaturePolys(osmGreens, x, z)
          || inFeaturePolys(osmTees, x, z) || inFeaturePolys(osmBunkers, x, z)) continue;
        spots.push({
          x, z, h: heightAt(x, z),
          s: 0.9 + coastTreeRng() * 1.25,
          ry: coastTreeRng() * Math.PI * 2,
          tilt: -0.08 + coastTreeRng() * 0.16,
          kind: coastTreeRng() < 0.86 ? 0 : 1,
          tint: [0.58 + coastTreeRng() * 0.16, 0.69 + coastTreeRng() * 0.18, 0.58 + coastTreeRng() * 0.14],
        });
        made++;
      }
    }
    if (hole.isRange && hole.rangeScenery?.treeBelts) {
      const rangeTreeRng = makeRng(hole.seed * 313 + 17);
      const backZ = path[path.length - 1].z;
      const sideRows = [
        { x: minX + 28, wob: 18 },
        { x: maxX - 28, wob: -18 },
        { x: minX + 58, wob: -12 },
        { x: maxX - 58, wob: 12 },
      ];
      for (const row of sideRows) {
        for (let z = tee.z + 18; z <= backZ + 74; z += 18 + rangeTreeRng() * 12) {
          const x = row.x + Math.sin(z * 0.028 + row.wob) * 9 + (rangeTreeRng() - 0.5) * 14;
          const p = pathInfo(x, z);
          if (p.dist < fhw + 18) continue;
          spots.push({
            x, z, h: heightAt(x, z),
            s: 0.92 + rangeTreeRng() * 1.25,
            ry: rangeTreeRng() * Math.PI * 2,
            tilt: (rangeTreeRng() - 0.5) * 0.09,
            kind: rangeTreeRng() < 0.72 ? (rangeTreeRng() < 0.58 ? 0 : 1) : (rangeTreeRng() < 0.5 ? 2 : 3),
            tint: [0.68 + rangeTreeRng() * 0.22, 0.79 + rangeTreeRng() * 0.22, 0.66 + rangeTreeRng() * 0.18],
          });
        }
      }
      for (let i = 0; i < 78; i++) {
        const x = minX + 28 + rangeTreeRng() * (maxX - minX - 56);
        const z = backZ + 26 + rangeTreeRng() * 86;
        const p = pathInfo(x, z);
        if (p.dist < fhw + 10 && rangeTreeRng() < 0.72) continue;
        spots.push({
          x, z, h: heightAt(x, z),
          s: 0.8 + rangeTreeRng() * 1.35,
          ry: rangeTreeRng() * Math.PI * 2,
          tilt: (rangeTreeRng() - 0.5) * 0.08,
          kind: rangeTreeRng() < 0.8 ? (rangeTreeRng() < 0.62 ? 0 : 1) : 2,
          tint: [0.62 + rangeTreeRng() * 0.2, 0.75 + rangeTreeRng() * 0.22, 0.62 + rangeTreeRng() * 0.16],
        });
      }
    }

    // Corridor trees get the dense near-LOD canopy (where the camera lands).
    // Dogwoods (kind 9) are already a bespoke near-LOD understory tree — leave
    // them alone or the remap would turn them into dense pines.
    for (const t of spots) {
      if (t.kind === 9) continue;
      if (pathInfo(t.x, t.z).dist < fhw + 40) {
        t.kind = t.kind <= 1 ? 6 : (t.kind <= 3 ? 7 : 8);
      }
    }
    const kit = treeKit(assets);
    const m4 = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    const eu = new THREE.Euler();
    const v3 = new THREE.Vector3();
    const s3 = new THREE.Vector3();
    const col = new THREE.Color();

    function setInstances(im, mine, tinted) {
      mine.forEach((t, i) => {
        eu.set(t.tilt, t.ry, t.tilt * 0.7);
        q.setFromEuler(eu);
        v3.set(t.x, t.h - 0.12, t.z);
        s3.set(t.s, t.s, t.s);
        m4.compose(v3, q, s3);
        im.setMatrixAt(i, m4);
        if (tinted) {
          col.setRGB(t.tint[0], t.tint[1], t.tint[2]);
          im.setColorAt(i, col);
        }
      });
      im.instanceMatrix.needsUpdate = true;
      if (im.instanceColor) im.instanceColor.needsUpdate = true;
      group.add(im);
    }

    for (let k = 0; k < kit.canopies.length; k++) {
      const mine = spots.filter(t => t.kind === k);
      if (!mine.length) continue;
      const c = kit.canopies[k];
      const im = new THREE.InstancedMesh(c.geo, c.mat, mine.length);
      im.customDepthMaterial = c.depth;
      im.castShadow = true;
      setInstances(im, mine, true);
    }
    for (const species of ['pine', 'leaf', 'pineTall']) {
      const mine = spots.filter(t => kit.canopies[t.kind].trunk === species);
      if (!mine.length) continue;
      const tk = kit.trunks[species];
      const im = new THREE.InstancedMesh(tk.geo, tk.mat, mine.length);
      im.castShadow = true;
      setInstances(im, mine, false);
    }

    // ---------- layered horizon: distant ridgelines with atmospheric depth ----------
    // Three concentric silhouette rings — near treeline, mid hills, far
    // mountains — each taller, hazier, bluer. This is what makes a course sit
    // in a real landscape instead of behind a flat band (GSPro look).
    const ccx = (minX + maxX) / 2, ccz = (minZ + maxZ) / 2;
    const fbmBack = makeFbm(hole.seed + 77, 3);
    const baseR = Math.max(maxX - ccx, maxZ - ccz);
    const hazeSky = new THREE.Color(visualZones.hazeColor ?? 0xbcccdb);
    function ridgeRing(rad, segs, floorY, baseH, ampH, freq, groundC, crestHaze, seedOff, dip) {
      const geo = new THREE.CylinderGeometry(rad, rad, 1, segs, 1, true);
      const pos = geo.attributes.position;
      const cols = new Float32Array(pos.count * 3);
      const ground = new THREE.Color(groundC);
      const crest = ground.clone().lerp(hazeSky, crestHaze);
      const c = new THREE.Color();
      for (let i = 0; i < pos.count; i++) {
        const x = pos.getX(i), z = pos.getZ(i);
        const top = pos.getY(i) > 0;
        const a = Math.atan2(z, x);
        // multi-octave silhouette so peaks and valleys read distinct
        const n = (fbmBack(Math.cos(a) * freq + seedOff, Math.sin(a) * freq) * 0.5 + 0.5)
          * 0.7 + (fbmBack(Math.cos(a) * freq * 2.7 + 9, Math.sin(a) * freq * 2.7) * 0.5 + 0.5) * 0.3;
        // optional dip toward the ocean side so the sea horizon stays open
        let h = baseH + n * ampH;
        if (dip) {
          const oceanBias = Math.max(0, Math.cos(a - dip)) ** 2;
          h *= 1 - oceanBias * 0.72;
        }
        pos.setY(i, top ? floorY + h : floorY - 8);
        c.copy(top ? crest : ground);
        cols[i * 3] = c.r; cols[i * 3 + 1] = c.g; cols[i * 3 + 2] = c.b;
      }
      geo.setAttribute('color', new THREE.BufferAttribute(cols, 3));
      const m = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({
        vertexColors: true, side: THREE.BackSide, fog: true, depthWrite: false,
      }));
      m.position.set(ccx, 0, ccz);
      m.renderOrder = -1;
      group.add(m);
    }
    // Point the ocean-dip toward the sea (coastal only)
    const oceanDir = hasOcean ? Math.atan2(0, 1) : null;
    if (treeless) {
      // Flat coastal links (St Andrews): no hills, no mountains. A low, distant
      // band of farmland/dunes melting into a big grey sky — the town buildings
      // supply the only real skyline.
      ridgeRing(baseR + 260, 112, 0, 4, 6, 2.1, 0x6d7856, 0.55, 4, oceanDir);       // low dune/links band
      ridgeRing(baseR + 1000, 80, 0, 8, 10, 1.5, 0x8a9285, 0.8, 37, oceanDir);      // faint far shore, mostly haze
    } else if (forest) {
      // Rolling wooded country (Augusta): green pine ridges all the way out —
      // never bare grey mountains. Lower and greener than the default massif.
      ridgeRing(baseR + 150, 128, 0, 14, 22, 2.4, 0x2c4724, 0.30, 4, null);          // near pine wall
      ridgeRing(baseR + 620, 96, 0, 30, 48, 1.7, 0x334a2c, 0.55, 31, null);          // mid wooded hills
      ridgeRing(baseR + 1500, 80, 0, 46, 78, 1.1, 0x45583d, 0.80, 57, null);         // far wooded ridge (green)
    } else {
      ridgeRing(baseR + 150, 128, 0, 12, 16, 2.4, 0x33502b, 0.35, 4, null);          // near treeline
      ridgeRing(baseR + 620, 96, 0, 34, 60, 1.7, 0x3f5744, 0.62, 31, oceanDir);      // mid hills
      ridgeRing(baseR + 1500, 80, 0, 70, 150, 1.1, 0x5a6f78, 0.82, 57, oceanDir);    // far mountains
    }

    if (hole.isRange && hole.rangeScenery?.mountains) {
      const mountainRng = makeRng(hole.seed * 421 + 9);
      const mountainBase = Math.min(heightAt(minX, maxZ), heightAt(maxX, maxZ), heightAt(0, maxZ)) - 1.8;
      const makeRangeFoothills = ({ width, depth, zStart, height, colorLow, colorHigh, alpha, seedOffset }) => {
        const cols = 92;
        const rows = 34;
        const positions = [];
        const colors = [];
        const indices = [];
        const low = new THREE.Color(colorLow);
        const high = new THREE.Color(colorHigh);
        const noise = makeFbm(hole.seed * 19 + seedOffset, 4);
        const cx = (minX + maxX) / 2;
        for (let iz = 0; iz <= rows; iz++) {
          const v = iz / rows;
          for (let ix = 0; ix <= cols; ix++) {
            const u = ix / cols;
            const x = cx - width / 2 + u * width;
            const z = zStart + v * depth;
            const ridgeCenter = 0.36
              + 0.12 * Math.sin(u * Math.PI * 2.7 + seedOffset)
              + 0.08 * noise(u * 2.1 + 4, seedOffset * 0.13);
            const ridge = Math.exp(-((v - ridgeCenter) ** 2) / 0.075);
            const farRidge = Math.exp(-((v - 0.74) ** 2) / 0.115) * 0.36;
            const sideFalloff = Math.sin(Math.PI * u) * 0.32 + 0.68;
            const broad = noise(u * 3.4 + 11, v * 2.4 - 7) * 0.5 + 0.5;
            const detail = noise(u * 11.5 - 4, v * 7.2 + 18) * 0.5 + 0.5;
            const y = mountainBase
              + (ridge * height + farRidge * height * 0.8) * sideFalloff
              + broad * height * 0.26
              + detail * height * 0.055
              - v * 10;
            positions.push(x, y, z);
            const shade = Math.min(Math.max((y - mountainBase) / (height * 1.2), 0), 1);
            const haze = 0.32 + v * 0.40;
            const c = low.clone().lerp(high, shade * 0.58).lerp(new THREE.Color(0xb6c9d8), haze);
            colors.push(c.r, c.g, c.b);
          }
        }
        for (let iz = 0; iz < rows; iz++) {
          for (let ix = 0; ix < cols; ix++) {
            const a = iz * (cols + 1) + ix;
            indices.push(a, a + cols + 1, a + 1, a + 1, a + cols + 1, a + cols + 2);
          }
        }
        const geo = new THREE.BufferGeometry();
        geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
        geo.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
        geo.setIndex(indices);
        geo.computeVertexNormals();
        const mesh = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({
          vertexColors: true,
          transparent: true,
          opacity: alpha,
          fog: true,
          depthWrite: false,
          side: THREE.FrontSide,
        }));
        mesh.receiveShadow = false;
        group.add(mesh);
      };
      makeRangeFoothills({
        width: (maxX - minX) * 2.3,
        depth: 520,
        zStart: maxZ + 55,
        height: 48,
        colorLow: 0x3b6245,
        colorHigh: 0x7b9478,
        alpha: 0.76,
        seedOffset: 3,
      });
      makeRangeFoothills({
        width: (maxX - minX) * 2.9,
        depth: 760,
        zStart: maxZ + 370,
        height: 86,
        colorLow: 0x334d43,
        colorHigh: 0x718276,
        alpha: 0.44,
        seedOffset: 23,
      });
      makeRangeFoothills({
        width: (maxX - minX) * 3.4,
        depth: 1040,
        zStart: maxZ + 780,
        height: 136,
        colorLow: 0x35454a,
        colorHigh: 0x7a8890,
        alpha: 0.28,
        seedOffset: 47,
      });
    }

    // ---------- tree contact AO: soft shadow discs at every trunk base ----------
    // (GSPro step 3a) grounds the card trees — without these they float. The
    // disc has a dark contact core fading to a long soft edge, and is stretched
    // + offset along the sun-shadow direction so the pool reads as a real cast
    // shadow raking away from each trunk rather than a flat symmetric blob.
    if (spots.length) {
      const aoCv = document.createElement('canvas');
      aoCv.width = aoCv.height = 64;
      const aoCtx = aoCv.getContext('2d');
      const aoG = aoCtx.createRadialGradient(32, 32, 2, 32, 32, 31);
      aoG.addColorStop(0, 'rgba(8,14,6,0.5)');
      aoG.addColorStop(0.35, 'rgba(9,15,7,0.32)');
      aoG.addColorStop(0.7, 'rgba(10,16,8,0.13)');
      aoG.addColorStop(1, 'rgba(10,16,8,0)');
      aoCtx.fillStyle = aoG;
      aoCtx.fillRect(0, 0, 64, 64);
      const aoTex = new THREE.CanvasTexture(aoCv);
      const aoMesh = new THREE.InstancedMesh(
        new THREE.PlaneGeometry(1, 1),
        new THREE.MeshBasicMaterial({ map: aoTex, transparent: true, depthWrite: false }),
        Math.min(spots.length, 1400),
      );
      // Orient the ellipse's long axis along the ground-projected shadow.
      const shx = -assets.sunDir.x, shz = -assets.sunDir.z;
      const shLen = Math.hypot(shx, shz) || 1;
      const sux = shx / shLen, suz = shz / shLen;
      const phi = Math.atan2(-suz, sux);
      const qa = new THREE.Quaternion()
        .setFromAxisAngle(new THREE.Vector3(0, 1, 0), phi)
        .multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0, 0), -Math.PI / 2));
      const m4a = new THREE.Matrix4();
      const posA = new THREE.Vector3();
      const scaleA = new THREE.Vector3();
      let na = 0;
      for (const t of spots) {
        if (na >= aoMesh.count) break;
        // dogwoods (9) are small, tall pines (loblolly) throw a wider pool
        const base = t.kind === 9 ? 1.7 : (t.kind === 0 || t.kind === 1 || t.kind === 6) ? 2.6 : 3.3;
        const r = base * t.s;
        const long = r * 1.4, short = r * 0.92;
        const off = (long - r) * 0.8;
        posA.set(
          t.x + sux * off,
          heightAt(t.x, t.z) + 0.025 + (na % 7) * 0.002,
          t.z + suz * off,
        );
        scaleA.set(long, short, 1);
        m4a.compose(posA, qa, scaleA);
        aoMesh.setMatrixAt(na++, m4a);
      }
      aoMesh.count = na;
      aoMesh.instanceMatrix.needsUpdate = true;
      aoMesh.renderOrder = 1;
      group.add(aoMesh);
    }

    // ---------- birds: distant circling silhouettes ----------
    const birds = [];
    {
      const bgeo = new THREE.PlaneGeometry(1.6, 0.5);
      const bcv = document.createElement('canvas');
      bcv.width = 64; bcv.height = 20;
      const bctx = bcv.getContext('2d');
      bctx.strokeStyle = 'rgba(20,24,20,0.9)';
      bctx.lineWidth = 3;
      bctx.lineCap = 'round';
      bctx.beginPath();
      bctx.moveTo(4, 16); bctx.quadraticCurveTo(20, 2, 32, 14);
      bctx.quadraticCurveTo(44, 2, 60, 16);
      bctx.stroke();
      const btex = new THREE.CanvasTexture(bcv);
      const bmat = new THREE.MeshBasicMaterial({
        map: btex, transparent: true, depthWrite: false, side: THREE.DoubleSide,
      });
      for (let i = 0; i < 5; i++) {
        const b = new THREE.Mesh(bgeo, bmat);
        b.rotation.x = -Math.PI / 2;
        b.userData = { i, r: 90 + i * 18, h: 42 + i * 5, ph: i * 1.37 };
        group.add(b);
        birds.push(b);
      }
    }

    // everything that breathes, drifts, or sways
    updateWater = (t, wind) => {
      if (oceanMesh) oceanMesh.material.uniforms.time.value = t * 0.35;
      for (const w of waters) w.material.uniforms.time.value = t * 0.5;
      for (const fn of flatWaters) { fn.offset.x = t * 0.008; fn.offset.y = t * 0.011; }
      const sh = terrain.material.userData.shader;
      if (sh) {
        sh.uniforms.uTime.value = t;
        if (wind) sh.uniforms.uWindVec.value.set(wind.x, wind.z);
      }
      for (const s of kit.swayShaders) {
        s.uniforms.uTime.value = t;
        if (wind) s.uniforms.uWind.value = wind.speed;
      }
      for (const b of birds) {
        const u = b.userData;
        const ang = t * 0.045 + u.ph;
        b.position.set(
          ccx + Math.cos(ang) * u.r * 1.5,
          u.h + Math.sin(t * 0.5 + u.ph) * 3,
          ccz + Math.sin(ang) * u.r,
        );
        b.rotation.set(-Math.PI / 2, 0, -ang);
        b.scale.y = 1 + Math.sin(t * 8 + u.ph * 3) * 0.35;  // wing-beat shimmer
      }
    };

    // ---------- flag, cup, tee markers ----------
    const flagGroup = new THREE.Group();
    const pole = new THREE.Mesh(
      new THREE.CylinderGeometry(0.022, 0.022, 2.25, 8),
      new THREE.MeshLambertMaterial({ color: 0xf4f1e6 }),
    );
    pole.position.y = 1.125;
    pole.castShadow = true;
    flagGroup.add(pole);

    const flagGeo = new THREE.PlaneGeometry(0.62, 0.4, 8, 3);
    flagGeo.translate(0.31, 0, 0);
    const flagBase = flagGeo.attributes.position.array.slice();
    const flag = new THREE.Mesh(
      flagGeo,
      new THREE.MeshLambertMaterial({ color: 0xc23a28, side: THREE.DoubleSide }),
    );
    flag.position.y = 2.0;
    flagGroup.add(flag);

    const cup = new THREE.Mesh(
      new THREE.CircleGeometry(0.075, 20),
      new THREE.MeshBasicMaterial({ color: 0x10160f }),
    );
    cup.rotation.x = -Math.PI / 2;
    cup.position.y = 0.012;
    flagGroup.add(cup);
    flagGroup.position.set(pinPos.x, pinPos.y, pinPos.z);
    group.add(flagGroup);

    // ---------- green-reading heatmap (filled elevation surface + fall-line arrows) ----------
    {
      const gdef = hole.green;
      const R = Math.max(gdef.rx, gdef.rz) * 1.28;
      const STEP = 0.7;                                    // heatmap cell size (m)
      const inside = (x, z) => ellipseVal(gdef, x, z) <= 1.06;

      // Height range across the green, for normalizing the color ramp.
      let hMin = Infinity, hMax = -Infinity;
      for (let gx = -R; gx <= R; gx += STEP) {
        for (let gz = -R; gz <= R; gz += STEP) {
          const x = gdef.cx + gx, z = gdef.cz + gz;
          if (!inside(x, z)) continue;
          const hh = heightAt(x, z);
          if (hh < hMin) hMin = hh;
          if (hh > hMax) hMax = hh;
        }
      }
      const span = Math.max(hMax - hMin, 0.05);

      // Elevation ramp for a green-book style overlay: low = cool blue, high =
      // warm amber. Deliberately NO pure red (reads as "danger", not terrain) and
      // no grass-green mid-tones (they would vanish into the turf).
      const RAMP = [
        [0.00, new THREE.Color(0x3577d6)],  // low  — blue
        [0.34, new THREE.Color(0x37bfb0)],  // teal
        [0.62, new THREE.Color(0xe9dc5c)],  // soft yellow
        [1.00, new THREE.Color(0xe89a3c)],  // high — amber
      ];
      const _rc = new THREE.Color();
      const ramp = (t) => {
        t = t < 0 ? 0 : t > 1 ? 1 : t;
        for (let i = 1; i < RAMP.length; i++) {
          if (t <= RAMP[i][0]) {
            const a = RAMP[i - 1], b = RAMP[i];
            const f = (t - a[0]) / ((b[0] - a[0]) || 1);
            return _rc.copy(a[1]).lerp(b[1], f);
          }
        }
        return _rc.copy(RAMP[RAMP.length - 1][1]);
      };

      const heatGroup = new THREE.Group();

      // --- filled, translucent heatmap surface (triangulated grid) ---
      const pos = [], col = [];
      const steps = Math.ceil((2 * R) / STEP);
      const push = (x, z, h) => {
        pos.push(x, h + 0.06, z);
        const c = ramp((h - hMin) / span);
        col.push(c.r, c.g, c.b);
      };
      for (let ix = 0; ix < steps; ix++) {
        for (let iz = 0; iz < steps; iz++) {
          const x0 = gdef.cx - R + ix * STEP, z0 = gdef.cz - R + iz * STEP;
          const x1 = x0 + STEP, z1 = z0 + STEP;
          // Emit a quad only where all four corners lie on the green.
          if (!(inside(x0, z0) && inside(x1, z0) && inside(x1, z1) && inside(x0, z1))) continue;
          const c00 = heightAt(x0, z0), c10 = heightAt(x1, z0);
          const c11 = heightAt(x1, z1), c01 = heightAt(x0, z1);
          push(x0, z0, c00); push(x1, z0, c10); push(x1, z1, c11);
          push(x0, z0, c00); push(x1, z1, c11); push(x0, z1, c01);
        }
      }
      if (pos.length) {
        const fgeo = new THREE.BufferGeometry();
        fgeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(pos), 3));
        fgeo.setAttribute('color', new THREE.BufferAttribute(new Float32Array(col), 3));
        const fill = new THREE.Mesh(fgeo, new THREE.MeshBasicMaterial({
          vertexColors: true, transparent: true, opacity: 0.42,
          depthWrite: false, side: THREE.DoubleSide,
        }));
        fill.renderOrder = 2;
        heatGroup.add(fill);
      }

      // --- fall-line chevrons: brighter downhill arrows so the read is directional ---
      const lpos = [], lcol = [];
      const white = new THREE.Color(0xffffff);
      for (let gx = -R; gx <= R; gx += 3) {
        for (let gz = -R; gz <= R; gz += 3) {
          const x = gdef.cx + gx, z = gdef.cz + gz;
          if (ellipseVal(gdef, x, z) > 0.94) continue;      // keep arrows off the fringe
          const e2 = 0.6;
          const sx = heightAt(x + e2, z) - heightAt(x - e2, z);
          const sz = heightAt(x, z + e2) - heightAt(x, z - e2);
          const mag = Math.hypot(sx, sz);
          if (mag < 0.006) continue;                        // dead flat: no arrow
          const dx = -sx / mag, dz = -sz / mag;             // downhill direction
          const len = Math.min(1.3, 0.55 + mag * 10);
          const hx = x + dx * len, hz = z + dz * len;
          const hh0 = heightAt(x, z) + 0.09, hh1 = heightAt(hx, hz) + 0.09;
          _rc.copy(ramp((heightAt(x, z) - hMin) / span)).lerp(white, 0.62);
          const cr = _rc.r, cg = _rc.g, cb = _rc.b;
          lpos.push(x, hh0, z, hx, hh1, hz);
          lcol.push(cr, cg, cb, cr, cg, cb);
          for (const side of [1, -1]) {
            const bx2 = hx - dx * 0.30 + side * -dz * 0.20;
            const bz2 = hz - dz * 0.30 + side * dx * 0.20;
            lpos.push(hx, hh1, hz, bx2, heightAt(bx2, bz2) + 0.06, bz2);
            lcol.push(cr, cg, cb, cr, cg, cb);
          }
        }
      }
      if (lpos.length) {
        const lgeo = new THREE.BufferGeometry();
        lgeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(lpos), 3));
        lgeo.setAttribute('color', new THREE.BufferAttribute(new Float32Array(lcol), 3));
        const arrows = new THREE.LineSegments(lgeo, new THREE.LineBasicMaterial({
          vertexColors: true, transparent: true, opacity: 0.9, depthWrite: false,
        }));
        arrows.renderOrder = 3;
        heatGroup.add(arrows);
      }

      heatGroup.visible = false;
      group.add(heatGroup);
      group.userData.greenGrid = heatGroup;
    }

    // ---------- OB stakes along the corridor ----------
    {
      const stakes = [];
      let L = 0;
      for (let i = 1; i < path.length; i++) {
        L += Math.hypot(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z);
      }
      for (let s = 0; s <= L; s += 24) {
        const p = pointAtAlong(s);
        const p2 = pointAtAlong(Math.min(s + 2, L));
        let tx = p2.x - p.x, tz = p2.z - p.z;
        const tl = Math.hypot(tx, tz) || 1;
        tx /= tl; tz /= tl;
        for (const side of [-1, 1]) {
          const sx = p.x + -tz * side * (obDist - 2);
          const sz = p.z + tx * side * (obDist - 2);
          if (hasWater && waterMask(sx, sz).m > 0.05) continue;
          stakes.push({ x: sx, z: sz, h: heightAt(sx, sz) });
        }
      }
      if (stakes.length) {
        const sgeo = new THREE.CylinderGeometry(0.045, 0.045, 1.15, 6);
        const smat = new THREE.MeshLambertMaterial({ color: 0xf5f2e8 });
        const im = new THREE.InstancedMesh(sgeo, smat, stakes.length);
        const sm4 = new THREE.Matrix4();
        stakes.forEach((st, i) => {
          sm4.makeTranslation(st.x, st.h + 0.55, st.z);
          im.setMatrixAt(i, sm4);
        });
        im.instanceMatrix.needsUpdate = true;
        im.castShadow = true;
        group.add(im);
      }
    }

    const teeMarkMat = new THREE.MeshBasicMaterial({ color: 0xe8e3d2 });
    for (const side of [-1, 1]) {
      const mark = new THREE.Mesh(new THREE.SphereGeometry(0.1, 10, 8), teeMarkMat);
      mark.position.set(tee.x + side * 2.2, teeH + 0.1, tee.z);
      group.add(mark);
    }

    updateFlag = function (t, windSpeed = 4) {
      const arr = flagGeo.attributes.position.array;
      const amp = 0.03 + windSpeed * 0.012;
      for (let i = 0; i < arr.length; i += 3) {
        const bx = flagBase[i];
        arr[i + 2] = Math.sin(bx * 9 - t * (3 + windSpeed * 0.7)) * amp * bx;
      }
      flagGeo.attributes.position.needsUpdate = true;
      flagGeo.computeVertexNormals();
    };
  }

  function dispose() {
    if (!group) return;
    group.traverse((o) => {
      if (o.geometry) o.geometry.dispose();
      if (o.material && !o.isWater) {
        if (Array.isArray(o.material)) o.material.forEach(m => m.dispose());
        else o.material.dispose();
      }
    });
  }

  return {
    group, heightAt, surfaceAt, normalAt, waterLevel,
    conditions: hole.island?.conditions || null,
    pinPos, teePos: { x: tee.x, y: teeH, z: tee.z },
    pointAtAlong, pathInfo, isOB, updateFlag, updateWater, dispose,
    updateGrass(t) { const gm = group?.userData?.grassMat; if (gm) gm.userData.uniforms.uTime.value = t; },
    greenGrid: group ? group.userData.greenGrid : null,
    bounds: { minX, maxX, minZ, maxZ },
    trees: spots.map(t => ({ x: t.x, z: t.z, h: t.h, s: t.s, isPine: t.kind <= 1 })),
  };
}
