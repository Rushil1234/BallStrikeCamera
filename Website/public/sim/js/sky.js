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
    // combined cloud density field (base body + fine detail), reused for
    // both the visible cloud mask and the fake self-shadowing sample.
    float cloudField(vec2 p){
      float base = fbm(p * 0.9);
      float detail = fbm(p * 2.6 + base * 0.5);
      return base * 0.7 + detail * 0.3;
    }

    void main(){
      vec3 dir = normalize(vDir);
      float up = clamp(dir.y, 0.0, 1.0);
      vec3 sunN = normalize(uSunDir);
      vec2 sunFlat = normalize(uSunDir.xz + 1e-4);   // sun azimuth on the ground plane

      // sky gradient: horizon haze -> zenith with atmospheric falloff.
      // Two-stage curve keeps a luminous horizon while deepening the zenith so
      // the dome doesn't read as one flat wash.
      float t = pow(up, 0.42);
      vec3 sky = mix(uHorizon, uZenith, t);
      sky = mix(sky, uZenith * 0.82, smoothstep(0.45, 1.0, up) * 0.35);   // deeper overhead

      // warm horizon glow biased toward the sun azimuth (aerial perspective):
      // the low sun scatters warm light along the horizon it sits on.
      float horizonBand = pow(1.0 - up, 3.0);
      float sunAz = max(dot(normalize(vec2(dir.x, dir.z) + 1e-4), sunFlat), 0.0);
      sky += uSunColor * horizonBand * pow(sunAz, 1.6) * 0.22;

      // sun disc + halo (tightened broad glow so it blooms gently, not blown)
      float sd = max(dot(dir, sunN), 0.0);
      float ad = acos(clamp(sd, -1.0, 1.0));               // angular distance to sun
      sky += uSunColor * pow(sd, 1200.0) * 1.5;            // crisp disc
      sky += uSunColor * pow(sd, 14.0) * 0.24;            // inner halo
      sky += uSunColor * pow(sd, 4.0) * 0.045;            // broad glow

      // crepuscular light-shafts: cheap in-dome radial streaks near the sun.
      // A noise band swept by the angle around the sun, gated tight to the sun
      // and fading with distance — no extra full-screen pass. Overcast kills it.
      {
        vec3 perp = normalize(dir - sunN * sd + 1e-4);
        float rayAng = atan(perp.z, perp.x);
        float rays = fbm(vec2(rayAng * 2.6, ad * 3.0) + uWind * uTime * 0.02);
        rays = smoothstep(0.42, 0.95, rays);
        float shaft = rays * exp(-ad * 3.2) * smoothstep(0.0, 0.12, dir.y);
        sky += uSunColor * shaft * 0.12 * (1.0 - uCloudCover);
      }

      // clouds: project onto a cloud plane above, sample drifting fbm.
      // Visible down to low elevations (that is where the camera looks) with a
      // crisp bright cumulus mask, fake sun-side self shadowing for depth.
      if (dir.y > 0.012) {
        vec2 cuv = dir.xz / (dir.y * 0.62 + 0.32) * 1.25 + uWind * uTime * 0.006;
        float density = cloudField(cuv);
        float lo = mix(0.54, 0.30, uCloudCover);
        float edge = mix(0.12, 0.32, 1.0 - uCloudSharp);
        float mask = smoothstep(lo, lo + edge, density);
        mask *= smoothstep(0.012, 0.09, dir.y);            // show much lower

        // self-shadow: sample the field a step toward the sun. Where the
        // sun-side is thinner this pixel is a lit rim; where it is thicker the
        // pixel sits in a shadowed base. Gives cumulus real top/bottom depth.
        float toward = cloudField(cuv - sunFlat * 0.55);
        float lit = clamp((density - toward) * 3.2 + 0.55, 0.0, 1.0);
        float body = smoothstep(lo - 0.16, lo + 0.26, density);   // core brightness
        vec3 cloud = mix(uCloudDark, uCloudLit, 0.30 + 0.70 * body);
        cloud *= mix(0.72, 1.12, lit);                     // shade bases, light tops
        cloud += uSunColor * pow(sd, 6.0) * 0.5 * mask;    // silver lining rim
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

// ---------- drifting cloud shadows on the ground ----------
// A large horizontal sheet just above the turf, multiply-blended, that samples
// a slow large-scale noise and darkens the ground in soft dappled patches which
// creep with the wind. One extra flat quad — no full-screen pass — so it is
// nearly free, yet it is one of the strongest "outdoors, real weather" cues.
function makeCloudShadows(scene, sunDir) {
  const uniforms = {
    uTime:   { value: 0 },
    uWind:   { value: new THREE.Vector2(0.6, 0.2) },
    uAmount: { value: 0.26 },   // darkening strength (tuned per atmosphere)
    uTint:   { value: new THREE.Color(0x6f7d92) },  // cool shadow colour
  };
  const vertex = /* glsl */`
    varying vec2 vWorld;
    varying vec2 vUv;
    void main(){
      vUv = uv;
      vec4 wp = modelMatrix * vec4(position, 1.0);
      vWorld = wp.xz;
      gl_Position = projectionMatrix * viewMatrix * wp;
    }`;
  const fragment = /* glsl */`
    precision highp float;
    varying vec2 vWorld;
    varying vec2 vUv;
    uniform float uTime, uAmount;
    uniform vec2 uWind;
    uniform vec3 uTint;
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
      for(int i = 0; i < 5; i++){ v += a * vnoise(p); p = m * p; a *= 0.5; }
      return v;
    }
    void main(){
      // large-scale drifting field: ~120m patches
      vec2 p = vWorld * 0.0085 + uWind * uTime * 0.010;
      float n = fbm(p);
      float sh = smoothstep(0.46, 0.72, n);           // soft-edged shadow patches
      // fade out toward the quad edges so there is no hard boundary at the rim
      vec2 e = smoothstep(0.0, 0.14, vUv) * smoothstep(0.0, 0.14, 1.0 - vUv);
      sh *= e.x * e.y;
      vec3 col = mix(vec3(1.0), uTint, sh * uAmount);  // multiply: 1 = untouched
      gl_FragColor = vec4(col, 1.0);
    }`;
  const mat = new THREE.ShaderMaterial({
    uniforms, vertexShader: vertex, fragmentShader: fragment,
    transparent: true, depthWrite: false, blending: THREE.MultiplyBlending, fog: false,
  });
  const geo = new THREE.PlaneGeometry(6000, 6000, 1, 1);
  geo.rotateX(-Math.PI / 2);
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.y = 1.2;          // just above the turf, below eye height
  mesh.frustumCulled = false;
  mesh.renderOrder = 4;           // after opaque terrain, before transparent UI sprites
  scene.add(mesh);
  return { mesh, uniforms };
}

export function makeSky(scene, renderer, assets) {
  // HDRI drives image-based lighting only; the procedural dome is the visible sky.
  scene.background = null;
  scene.environment = assets.skyEnv;
  scene.environmentIntensity = 0.55;

  // gentle aerial perspective; the dome horizon takes over past the fog
  scene.fog = new THREE.Fog(0xd2dee8, 430, 2600);

  const sunDir = assets.sunDir.clone();
  // Force a low, raking sun regardless of where the HDRI's hotspot sits. Long,
  // soft, directional shadows are the single biggest "photoreal golf sim" cue
  // (GSPro / PGA 2K) — they model the terrain undulation and ground the trees.
  {
    const az = Math.atan2(sunDir.z, sunDir.x);
    const el = 0.50;                     // ~29° above the horizon: long but playable shadows
    const cy = Math.cos(el);
    sunDir.set(Math.cos(az) * cy, Math.sin(el), Math.sin(az) * cy).normalize();
  }
  const skyDome = makeSkyDome(scene, sunDir);
  const cloudShadows = makeCloudShadows(scene, sunDir);

  // Sky fill so foliage (non-PBR materials) isn't flat black in shade. Lifted a
  // touch to keep the low-sun shadow sides readable and softly blue, not muddy.
  const hemi = new THREE.HemisphereLight(0xc2d6ea, 0x4a663e, 0.72);
  scene.add(hemi);

  const sun = new THREE.DirectionalLight(0xffeccb, 2.15);
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
  sun.shadow.radius = 3.6;   // softer penumbra — real shadows aren't hard-edged
  scene.add(sun);
  scene.add(sun.target);

  return {
    sun, hemi, sunDir,
    sky: skyDome,        // { dome, uniforms } — atmosphere presets tune these
    cloudShadows,        // { mesh, uniforms }
    update(t, focus) {
      skyDome.uniforms.uTime.value = t;
      // drive the ground cloud shadows: share the sky's wind + time, and fade
      // the dappling out as overcast rises (diffuse light casts no crisp patches).
      cloudShadows.uniforms.uTime.value = t;
      cloudShadows.uniforms.uWind.value.copy(skyDome.uniforms.uWind.value);
      const cover = skyDome.uniforms.uCloudCover.value;
      cloudShadows.uniforms.uAmount.value =
        0.05 + 0.27 * Math.max(0, Math.min(1, (0.78 - cover) / 0.45));
      if (focus) {
        skyDome.dome.position.set(focus.x, 0, focus.z);   // keep dome centred on view
        cloudShadows.mesh.position.set(focus.x, 1.2, focus.z);
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
