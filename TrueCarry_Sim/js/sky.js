// Environment: a procedural sky dome with crisp drifting fractal clouds
// (self-contained shader — no photo backdrop), plus the HDRI for image-based
// lighting and a shadow-casting sun aligned to the brightest spot.

import * as THREE from 'three';

// ---------- procedural sky dome ----------
// A large inward sphere painting a gradient sky, a sun disc + halo, and
// layered value-noise cumulus that drift with wind. Crisp because the cloud
// mask uses a sharp smoothstep, not a blurred photo.
function makeSkyDome(scene, sunDir) {
  const uniforms = {
    uSunDir:     { value: sunDir.clone().normalize() },
    uTime:       { value: 0 },
    uWind:       { value: new THREE.Vector2(0.6, 0.2) },
    uZenith:     { value: new THREE.Color(0x2a6bb0) },
    uHorizon:    { value: new THREE.Color(0xcfe0ec) },
    uSunColor:   { value: new THREE.Color(0xfff4dc) },
    uCloudLit:   { value: new THREE.Color(0xffffff) },
    uCloudDark:  { value: new THREE.Color(0x9fb0c0) },
    uCloudCover: { value: 0.5 },   // 0 clear .. 1 overcast
    uCloudSharp: { value: 0.62 },  // edge crispness
    uHazeColor:  { value: new THREE.Color(0xd6e2ec) },
  };

  const vertex = /* glsl */`
    varying vec3 vDir;
    void main() {
      vDir = position;
      vec4 mv = modelViewMatrix * vec4(position, 1.0);
      gl_Position = projectionMatrix * mv;
      gl_Position.z = gl_Position.w;   // force to far plane
    }`;

  const fragment = /* glsl */`
    precision highp float;
    varying vec3 vDir;
    uniform vec3 uSunDir, uZenith, uHorizon, uSunColor, uCloudLit, uCloudDark, uHazeColor;
    uniform float uTime, uCloudCover, uCloudSharp;
    uniform vec2 uWind;

    // hash + value noise + fbm
    float hash(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
    float vnoise(vec2 p){
      vec2 i = floor(p), f = fract(p);
      vec2 u = f * f * (3.0 - 2.0 * f);
      float a = hash(i), b = hash(i + vec2(1.0, 0.0));
      float c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
      return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }
    float fbm(vec2 p){
      float v = 0.0, a = 0.55; mat2 m = mat2(1.7, 1.2, -1.2, 1.7);
      for(int i = 0; i < 6; i++){ v += a * vnoise(p); p = m * p; a *= 0.5; }
      return v;
    }

    void main(){
      vec3 dir = normalize(vDir);
      float up = clamp(dir.y, 0.0, 1.0);

      // sky gradient: horizon haze -> zenith, richer overhead
      vec3 sky = mix(uHorizon, uZenith, pow(up, 0.36));

      // sun disc + halo
      float sd = max(dot(dir, normalize(uSunDir)), 0.0);
      sky += uSunColor * pow(sd, 900.0) * 1.4;             // disc
      sky += uSunColor * pow(sd, 12.0) * 0.28;             // inner halo
      sky += uSunColor * pow(sd, 3.0) * 0.06;              // broad glow

      // clouds: project onto a cloud plane above, sample drifting fbm.
      // Visible down to low elevations (that is where the camera looks) with a
      // crisp bright cumulus mask.
      if (dir.y > 0.012) {
        vec2 cuv = dir.xz / (dir.y * 0.62 + 0.32) * 1.25 + uWind * uTime * 0.006;
        float base = fbm(cuv * 0.9);
        float detail = fbm(cuv * 2.6 + base * 0.5);
        float density = base * 0.7 + detail * 0.3;
        float lo = mix(0.54, 0.30, uCloudCover);
        float edge = mix(0.12, 0.32, 1.0 - uCloudSharp);
        float mask = smoothstep(lo, lo + edge, density);
        mask *= smoothstep(0.012, 0.09, dir.y);            // show much lower
        // bright cumulus: white tops, soft shadowed cores
        float shade = smoothstep(lo - 0.14, lo + 0.22, density);
        vec3 cloud = mix(uCloudDark, uCloudLit, 0.35 + 0.65 * shade);
        cloud += uSunColor * pow(sd, 5.0) * 0.4 * mask;    // silver lining
        sky = mix(sky, cloud, mask);
      }

      // horizon haze band so the dome meets the terrain fog cleanly
      sky = mix(uHazeColor, sky, smoothstep(-0.04, 0.06, dir.y));

      gl_FragColor = vec4(sky, 1.0);
    }`;

  const mat = new THREE.ShaderMaterial({
    uniforms, vertexShader: vertex, fragmentShader: fragment,
    side: THREE.BackSide, depthWrite: false, fog: false,
  });
  const dome = new THREE.Mesh(new THREE.SphereGeometry(8000, 48, 32), mat);
  dome.frustumCulled = false;
  dome.renderOrder = -10;
  scene.add(dome);
  return { dome, uniforms };
}

export function makeSky(scene, renderer, assets) {
  // HDRI drives image-based lighting only; the procedural dome is the visible sky.
  scene.background = null;
  scene.environment = assets.skyEnv;
  scene.environmentIntensity = 0.55;

  // gentle aerial perspective; the dome horizon takes over past the fog
  scene.fog = new THREE.Fog(0xd2dee8, 430, 2600);

  const sunDir = assets.sunDir.clone();
  const skyDome = makeSkyDome(scene, sunDir);

  // small fill so foliage (non-PBR materials) isn't flat black in shade
  const hemi = new THREE.HemisphereLight(0xbdd3e8, 0x44603a, 0.62);
  scene.add(hemi);

  const sun = new THREE.DirectionalLight(0xfff1d8, 2.0);
  sun.position.copy(sunDir).multiplyScalar(300);
  sun.castShadow = true;
  sun.shadow.mapSize.set(4096, 4096);
  // Cover the whole visible hole: a tight box left everything past ~110m
  // unshadowed, which read as a bright veil across open fairways.
  const S = 340;
  sun.shadow.camera.left = -S; sun.shadow.camera.right = S;
  sun.shadow.camera.top = S; sun.shadow.camera.bottom = -S;
  sun.shadow.camera.near = 20; sun.shadow.camera.far = 1400;
  sun.shadow.bias = -0.0004;
  sun.shadow.normalBias = 0.03;
  sun.shadow.radius = 2.2;
  scene.add(sun);
  scene.add(sun.target);

  return {
    sun, hemi, sunDir,
    sky: skyDome,        // { dome, uniforms } — atmosphere presets tune these
    update(t, focus) {
      skyDome.uniforms.uTime.value = t;
      if (focus) {
        skyDome.dome.position.set(focus.x, 0, focus.z);   // keep dome centred on view
        // Snap the frustum centre to the shadow-texel grid so the map
        // doesn't shimmer as the camera moves.
        const texel = (S * 2) / 4096;
        const fx = Math.round(focus.x / texel) * texel;
        const fz = Math.round(focus.z / texel) * texel;
        sun.position.set(fx + sunDir.x * 600, sunDir.y * 600, fz + sunDir.z * 600);
        sun.target.position.set(fx, 0, fz);
      }
    },
  };
}
