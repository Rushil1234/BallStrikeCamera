// Deterministic 2D value noise + fbm. Seeded so each hole's terrain is stable.

function hash2(ix, iz, seed) {
  const s = Math.sin(ix * 127.1 + iz * 311.7 + seed * 74.7) * 43758.5453123;
  return s - Math.floor(s);
}

function smooth(t) { return t * t * (3 - 2 * t); }

export function makeNoise2D(seed = 1) {
  return function noise(x, z) {
    const ix = Math.floor(x), iz = Math.floor(z);
    const fx = x - ix, fz = z - iz;
    const a = hash2(ix, iz, seed);
    const b = hash2(ix + 1, iz, seed);
    const c = hash2(ix, iz + 1, seed);
    const d = hash2(ix + 1, iz + 1, seed);
    const ux = smooth(fx), uz = smooth(fz);
    return (a * (1 - ux) + b * ux) * (1 - uz) + (c * (1 - ux) + d * ux) * uz;
  };
}

// Fractal brownian motion in [-1, 1]
export function makeFbm(seed = 1, octaves = 4) {
  const noise = makeNoise2D(seed);
  return function fbm(x, z) {
    let amp = 0.5, freq = 1, sum = 0, norm = 0;
    for (let i = 0; i < octaves; i++) {
      sum += amp * (noise(x * freq, z * freq) * 2 - 1);
      norm += amp;
      amp *= 0.5;
      freq *= 2.07;
    }
    return sum / norm;
  };
}

// Seeded PRNG (mulberry32) for repeatable scatter
export function makeRng(seed) {
  let a = seed >>> 0;
  return function rng() {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
