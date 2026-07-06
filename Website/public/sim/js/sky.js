// Environment: real HDRI sky (background panorama + image-based lighting)
// with a shadow-casting sun aligned to the brightest spot in the HDR.

import * as THREE from 'three';

export function makeSky(scene, renderer, assets) {
  scene.background = assets.skyBg;
  scene.environment = assets.skyEnv;
  scene.backgroundIntensity = 1.0;
  scene.environmentIntensity = 0.55;

  // gentle aerial perspective; the HDRI horizon takes over past the fog
  scene.fog = new THREE.Fog(0xd2dee8, 430, 2600);

  const sunDir = assets.sunDir.clone();

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
    update(t, focus) {
      if (focus) {
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
