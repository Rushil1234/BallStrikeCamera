// Environment: real HDRI sky (background panorama + image-based lighting)
// with a shadow-casting sun aligned to the brightest spot in the HDR.

import * as THREE from 'three';

export function makeSky(scene, renderer, assets) {
  scene.background = assets.skyBg;
  scene.environment = assets.skyEnv;
  scene.backgroundIntensity = 1.0;
  scene.environmentIntensity = 0.55;

  // gentle aerial perspective; the HDRI horizon takes over past the fog
  scene.fog = new THREE.Fog(0xcfdce6, 500, 2900);

  const sunDir = assets.sunDir.clone();

  // small fill so foliage (non-PBR materials) isn't flat black in shade
  const hemi = new THREE.HemisphereLight(0xbdd3e8, 0x44603a, 0.62);
  scene.add(hemi);

  const sun = new THREE.DirectionalLight(0xfff1d8, 2.0);
  sun.position.copy(sunDir).multiplyScalar(300);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  const S = 95;
  sun.shadow.camera.left = -S; sun.shadow.camera.right = S;
  sun.shadow.camera.top = S; sun.shadow.camera.bottom = -S;
  sun.shadow.camera.near = 50; sun.shadow.camera.far = 700;
  sun.shadow.bias = -0.0006;
  scene.add(sun);
  scene.add(sun.target);

  return {
    sun, hemi, sunDir,
    update(t, focus) {
      if (focus) {
        // keep the shadow frustum centred on the action
        sun.position.set(
          focus.x + sunDir.x * 300,
          sunDir.y * 300,
          focus.z + sunDir.z * 300,
        );
        sun.target.position.set(focus.x, 0, focus.z);
      }
    },
  };
}
