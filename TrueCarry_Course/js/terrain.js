// Full-course terrain using TrueCarry_Sim PBR pipeline:
// real photo-texture splatting, branch-card trees, Three.js Water, HDRI sky.

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { Water }           from 'three/addons/objects/Water.js';
import { makeFbm, makeRng } from './noise.js';

// ---------- Surface constants ----------
export const SURF = {
  ROUGH:    'rough',
  FAIRWAY:  'fairway',
  GREEN:    'green',
  BUNKER:   'bunker',
  WATER:    'water',
  CARTPATH: 'cartpath',
  OOB:      'oob',
};

export const SURF_PROPS = {
  [SURF.ROUGH]:    { restitution: 0.22, friction: 0.72, spin: 0.45, run: 0.5 },
  [SURF.FAIRWAY]:  { restitution: 0.32, friction: 0.58, spin: 0.82, run: 1.6 },
  [SURF.GREEN]:    { restitution: 0.18, friction: 0.88, spin: 1.00, run: 1.0 },
  [SURF.BUNKER]:   { restitution: 0.03, friction: 0.95, spin: 0.40, run: 0.2 },
  [SURF.WATER]:    { restitution: 0.00, friction: 1.00, spin: 0.00, run: 0.0 },
  [SURF.CARTPATH]: { restitution: 0.55, friction: 0.35, spin: 0.20, run: 3.5 },
  [SURF.OOB]:      { restitution: 0.20, friction: 0.70, spin: 0.40, run: 0.5 },
};

// ---------- Heightmap bilinear interpolation ----------
function makeHeightmap(hm) {
  const minElev = Math.min(...hm.data);
  const norm = hm.data.map(e => e - minElev);
  function heightAt(x, z) {
    const col = (x - hm.originX) / hm.cellSize;
    const row = (z - hm.originZ) / hm.cellSize;
    if (col < 0 || col > hm.cols - 1 || row < 0 || row > hm.rows - 1) return 0;
    const c0 = Math.floor(col), c1 = Math.min(c0 + 1, hm.cols - 1);
    const r0 = Math.floor(row), r1 = Math.min(r0 + 1, hm.rows - 1);
    const fc = col - c0, fr = row - r0;
    return norm[r0*hm.cols+c0]*(1-fc)*(1-fr) + norm[r0*hm.cols+c1]*fc*(1-fr)
         + norm[r1*hm.cols+c0]*(1-fc)*fr     + norm[r1*hm.cols+c1]*fc*fr;
  }
  return { heightAt, minElev };
}

// ---------- Surface polygon grid ----------
function pip(px, pz, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, zi] = poly[i], [xj, zj] = poly[j];
    if ((zi > pz) !== (zj > pz) && px < ((xj - xi) * (pz - zi)) / (zj - zi) + xi) inside = !inside;
  }
  return inside;
}

function makeSurfaceMap(courseData, hmOriginX, hmOriginZ, hmWidth, hmDepth) {
  const RES = 4;
  const cols = Math.ceil(hmWidth / RES) + 1;
  const rows = Math.ceil(hmDepth / RES) + 1;
  const grid = new Uint8Array(cols * rows);
  const ROUGH=0, FAIRWAY=1, GREEN=2, BUNKER=3, WATER=4, CARTPATH=5;

  function paint(poly, val) {
    if (!poly || poly.length < 3) return;
    const xs = poly.map(p => p[0]), zs = poly.map(p => p[1]);
    const minXi = Math.max(0, Math.floor((Math.min(...xs) - hmOriginX) / RES));
    const maxXi = Math.min(cols-1, Math.ceil((Math.max(...xs) - hmOriginX) / RES));
    const minZi = Math.max(0, Math.floor((Math.min(...zs) - hmOriginZ) / RES));
    const maxZi = Math.min(rows-1, Math.ceil((Math.max(...zs) - hmOriginZ) / RES));
    for (let r = minZi; r <= maxZi; r++) {
      for (let c = minXi; c <= maxXi; c++) {
        if (pip(hmOriginX + c*RES, hmOriginZ + r*RES, poly)) grid[r*cols+c] = val;
      }
    }
  }

  // Paint a polyline as a corridor of given half-width
  function paintPath(pts, halfWidth, val) {
    if (!pts || pts.length < 2) return;
    for (let i = 0; i < pts.length - 1; i++) {
      const [ax, az] = pts[i], [bx, bz] = pts[i + 1];
      const dx = bx - ax, dz = bz - az;
      const len = Math.hypot(dx, dz) || 1;
      const nx = dz / len, nz = -dx / len; // perpendicular
      const corridor = [
        [ax + nx * halfWidth, az + nz * halfWidth],
        [bx + nx * halfWidth, bz + nz * halfWidth],
        [bx - nx * halfWidth, bz - nz * halfWidth],
        [ax - nx * halfWidth, az - nz * halfWidth],
      ];
      paint(corridor, val);
    }
  }

  for (const hole of courseData.holes) paint(hole.fairway, FAIRWAY);
  for (const hole of courseData.holes) {
    for (const b of hole.bunkers) paint(b, BUNKER);
    for (const w of hole.water) paint(w, WATER);
  }
  for (const hole of courseData.holes) {
    if (hole.green.polygon) paint(hole.green.polygon, GREEN);
  }
  // Cart paths painted on top (they overlap fairway/rough)
  for (const path of (courseData.cartPaths || [])) {
    paintPath(path, 1.8, CARTPATH);
  }

  const SURF_TABLE = [SURF.ROUGH, SURF.FAIRWAY, SURF.GREEN, SURF.BUNKER, SURF.WATER, SURF.CARTPATH];
  function surfaceAt(x, z) {
    const col = Math.round((x - hmOriginX) / RES);
    const row = Math.round((z - hmOriginZ) / RES);
    if (col < 0 || col >= cols || row < 0 || row >= rows) return SURF.OOB;
    return SURF_TABLE[grid[row*cols+col]] || SURF.OOB;
  }
  return { surfaceAt, grid, cols, rows };
}

// ---------- PBR splat material (ported from TrueCarry_Sim) ----------
// vertex colors supply the designed hue; photo textures add structure only.
function splatMaterial(assets) {
  const g = assets.ground;
  const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 1.0, metalness: 0 });
  mat.envMapIntensity = 0.3;
  mat.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, {
      uGrassD: { value: g.grassD }, uGrassN: { value: g.grassN },
      uRoughD: { value: g.roughD }, uRoughN: { value: g.roughN },
      uSandD:  { value: g.sandD  }, uSandN:  { value: g.sandN  },
      uGrassMean: { value: g.grassMean },
      uRoughMean: { value: g.roughMean },
      uSandMean:  { value: g.sandMean  },
      uTime:    { value: 0 },
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
        uniform sampler2D uGrassD, uGrassN, uRoughD, uRoughN, uSandD, uSandN;
        uniform vec3 uGrassMean, uRoughMean, uSandMean;
        uniform float uTime;
        uniform vec2 uWindVec;
        vec2 uvFair()  { return vWPos.xz * 0.27; }
        vec2 uvGreen() { return vWPos.xz * 0.9;  }
        vec2 uvRough() { return vWPos.xz * 0.16; }
        vec2 uvSand()  { return vWPos.xz * 0.3;  }`)
      .replace('#include <color_fragment>', `#include <color_fragment>
        {
          vec3 gA = texture2D(uGrassD, uvFair()).rgb  / uGrassMean;
          vec3 gB = texture2D(uGrassD, uvGreen()).rgb / uGrassMean;
          vec3 grassC = mix(gA, gB, vSplat.w);
          vec3 roughC = texture2D(uRoughD, uvRough()).rgb / uRoughMean;
          vec3 sandC  = texture2D(uSandD,  uvSand()).rgb  / uSandMean;
          vec3 structure = grassC * vSplat.x + roughC * vSplat.y + sandC * vSplat.z;
          structure = mix(vec3(1.0), structure, 0.85);
          diffuseColor.rgb *= clamp(structure, 0.25, 1.9);
          // drifting cloud shadows
          vec2 cuv = vWPos.xz * 0.0011 + uWindVec * uTime * 0.0022 + vec2(0.0, uTime * 0.0006);
          float cn = texture2D(uRoughD, cuv).g * 0.62
                   + texture2D(uRoughD, cuv * 2.7 + 0.41).g * 0.38;
          diffuseColor.rgb *= 1.0 - 0.24 * smoothstep(0.48, 0.78, cn);
        }`)
      .replace('#include <normal_fragment_maps>', `
        {
          vec3 nT = texture2D(uGrassN, uvFair()).xyz  * (vSplat.x * (1.0 - vSplat.w * 0.7))
                  + texture2D(uGrassN, uvGreen()).xyz * (vSplat.x * vSplat.w * 0.7)
                  + texture2D(uRoughN, uvRough()).xyz * vSplat.y
                  + texture2D(uSandN,  uvSand()).xyz  * vSplat.z;
          vec3 mapN = nT * 2.0 - 1.0;
          mapN.xy *= 0.8;
          mapN = normalize(mapN);
          vec3 eyePos = -vViewPosition;
          vec3 q0 = dFdx(eyePos); vec3 q1 = dFdy(eyePos);
          vec2 st0 = dFdx(uvFair()); vec2 st1 = dFdy(uvFair());
          vec3 Nn = normalize(normal);
          vec3 Tt = normalize(q0 * st1.t - q1 * st0.t);
          vec3 Bb = -normalize(cross(Nn, Tt));
          normal = normalize(mat3(Tt, Bb, Nn) * mapN);
        }`);
  };
  return mat;
}

// ---------- Branch-card tree kit (ported from TrueCarry_Sim) ----------
const PINE_SPRIG   = { u0: 0.030, v0: 0.550, u1: 0.225, v1: 0.985 };
const LEAF_RECT_A  = { u0: 0.010, v0: 0.270, u1: 0.440, v1: 0.740 };
const LEAF_RECT_B  = { u0: 0.040, v0: 0.005, u1: 0.420, v1: 0.460 };

function cardGeo(w, h, rect) {
  const g = new THREE.PlaneGeometry(w, h);
  g.translate(0, h / 2, 0);
  const uv = g.attributes.uv;
  for (let i = 0; i < uv.count; i++) {
    uv.setXY(i,
      rect.u0 + uv.getX(i) * (rect.u1 - rect.u0),
      rect.v0 + uv.getY(i) * (rect.v1 - rect.v0));
  }
  return g;
}
const _m4 = new THREE.Matrix4(), _q = new THREE.Quaternion(), _eu = new THREE.Euler();
function placed(geo, px, py, pz, rx, ry, rz, s = 1) {
  const g = geo.clone();
  _eu.set(rx, ry, rz, 'YXZ'); _q.setFromEuler(_eu);
  _m4.compose(new THREE.Vector3(px, py, pz), _q, new THREE.Vector3(s, s, s));
  g.applyMatrix4(_m4); return g;
}
function normalsUp(geo) {
  const n = geo.attributes.normal;
  for (let i = 0; i < n.count; i++) n.setXYZ(i, 0, 1, 0);
  return geo;
}
function pineCanopy(seed) {
  const rng = makeRng(seed);
  const sprig = cardGeo(1.9, 3.2, PINE_SPRIG);
  const cards = [];
  for (let y = 2.4; y <= 8.2; y += 0.92) {
    const t = (y - 2.4) / 5.8;
    const n = Math.round(6 - 3 * t);
    const s = 1.15 - 0.62 * t;
    for (let i = 0; i < n; i++) {
      const yaw = (i / n) * Math.PI * 2 + rng() * 1.2;
      const pitch = -(Math.PI / 2) + 0.38 + rng() * 0.25;
      cards.push(placed(sprig, 0, y + (rng()-0.5)*0.3, 0, pitch, yaw, 0, s*(0.85+rng()*0.3)));
    }
  }
  cards.push(placed(sprig, 0, 8.0, 0, -0.06, rng()*Math.PI, 0, 0.8));
  cards.push(placed(sprig, 0, 8.0, 0, -0.06, rng()*Math.PI+Math.PI/2, 0, 0.72));
  return normalsUp(mergeGeometries(cards));
}
function leafCanopy(seed) {
  const rng = makeRng(seed);
  const a = cardGeo(3.1, 3.1, LEAF_RECT_A);
  const b = cardGeo(2.8, 3.0, LEAF_RECT_B);
  const cards = [];
  const CY = 5.2;
  for (let i = 0; i < 26; i++) {
    const az = rng() * Math.PI * 2;
    const elev = (rng()-0.32) * 1.9;
    const r = 0.7 + rng() * 1.9;
    const px = Math.cos(az)*Math.cos(elev)*r;
    const pz = Math.sin(az)*Math.cos(elev)*r;
    const py = CY + Math.sin(elev)*r*0.8;
    cards.push(placed(rng()<0.5?a:b, px, py-1.4, pz,
      (rng()-0.6)*1.1, rng()*Math.PI*2, (rng()-0.5)*0.7, 0.8+rng()*0.5));
  }
  return normalsUp(mergeGeometries(cards));
}
function trunkGeo(rTop, rBot, h, vRepeat) {
  const g = new THREE.CylinderGeometry(rTop, rBot, h, 8, 1, true);
  g.translate(0, h/2, 0);
  const uv = g.attributes.uv;
  for (let i = 0; i < uv.count; i++) uv.setY(i, uv.getY(i) * vRepeat);
  return g;
}

let _treeKit = null;
function getTreeKit(assets) {
  if (_treeKit) return _treeKit;
  const t = assets.trees;
  const swayShaders = [];
  const addSway = (mat) => {
    mat.onBeforeCompile = (shader) => {
      shader.uniforms.uTime = { value: 0 };
      shader.uniforms.uWind = { value: 1 };
      swayShaders.push(shader);
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', `#include <common>
          uniform float uTime; uniform float uWind;`)
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
  const canopyMat = (map, cut) => addSway(new THREE.MeshLambertMaterial({
    map, alphaTest: cut, side: THREE.DoubleSide,
  }));
  const depthMat = (map, cut) => new THREE.MeshDepthMaterial({
    depthPacking: THREE.RGBADepthPacking, map, alphaTest: cut,
  });
  _treeKit = {
    canopies: [
      { geo: pineCanopy(11), mat: canopyMat(t.pineCard, 0.52), depth: depthMat(t.pineCard, 0.52), trunk: 'pine' },
      { geo: pineCanopy(47), mat: canopyMat(t.pineCard, 0.52), depth: depthMat(t.pineCard, 0.52), trunk: 'pine' },
      { geo: leafCanopy(23), mat: canopyMat(t.leafCard, 0.4),  depth: depthMat(t.leafCard, 0.4),  trunk: 'leaf' },
      { geo: leafCanopy(89), mat: canopyMat(t.leafCard, 0.4),  depth: depthMat(t.leafCard, 0.4),  trunk: 'leaf' },
    ],
    trunks: {
      pine: { geo: trunkGeo(0.07, 0.30, 8.6, 3), mat: new THREE.MeshLambertMaterial({ map: t.pineBark }) },
      leaf: { geo: trunkGeo(0.14, 0.36, 4.8, 2), mat: new THREE.MeshLambertMaterial({ map: t.leafBark }) },
    },
    swayShaders,
  };
  return _treeKit;
}

// ---------- Terrain mesh with PBR vertex colors ----------
function buildTerrainMeshPBR(courseData, heightAt, surfaceAt, assets, hmOriginX, hmOriginZ, hmW, hmD) {
  const SEG = 5; // 5m — good detail without excessive verts
  const cols = Math.floor(hmW / SEG) + 1;
  const rows = Math.floor(hmD / SEG) + 1;

  const positions = new Float32Array(cols * rows * 3);
  const colors    = new Float32Array(cols * rows * 3);
  const splats    = new Float32Array(cols * rows * 4);
  const indices   = [];

  const fbmDetail = makeFbm(42, 3);

  const C = {
    fairA:    new THREE.Color(0x568f3f),
    fairB:    new THREE.Color(0x447c31),
    fringe:   new THREE.Color(0x467c38),
    greenA:   new THREE.Color(0x67a64f),
    greenB:   new THREE.Color(0x5d9b46),
    rough:    new THREE.Color(0x3b662e),
    deep:     new THREE.Color(0x2c4f22),
    sand:     new THREE.Color(0xd5c28c),
    bed:      new THREE.Color(0x31464a),
    cartPath: new THREE.Color(0x9e9e8e),
  };
  const tmp = new THREE.Color();

  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const idx = r * cols + c;
      const x   = hmOriginX + c * SEG;
      const z   = hmOriginZ + r * SEG;
      const y   = heightAt(x, z);
      positions[idx*3]   = x;
      positions[idx*3+1] = y;
      positions[idx*3+2] = z;

      const surf = surfaceAt(x, z);
      let sg = 0, sr = 0, ss = 0, sw = 0;

      if (surf === SURF.BUNKER) {
        tmp.copy(C.sand); ss = 1;
      } else if (surf === SURF.WATER) {
        tmp.copy(C.bed); sr = 1;
      } else if (surf === SURF.GREEN) {
        const checker = (Math.floor(x / 2.4) + Math.floor(z / 2.4)) % 2 === 0;
        tmp.copy(checker ? C.greenA : C.greenB); sg = 1; sw = 1;
      } else if (surf === SURF.FAIRWAY) {
        const stripe = Math.floor(z / 7) % 2 === 0;
        tmp.copy(stripe ? C.fairA : C.fairB); sg = 1;
      } else if (surf === SURF.CARTPATH) {
        tmp.copy(C.cartPath); ss = 0.5; sr = 0.5; // concrete: mix sand+rough structure
      } else {
        // rough / OOB — vary darkness with fbm
        const t = Math.max(0, Math.min(1, fbmDetail(x * 0.01, z * 0.01) * 0.5 + 0.5));
        tmp.copy(C.rough).lerp(C.deep, t); sr = 1;
      }

      const vmod = 1 + fbmDetail(x * 0.08 + 31, z * 0.08) * 0.06;
      colors[idx*3]   = tmp.r * vmod;
      colors[idx*3+1] = tmp.g * vmod;
      colors[idx*3+2] = tmp.b * vmod;
      splats[idx*4]   = sg; splats[idx*4+1] = sr;
      splats[idx*4+2] = ss; splats[idx*4+3] = sw;
    }
  }

  for (let r = 0; r < rows-1; r++) {
    for (let c = 0; c < cols-1; c++) {
      const a = r*cols+c, b=a+1, d=(r+1)*cols+c, e=d+1;
      indices.push(a, d, b, b, d, e);
    }
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setAttribute('color',    new THREE.BufferAttribute(colors, 3));
  geo.setAttribute('splat',    new THREE.BufferAttribute(splats, 4));
  geo.setIndex(indices);
  geo.computeVertexNormals();

  const mesh = new THREE.Mesh(geo, splatMaterial(assets));
  mesh.receiveShadow = true;
  mesh.name = 'terrain';
  return mesh;
}

// ---------- Water (Three.js Water addon) ----------
function buildWaterPBR(courseData, heightAt, scene, assets) {
  const waters = [];
  for (const hole of courseData.holes) {
    for (const w of hole.water) {
      if (!w || w.length < 3) continue;
      const xs = w.map(p => p[0]), zs = w.map(p => p[1]);
      const cx = (Math.min(...xs) + Math.max(...xs)) / 2;
      const cz = (Math.min(...zs) + Math.max(...zs)) / 2;
      const sx = Math.max(...xs) - Math.min(...xs) + 4;
      const sz = Math.max(...zs) - Math.min(...zs) + 4;
      const y  = heightAt(cx, cz) + 0.05;

      const water = new Water(new THREE.PlaneGeometry(sx, sz), {
        textureWidth:  512,
        textureHeight: 512,
        waterNormals:  assets.waterN,
        sunDirection:  assets.sunDir.clone(),
        sunColor: 0xffffff,
        waterColor: 0x0e3526,
        distortionScale: 2.2,
        fog: true,
      });
      water.rotation.x = -Math.PI / 2;
      water.position.set(cx, y, cz);
      scene.add(water);
      waters.push(water);
    }
  }
  return waters;
}

// ---------- Branch-card trees ----------
function buildTreesPBR(courseData, heightAt, scene, assets) {
  if (!courseData.trees?.length) return [];
  const kit   = getTreeKit(assets);
  const rng   = makeRng(courseData.meta ? 999 : 999);

  // Annotate each tree with a kind (0-3) and per-instance tint
  const spots = courseData.trees.map((t, i) => ({
    x: t.x, z: t.z, h: heightAt(t.x, t.z),
    s: (t.r / 3.2) * (0.65 + (i % 97) / 97 * 0.7),
    ry: (i * 2.39996) % (Math.PI * 2),
    tilt: ((i % 13) / 13 - 0.5) * 0.07,
    kind: t.isPine ? (i % 2) : 2 + (i % 2),
    tint: [0.82 + (i % 17) / 17 * 0.34, 0.84 + (i % 23) / 23 * 0.34, 0.82 + (i % 11) / 11 * 0.28],
  }));

  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion();
  const eu = new THREE.Euler(), v3 = new THREE.Vector3(), s3 = new THREE.Vector3();
  const col = new THREE.Color();

  function setInstances(im, mine, tinted) {
    mine.forEach((t, i) => {
      eu.set(t.tilt, t.ry, t.tilt * 0.7);
      q.setFromEuler(eu);
      v3.set(t.x, t.h - 0.12, t.z);
      s3.set(t.s, t.s, t.s);
      m4.compose(v3, q, s3);
      im.setMatrixAt(i, m4);
      if (tinted) { col.setRGB(t.tint[0], t.tint[1], t.tint[2]); im.setColorAt(i, col); }
    });
    im.instanceMatrix.needsUpdate = true;
    if (im.instanceColor) im.instanceColor.needsUpdate = true;
    scene.add(im);
  }

  for (let k = 0; k < kit.canopies.length; k++) {
    const mine = spots.filter(t => t.kind === k);
    if (!mine.length) continue;
    const c  = kit.canopies[k];
    const im = new THREE.InstancedMesh(c.geo, c.mat, mine.length);
    im.customDepthMaterial = c.depth;
    im.castShadow = true;
    setInstances(im, mine, true);
  }
  for (const species of ['pine', 'leaf']) {
    const mine = spots.filter(t => kit.canopies[t.kind].trunk === species);
    if (!mine.length) continue;
    const tk = kit.trunks[species];
    const im = new THREE.InstancedMesh(tk.geo, tk.mat, mine.length);
    im.castShadow = true;
    setInstances(im, mine, false);
  }

  return kit.swayShaders;
}

// ---------- Backdrop treeline cylinder ----------
function buildBackdrop(courseData, scene) {
  const { minX, maxX, minZ, maxZ } = courseData.bbox;
  const ccx = (minX + maxX) / 2, ccz = (minZ + maxZ) / 2;
  const radius = Math.max(maxX - ccx, maxZ - ccz) + 200;
  const fbmBack = makeFbm(77, 3);

  const rgeo = new THREE.CylinderGeometry(radius, radius, 1, 140, 1, true);
  const rpos = rgeo.attributes.position;
  const rcol = new Float32Array(rpos.count * 3);
  const lo = new THREE.Color(0x2f4d28);
  const hi = new THREE.Color(0x5d7a55).lerp(new THREE.Color(0xaebfd0), 0.45);
  for (let i = 0; i < rpos.count; i++) {
    const x = rpos.getX(i), z = rpos.getZ(i);
    const top = rpos.getY(i) > 0;
    const a = Math.atan2(z, x);
    const n = fbmBack(Math.cos(a) * 2.4 + 4, Math.sin(a) * 2.4) * 0.5 + 0.5;
    rpos.setY(i, top ? 10 + n * 9 : -6);
    const c = top ? hi : lo;
    rcol[i*3] = c.r; rcol[i*3+1] = c.g; rcol[i*3+2] = c.b;
  }
  rgeo.setAttribute('color', new THREE.BufferAttribute(rcol, 3));
  const rm = new THREE.Mesh(rgeo, new THREE.MeshBasicMaterial({
    vertexColors: true, side: THREE.BackSide, fog: true,
  }));
  rm.position.set(ccx, 0, ccz);
  scene.add(rm);
}

// ---------- Flags + cup markers ----------
function buildHoleMarkers(courseData, heightAt, scene) {
  for (const hole of courseData.holes) {
    const [gx, gz] = hole.green.center;
    const y = heightAt(gx, gz);

    const pole = new THREE.Mesh(
      new THREE.CylinderGeometry(0.022, 0.022, 2.25, 8),
      new THREE.MeshLambertMaterial({ color: 0xf4f1e6 }),
    );
    pole.position.set(gx, y + 1.125, gz);
    pole.castShadow = true;

    const flagGeo = new THREE.PlaneGeometry(0.62, 0.4);
    flagGeo.translate(0.31, 0, 0);
    const flag = new THREE.Mesh(flagGeo,
      new THREE.MeshLambertMaterial({ color: 0xc23a28, side: THREE.DoubleSide }));
    flag.position.set(gx, y + 2.0, gz);

    const cup = new THREE.Mesh(
      new THREE.CircleGeometry(0.075, 20),
      new THREE.MeshBasicMaterial({ color: 0x10160f }),
    );
    cup.rotation.x = -Math.PI / 2;
    cup.position.set(gx, y + 0.012, gz);

    scene.add(pole, flag, cup);
  }
}

// ---------- Module-level singletons ----------
let _heightAt, _surfaceAt, _waterRef, _terrainShader, _swayShaders;

// ---------- Main export ----------
export function buildWorld(courseData, scene, assets) {
  _treeKit = null; // reset if called again

  const hm = courseData.heightmap;
  const { heightAt } = makeHeightmap(hm);
  _heightAt = heightAt;

  const hmOriginX = hm.originX, hmOriginZ = hm.originZ;
  const hmWidth   = (hm.cols - 1) * hm.cellSize;
  const hmDepth   = (hm.rows - 1) * hm.cellSize;

  const surfMap = makeSurfaceMap(courseData, hmOriginX, hmOriginZ, hmWidth, hmDepth);
  _surfaceAt = surfMap.surfaceAt;

  const terrain = buildTerrainMeshPBR(courseData, heightAt, surfMap.surfaceAt, assets, hmOriginX, hmOriginZ, hmWidth, hmDepth);
  scene.add(terrain);
  _terrainShader = terrain.material.userData;

  buildBackdrop(courseData, scene);
  buildHoleMarkers(courseData, heightAt, scene);

  const waterPlanes = buildWaterPBR(courseData, heightAt, scene, assets);
  _waterRef = waterPlanes;

  _swayShaders = buildTreesPBR(courseData, heightAt, scene, assets);

  return { terrain, waterPlanes };
}

// Call from main animation loop to animate water + tree sway + cloud shadows
export function updateWorld(t, windVec) {
  if (_waterRef) {
    for (const w of _waterRef) w.material.uniforms.time.value = t * 0.5;
  }
  if (_terrainShader?.shader) {
    _terrainShader.shader.uniforms.uTime.value = t;
    if (windVec) _terrainShader.shader.uniforms.uWindVec.value.set(windVec.x, windVec.z);
  }
  if (_swayShaders) {
    for (const sh of _swayShaders) {
      sh.uniforms.uTime.value = t;
      if (windVec) sh.uniforms.uWind.value = Math.hypot(windVec.x, windVec.z);
    }
  }
}

// ---------- Physics / query helpers ----------
export function heightAt(x, z)  { return _heightAt  ? _heightAt(x, z)  : 0; }
export function surfaceAt(x, z) { return _surfaceAt ? _surfaceAt(x, z) : SURF.ROUGH; }

export function slopeAt(x, z) {
  const eps = 0.5;
  const h0 = heightAt(x, z), hpx = heightAt(x+eps, z)-h0, hpz = heightAt(x, z+eps)-h0;
  const len = Math.hypot(-hpx, eps, -hpz) || 1;
  return { nx: -hpx/len, ny: eps/len, nz: -hpz/len };
}

export function holeCameraPos(hole, behindMeters = 18) {
  const [tx, tz] = hole.tee, [gx, gz] = hole.green.center;
  const dx = tx - gx, dz = tz - gz;
  const len = Math.hypot(dx, dz) || 1;
  return {
    cx: tx + (dx/len) * behindMeters,
    cy: heightAt(tx, tz) + 9.0,   // 9m above tee = proper overhead setup view
    cz: tz + (dz/len) * behindMeters,
    tx: gx, ty: heightAt(gx, gz) + 0.5, tz: gz,
  };
}

// ---------- Minimap ----------
export function drawMinimapBase(courseData, canvas) {
  const ctx = canvas.getContext('2d');
  const W = canvas.width, H = canvas.height;
  const bbox = courseData.bbox;
  const scaleX = W / (bbox.maxX - bbox.minX);
  const scaleZ = H / (bbox.maxZ - bbox.minZ);
  function toC(x, z) { return [(x-bbox.minX)*scaleX, (z-bbox.minZ)*scaleZ]; }

  ctx.clearRect(0, 0, W, H);
  ctx.fillStyle = '#1e3a10'; ctx.fillRect(0, 0, W, H);

  function drawPoly(poly, color) {
    if (!poly?.length) return;
    ctx.beginPath(); ctx.fillStyle = color;
    const [px, pz] = toC(poly[0][0], poly[0][1]);
    ctx.moveTo(px, pz);
    for (let i = 1; i < poly.length; i++) {
      const [qx, qz] = toC(poly[i][0], poly[i][1]); ctx.lineTo(qx, qz);
    }
    ctx.closePath(); ctx.fill();
  }

  for (const hole of courseData.holes) {
    drawPoly(hole.fairway, '#3a6a18');
    for (const b of hole.bunkers) drawPoly(b, '#c8a84a');
    for (const w of hole.water) drawPoly(w, '#2060a8');
    if (hole.green.polygon) drawPoly(hole.green.polygon, '#50cc60');
  }

  // Cart paths
  for (const path of (courseData.cartPaths || [])) {
    if (path.length < 2) continue;
    ctx.beginPath();
    ctx.strokeStyle = 'rgba(180,175,155,0.7)';
    ctx.lineWidth   = Math.max(1, Math.min(scaleX, scaleZ) * 3.6);
    const [px, pz] = toC(path[0][0], path[0][1]); ctx.moveTo(px, pz);
    for (let i = 1; i < path.length; i++) {
      const [qx, qz] = toC(path[i][0], path[i][1]); ctx.lineTo(qx, qz);
    }
    ctx.stroke();
  }

  for (const hole of courseData.holes) {
    if (hole.path?.length > 1) {
      ctx.strokeStyle = 'rgba(255,255,255,0.25)'; ctx.lineWidth = 0.5; ctx.beginPath();
      const [px, pz] = toC(hole.path[0][0], hole.path[0][1]); ctx.moveTo(px, pz);
      for (let i = 1; i < hole.path.length; i++) {
        const [qx, qz] = toC(hole.path[i][0], hole.path[i][1]); ctx.lineTo(qx, qz);
      }
      ctx.stroke();
    }
  }
  return { toC, scaleX, scaleZ };
}
