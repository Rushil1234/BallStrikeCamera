// Asset loading: PBR ground textures, tree branch-card textures, HDRI sky
// (background JPG + 1k HDR for image-based lighting), water normals.
// All CC0 from Poly Haven, water normals from three.js examples (MIT).

import * as THREE from 'three';
import { RGBELoader } from 'three/addons/loaders/RGBELoader.js?v=gspro-8';

function loadTex(loader, url, { srgb = false, aniso = 8 } = {}) {
  return new Promise((resolve, reject) => {
    loader.load(url, (t) => {
      if (srgb) t.colorSpace = THREE.SRGBColorSpace;
      t.wrapS = t.wrapT = THREE.RepeatWrapping;
      t.anisotropy = aniso;
      resolve(t);
    }, undefined, reject);
  });
}

// average linear color of an image texture — used to neutralize a photo
// texture so the designed vertex colors set the hue and the photo provides
// structure. Averaging must happen in linear space (the shader samples
// linear), so convert each pixel before summing.
function meanColor(tex) {
  const img = tex.image;
  const cv = document.createElement('canvas');
  cv.width = cv.height = 64;
  const ctx = cv.getContext('2d');
  ctx.drawImage(img, 0, 0, 64, 64);
  const d = ctx.getImageData(0, 0, 64, 64).data;
  let r = 0, g = 0, b = 0;
  for (let i = 0; i < d.length; i += 4) {
    r += Math.pow(d[i] / 255, 2.2);
    g += Math.pow(d[i + 1] / 255, 2.2);
    b += Math.pow(d[i + 2] / 255, 2.2);
  }
  const n = d.length / 4;
  return new THREE.Vector3(
    Math.max(r / n, 0.02), Math.max(g / n, 0.02), Math.max(b / n, 0.02),
  );
}

// Combine a branch diffuse + alpha into one RGBA texture, flooding the
// background with the average foreground color so mipmaps don't develop
// dark halos around the cutouts.
function cardTexture(diffTex, alphaTex, aniso, brighten = 1) {
  const W = diffTex.image.width, H = diffTex.image.height;
  const cv = document.createElement('canvas');
  cv.width = W; cv.height = H;
  const ctx = cv.getContext('2d');
  ctx.drawImage(diffTex.image, 0, 0, W, H);
  const diff = ctx.getImageData(0, 0, W, H);
  const cv2 = document.createElement('canvas');
  cv2.width = W; cv2.height = H;
  const ctx2 = cv2.getContext('2d');
  ctx2.drawImage(alphaTex.image, 0, 0, W, H);
  const alpha = ctx2.getImageData(0, 0, W, H).data;

  // average foreground color
  let r = 0, g = 0, b = 0, n = 0;
  for (let i = 0; i < alpha.length; i += 4) {
    if (alpha[i] > 128) { r += diff.data[i]; g += diff.data[i + 1]; b += diff.data[i + 2]; n++; }
  }
  if (n) { r /= n; g /= n; b /= n; } else { r = g = b = 90; }

  const d = diff.data;
  for (let i = 0; i < alpha.length; i += 4) {
    const a = alpha[i];
    if (a <= 128) { d[i] = r; d[i + 1] = g; d[i + 2] = b; }
    if (brighten !== 1) {
      d[i] = Math.min(255, d[i] * brighten);
      d[i + 1] = Math.min(255, d[i + 1] * brighten);
      d[i + 2] = Math.min(255, d[i + 2] * brighten);
    }
    d[i + 3] = a;
  }
  ctx.putImageData(diff, 0, 0);
  const tex = new THREE.CanvasTexture(cv);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = aniso;
  tex.wrapS = tex.wrapT = THREE.ClampToEdgeWrapping;
  return tex;
}

// brightest texel of the equirect HDR = the sun
function sunFromEquirect(tex) {
  const { data, width, height } = tex.image;
  let best = -1, bi = 0;
  for (let i = 0; i < width * height; i++) {
    const l = data[i * 4] + data[i * 4 + 1] + data[i * 4 + 2];
    if (l > best) { best = l; bi = i; }
  }
  const u = (bi % width) / width;
  const v = Math.floor(bi / width) / height;
  // three's equirectUv: u = atan2(z, x)/2pi + 0.5, v = asin(y)/pi + 0.5
  const az = (u - 0.5) * Math.PI * 2;
  const el = (v - 0.5) * Math.PI;
  const cy = Math.cos(el);
  const dir = new THREE.Vector3(Math.cos(az) * cy, Math.abs(Math.sin(el)), Math.sin(az) * cy);
  return dir.normalize();
}

export async function loadAssets(renderer) {
  const maxAniso = renderer.capabilities.getMaxAnisotropy();
  const aniso = Math.min(16, maxAniso);
  const tl = new THREE.TextureLoader();
  const t = (url, opts = {}) => loadTex(tl, url, { aniso, ...opts });

  const rgbe = new RGBELoader().setDataType(THREE.FloatType);
  const hdrPromise = new Promise((res, rej) => rgbe.load('assets/sky/sky_1k.hdr', res, undefined, rej));

  const [
    grassD, grassN, grassR, roughD, roughN, roughR, sandD, sandN, sandR,
    skyBg, skyEnv,
    twigD, twigA, pineBark, leafD, leafA, leafBark,
    waterN,
  ] = await Promise.all([
    t('assets/ground/grass_diff.jpg', { srgb: true }),
    t('assets/ground/grass_nor.jpg'),
    t('assets/ground/grass_rough.jpg'),
    t('assets/ground/rough_diff.jpg', { srgb: true }),
    t('assets/ground/rough_nor.jpg'),
    t('assets/ground/rough_rough.jpg'),
    t('assets/ground/sand_diff.jpg', { srgb: true }),
    t('assets/ground/sand_nor.jpg'),
    t('assets/ground/sand_rough.jpg'),
    t('assets/sky/sky_bg.jpg', { srgb: true, aniso: maxAniso }),
    hdrPromise,
    t('assets/trees/pine_twig_diff.jpg', { srgb: true }),
    t('assets/trees/pine_twig_alpha.jpg'),
    t('assets/trees/pine_bark_diff.jpg', { srgb: true }),
    t('assets/trees/leaf_diff.jpg', { srgb: true }),
    t('assets/trees/leaf_alpha.jpg'),
    t('assets/trees/leaf_bark_diff.jpg', { srgb: true }),
    t('assets/water/waternormals.jpg'),
  ]);

  skyBg.mapping = THREE.EquirectangularReflectionMapping;
  skyEnv.mapping = THREE.EquirectangularReflectionMapping;

  return {
    ground: {
      grassD, grassN, grassR, roughD, roughN, roughR, sandD, sandN, sandR,
      grassMean: meanColor(grassD),
      roughMean: meanColor(roughD),
      sandMean: meanColor(sandD),
    },
    trees: {
      pineCard: cardTexture(twigD, twigA, aniso, 1.5),
      leafCard: cardTexture(leafD, leafA, aniso, 1.15),
      pineBark, leafBark,
    },
    skyBg,
    skyEnv,
    waterN,
    sunDir: sunFromEquirect(skyEnv),
  };
}
