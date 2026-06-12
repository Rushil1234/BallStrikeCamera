// Pine Hollow National — 18 holes, par 72, ~6,900 yards.
// All coordinates in meters, each hole in its own local space (the tee is
// path[0], the last path point is the green center). Bunkers/greens are
// rotated ellipses; water is an ellipse pond or a channel (polyline+width).
// fairwayProfile is [[along_m, half_width_m], ...] — fairways flare at the
// landing zones and pinch where the architect wants you to think.

export const HOLES = [
  // ---------------- FRONT NINE (par 36) ----------------
  {
    id: 1, name: 'PINEHURST BEND', par: 4, seed: 1117,
    path: [{ x: 0, z: 0 }, { x: 2, z: 120 }, { x: -18, z: 235 }, { x: -30, z: 330 }],
    fairwayHalf: 17,
    fairwayProfile: [[0, 13], [110, 19], [230, 21], [280, 14], [332, 11]],
    green: { cx: -30, cz: 330, rx: 14, rz: 18, rot: -0.25 },
    pin: { x: -27, z: 334 },
    bunkers: [
      { cx: 14, cz: 228, rx: 9, rz: 16, rot: 0.5, depth: 1.1 },
      { cx: -38, cz: 200, rx: 6, rz: 10, rot: -0.4, depth: 0.9 },
      { cx: -44, cz: 318, rx: 6, rz: 9, rot: 0.3, depth: 1.2 },
      { cx: -16, cz: 316, rx: 5, rz: 7, rot: -0.4, depth: 1.0 },
    ],
    water: [],
    treeDensity: 1.0, windMax: 5,
  },
  {
    // homage: Augusta National 12 ("Golden Bell") — short iron over the
    // creek to a wide, shallow, angled green; swirling wind decides it
    id: 2, name: 'GOLDEN BELL', par: 3, seed: 2229,
    path: [{ x: 0, z: 0 }, { x: 8, z: 155 }],
    fairwayHalf: 12,
    fairwayProfile: [[0, 9], [110, 10], [155, 14]],
    green: { cx: 8, cz: 155, rx: 16, rz: 8, rot: -0.35 },
    pin: { x: 13, z: 156 },
    bunkers: [
      { cx: 6, cz: 143, rx: 7, rz: 3.5, rot: -0.3, depth: 1.4 },
      { cx: 0, cz: 167, rx: 5, rz: 4, rot: 0.2, depth: 1.1 },
      { cx: 17, cz: 165, rx: 4, rz: 4, rot: -0.2, depth: 1.1 },
    ],
    water: [{ type: 'channel', width: 10, pts: [
      { x: -60, z: 124 }, { x: 8, z: 136 }, { x: 70, z: 124 },
    ] }],
    treeDensity: 1.25, windMax: 8,
  },
  {
    id: 3, name: 'CREEKSIDE LONG', par: 5, seed: 3331,
    path: [{ x: 0, z: 0 }, { x: -5, z: 150 }, { x: 15, z: 300 }, { x: 60, z: 420 }, { x: 75, z: 470 }],
    fairwayHalf: 16,
    fairwayProfile: [[0, 13], [130, 20], [240, 17], [310, 13], [380, 18], [470, 12]],
    green: { cx: 75, cz: 470, rx: 13, rz: 17, rot: 0.5 },
    pin: { x: 77, z: 474 },
    bunkers: [
      { cx: -24, cz: 215, rx: 8, rz: 14, rot: -0.4, depth: 1.1 },
      { cx: 38, cz: 352, rx: 7, rz: 11, rot: 0.7, depth: 1.0 },
      { cx: 80, cz: 430, rx: 5, rz: 8, rot: 0.6, depth: 0.9 },
      { cx: 60, cz: 455, rx: 6, rz: 9, rot: 0.5, depth: 1.2 },
    ],
    water: [{ type: 'channel', width: 11, pts: [
      { x: -90, z: 285 }, { x: -10, z: 268 }, { x: 60, z: 282 }, { x: 130, z: 265 },
    ] }],
    treeDensity: 0.9, windMax: 6,
  },
  {
    id: 4, name: 'BROKEN OAK', par: 4, seed: 4441,
    path: [{ x: 0, z: 0 }, { x: -3, z: 160 }, { x: 30, z: 290 }, { x: 45, z: 372 }],
    fairwayHalf: 16,
    fairwayProfile: [[0, 12], [140, 20], [250, 15], [310, 17], [377, 11]],
    green: { cx: 45, cz: 372, rx: 13, rz: 16, rot: 0.3 },
    pin: { x: 47, z: 375 },
    bunkers: [
      { cx: -20, cz: 225, rx: 8, rz: 13, rot: -0.3, depth: 1.1 },
      { cx: 28, cz: 250, rx: 6, rz: 9, rot: 0.5, depth: 1.0 },
      { cx: 58, cz: 362, rx: 5, rz: 8, rot: 0.4, depth: 1.3 },
      { cx: 33, cz: 357, rx: 5, rz: 6, rot: -0.2, depth: 1.1 },
    ],
    water: [],
    treeDensity: 1.1, windMax: 5,
  },
  {
    // homage: Royal Troon 8 ("Postage Stamp") — a wedge to a tiny green
    // ringed by pot bunkers deep enough to lose a caddie in
    id: 5, name: 'POSTAGE STAMP', par: 3, seed: 5557,
    path: [{ x: 0, z: 0 }, { x: -6, z: 112 }],
    fairwayHalf: 9,
    fairwayProfile: [[0, 7], [80, 8], [112, 10]],
    green: { cx: -6, cz: 112, rx: 8.5, rz: 10, rot: 0.2 },
    pin: { x: -4, z: 114 },
    bunkers: [
      { cx: -19, cz: 108, rx: 5, rz: 8, rot: 0.5, depth: 1.8 },
      { cx: 6, cz: 104, rx: 4, rz: 6, rot: -0.4, depth: 1.6 },
      { cx: -11, cz: 126, rx: 5, rz: 5, rot: 0.1, depth: 1.7 },
      { cx: 1, cz: 121, rx: 3, rz: 4, rot: 0.3, depth: 1.5 },
      { cx: -6, cz: 99, rx: 4, rz: 3, rot: 0, depth: 1.6 },
    ],
    water: [],
    treeDensity: 1.3, windMax: 9,
  },
  {
    id: 6, name: 'TWIN PINES', par: 4, seed: 6661,
    path: [{ x: 0, z: 0 }, { x: 4, z: 150 }, { x: -12, z: 260 }, { x: -20, z: 355 }],
    fairwayHalf: 15,
    fairwayProfile: [[0, 12], [130, 19], [235, 13], [300, 16], [356, 11]],
    green: { cx: -20, cz: 355, rx: 13, rz: 16, rot: -0.2 },
    pin: { x: -18, z: 358 },
    bunkers: [
      { cx: 24, cz: 235, rx: 8, rz: 13, rot: 0.4, depth: 1.1 },
      { cx: -34, cz: 245, rx: 7, rz: 11, rot: -0.5, depth: 1.0 },
      { cx: -33, cz: 345, rx: 5, rz: 8, rot: 0.2, depth: 1.2 },
      { cx: -8, cz: 342, rx: 4, rz: 6, rot: -0.3, depth: 1.0 },
    ],
    water: [],
    treeDensity: 1.0, windMax: 5,
  },
  {
    id: 7, name: 'THE GAUNTLET', par: 5, seed: 7771,
    path: [{ x: 0, z: 0 }, { x: 8, z: 170 }, { x: -25, z: 330 }, { x: 15, z: 440 }, { x: 28, z: 490 }],
    fairwayHalf: 15,
    fairwayProfile: [[0, 12], [150, 19], [260, 14], [330, 16], [410, 12], [490, 11]],
    green: { cx: 28, cz: 490, rx: 13, rz: 16, rot: 0.4 },
    pin: { x: 30, z: 493 },
    bunkers: [
      { cx: -18, cz: 240, rx: 8, rz: 13, rot: -0.4, depth: 1.1 },
      { cx: 22, cz: 260, rx: 6, rz: 9, rot: 0.4, depth: 0.9 },
      { cx: 5, cz: 395, rx: 7, rz: 10, rot: 0.5, depth: 1.0 },
      { cx: 12, cz: 480, rx: 5, rz: 8, rot: 0.3, depth: 1.3 },
    ],
    water: [{ type: 'pond', cx: 58, cz: 438, rx: 26, rz: 34, rot: 0.2 }],
    treeDensity: 1.0, windMax: 6,
  },
  {
    // homage: St Andrews 17 ("Road Hole") — blind dogleg right, then a
    // long, paper-thin green angled across the line with a tiny pot
    // bunker eating its front-left; OB presses in behind
    id: 8, name: 'THE ROAD', par: 4, seed: 8881,
    path: [{ x: 0, z: 0 }, { x: -6, z: 150 }, { x: 30, z: 275 }, { x: 42, z: 358 }],
    fairwayHalf: 15,
    fairwayProfile: [[0, 12], [140, 18], [250, 13], [310, 15], [360, 11]],
    green: { cx: 42, cz: 358, rx: 17, rz: 8, rot: 0.9 },
    pin: { x: 45, z: 360 },
    bunkers: [
      { cx: 36, cz: 351, rx: 4, rz: 5, rot: 0.2, depth: 2.2 },
      { cx: 8, cz: 265, rx: 7, rz: 11, rot: -0.4, depth: 1.1 },
      { cx: 50, cz: 300, rx: 6, rz: 9, rot: 0.5, depth: 1.0 },
    ],
    water: [],
    treeDensity: 0.95, windMax: 7, obMargin: 48,
  },
  {
    id: 9, name: 'HOMEWARD', par: 4, seed: 9991,
    path: [{ x: 0, z: 0 }, { x: -5, z: 180 }, { x: 15, z: 310 }, { x: 22, z: 399 }],
    fairwayHalf: 15,
    fairwayProfile: [[0, 12], [150, 19], [255, 15], [330, 13], [400, 11]],
    green: { cx: 22, cz: 399, rx: 13, rz: 16, rot: 0.25 },
    pin: { x: 24, z: 402 },
    bunkers: [
      { cx: 28, cz: 245, rx: 8, rz: 13, rot: 0.4, depth: 1.1 },
      { cx: -20, cz: 270, rx: 6, rz: 10, rot: -0.5, depth: 0.9 },
      { cx: 38, cz: 392, rx: 5, rz: 7, rot: 0.3, depth: 1.1 },
    ],
    water: [{ type: 'channel', width: 9, pts: [
      { x: -70, z: 355 }, { x: 0, z: 348 }, { x: 80, z: 352 },
    ] }],
    treeDensity: 0.9, windMax: 5,
  },

  // ---------------- BACK NINE (par 36) ----------------
  {
    id: 10, name: 'SHORT GRASS', par: 4, seed: 10103,
    path: [{ x: 0, z: 0 }, { x: 2, z: 140 }, { x: -28, z: 250 }, { x: -38, z: 322 }],
    fairwayHalf: 18,
    fairwayProfile: [[0, 14], [120, 22], [210, 24], [270, 15], [325, 12]],
    green: { cx: -38, cz: 322, rx: 14, rz: 16, rot: -0.3 },
    pin: { x: -36, z: 325 },
    bunkers: [
      { cx: -30, cz: 215, rx: 9, rz: 14, rot: -0.5, depth: 1.3 },
      { cx: 18, cz: 235, rx: 6, rz: 9, rot: 0.4, depth: 0.9 },
      { cx: -30, cz: 308, rx: 5, rz: 8, rot: 0.2, depth: 1.2 },
      { cx: -52, cz: 316, rx: 5, rz: 7, rot: -0.3, depth: 1.1 },
    ],
    water: [],
    treeDensity: 1.0, windMax: 4,
  },
  {
    id: 11, name: 'WELLSPRING', par: 3, seed: 11113,
    path: [{ x: 0, z: 0 }, { x: 10, z: 152 }],
    fairwayHalf: 10,
    fairwayProfile: [[0, 8], [110, 9], [152, 12]],
    green: { cx: 10, cz: 152, rx: 13, rz: 12, rot: 0.3 },
    pin: { x: 12, z: 154 },
    bunkers: [
      { cx: 26, cz: 148, rx: 5, rz: 8, rot: 0.4, depth: 1.1 },
      { cx: 18, cz: 132, rx: 4, rz: 6, rot: -0.2, depth: 1.0 },
    ],
    water: [{ type: 'pond', cx: -18, cz: 95, rx: 30, rz: 45, rot: 0.1 }],
    treeDensity: 1.15, windMax: 6,
  },
  {
    id: 12, name: 'LONG MARCH', par: 5, seed: 12119,
    path: [{ x: 0, z: 0 }, { x: -8, z: 180 }, { x: 10, z: 360 }, { x: 18, z: 519 }],
    fairwayHalf: 15,
    fairwayProfile: [[0, 12], [160, 20], [270, 14], [360, 17], [450, 13], [520, 11]],
    green: { cx: 18, cz: 519, rx: 13, rz: 17, rot: 0.2 },
    pin: { x: 20, z: 523 },
    bunkers: [
      { cx: -26, cz: 230, rx: 8, rz: 13, rot: -0.4, depth: 1.1 },
      { cx: 28, cz: 300, rx: 7, rz: 11, rot: 0.5, depth: 1.0 },
      { cx: 2, cz: 470, rx: 7, rz: 10, rot: -0.2, depth: 1.0 },
      { cx: 32, cz: 512, rx: 5, rz: 8, rot: 0.4, depth: 1.3 },
      { cx: -14, cz: 430, rx: 6, rz: 9, rot: 0.3, depth: 0.9 },
    ],
    water: [],
    treeDensity: 0.85, windMax: 6,
  },
  {
    id: 13, name: 'AMEN OAK', par: 4, seed: 13127,
    path: [{ x: 0, z: 0 }, { x: -4, z: 155 }, { x: 35, z: 270 }, { x: 48, z: 355 }],
    fairwayHalf: 15,
    fairwayProfile: [[0, 12], [135, 19], [230, 13], [300, 15], [362, 11]],
    green: { cx: 48, cz: 355, rx: 13, rz: 15, rot: 0.35 },
    pin: { x: 50, z: 358 },
    bunkers: [
      { cx: 45, cz: 240, rx: 8, rz: 12, rot: 0.6, depth: 1.2 },
      { cx: -18, cz: 215, rx: 6, rz: 10, rot: -0.4, depth: 0.9 },
      { cx: 34, cz: 346, rx: 5, rz: 8, rot: -0.2, depth: 1.2 },
    ],
    water: [],
    treeDensity: 1.25, windMax: 5,
  },
  {
    id: 14, name: 'THE BEAST', par: 4, seed: 14143,
    path: [{ x: 0, z: 0 }, { x: -14, z: 190 }, { x: 20, z: 310 }, { x: 28, z: 392 }],
    fairwayHalf: 15,
    fairwayProfile: [[0, 12], [170, 18], [280, 13], [340, 15], [398, 11]],
    green: { cx: 28, cz: 392, rx: 14, rz: 16, rot: 0.25 },
    pin: { x: 30, z: 395 },
    bunkers: [
      { cx: -30, cz: 260, rx: 8, rz: 13, rot: -0.4, depth: 1.1 },
      { cx: 34, cz: 280, rx: 7, rz: 11, rot: 0.5, depth: 1.0 },
      { cx: 14, cz: 382, rx: 5, rz: 8, rot: 0.1, depth: 1.3 },
    ],
    water: [],
    treeDensity: 0.9, windMax: 7,
  },
  {
    // homage: Augusta National 13 ("Azalea") — sweeping par-5 dogleg
    // left; the tributary creek runs up the left side then crosses right
    // in front of the green, daring you to go for it in two
    id: 15, name: 'AZALEA BEND', par: 5, seed: 15149,
    path: [{ x: 0, z: 0 }, { x: 6, z: 160 }, { x: -30, z: 320 }, { x: -55, z: 440 }, { x: -60, z: 485 }],
    fairwayHalf: 15,
    fairwayProfile: [[0, 12], [150, 19], [260, 15], [340, 16], [420, 13], [488, 11]],
    green: { cx: -60, cz: 485, rx: 14, rz: 13, rot: -0.3 },
    pin: { x: -58, z: 488 },
    bunkers: [
      { cx: 16, cz: 245, rx: 8, rz: 12, rot: 0.4, depth: 1.1 },
      { cx: -74, cz: 500, rx: 4, rz: 5, rot: 0.3, depth: 1.2 },
      { cx: -62, cz: 505, rx: 4, rz: 4, rot: -0.2, depth: 1.2 },
      { cx: -50, cz: 502, rx: 4, rz: 5, rot: 0.2, depth: 1.2 },
    ],
    water: [{ type: 'channel', width: 8, pts: [
      { x: -100, z: 380 }, { x: -82, z: 430 }, { x: -62, z: 462 }, { x: -20, z: 468 }, { x: 40, z: 455 },
    ] }],
    treeDensity: 1.1, windMax: 5,
  },
  {
    id: 16, name: 'EDGE OF NIGHT', par: 4, seed: 16157,
    path: [{ x: 0, z: 0 }, { x: 6, z: 190 }, { x: -18, z: 320 }, { x: -26, z: 407 }],
    fairwayHalf: 15,
    fairwayProfile: [[0, 12], [160, 18], [265, 12], [330, 15], [410, 11]],
    green: { cx: -26, cz: 407, rx: 13, rz: 16, rot: -0.25 },
    pin: { x: -24, z: 410 },
    bunkers: [
      { cx: -32, cz: 255, rx: 8, rz: 13, rot: -0.5, depth: 1.1 },
      { cx: 22, cz: 270, rx: 7, rz: 11, rot: 0.4, depth: 1.0 },
      { cx: -40, cz: 396, rx: 5, rz: 8, rot: 0.2, depth: 1.3 },
      { cx: -12, cz: 394, rx: 5, rz: 7, rot: -0.3, depth: 1.2 },
    ],
    water: [],
    treeDensity: 1.0, windMax: 6,
  },
  {
    // homage: TPC Sawgrass 17 ("The Island") — a true island green:
    // eight overlapping ponds form an unbroken moat around the putting
    // surface; there is the green, and there is the water
    id: 17, name: 'THE ISLAND', par: 3, seed: 17167,
    path: [{ x: 0, z: 0 }, { x: 5, z: 152 }],
    fairwayHalf: 10,
    fairwayProfile: [[0, 8], [100, 9], [152, 12]],
    green: { cx: 5, cz: 152, rx: 11, rz: 12, rot: 0.2 },
    pin: { x: 7, z: 154 },
    bunkers: [],
    water: [
      { type: 'pond', cx: 33, cz: 152, rx: 12.5, rz: 12.5, rot: 0 },
      { type: 'pond', cx: 24.8, cz: 171.8, rx: 12.5, rz: 12.5, rot: 0 },
      { type: 'pond', cx: 5, cz: 180, rx: 12.5, rz: 12.5, rot: 0 },
      { type: 'pond', cx: -14.8, cz: 171.8, rx: 12.5, rz: 12.5, rot: 0 },
      { type: 'pond', cx: -23, cz: 152, rx: 12.5, rz: 12.5, rot: 0 },
      { type: 'pond', cx: -14.8, cz: 132.2, rx: 12.5, rz: 12.5, rot: 0 },
      { type: 'pond', cx: 5, cz: 124, rx: 12.5, rz: 12.5, rot: 0 },
      { type: 'pond', cx: 24.8, cz: 132.2, rx: 12.5, rz: 12.5, rot: 0 },
    ],
    treeDensity: 1.2, windMax: 7,
  },
  {
    // homage: Pebble Beach 18 — the bay runs the entire left side from
    // tee to green; hug the water line to shorten the home hole
    id: 18, name: 'CRESCENT BAY', par: 4, seed: 18181,
    path: [{ x: 0, z: 0 }, { x: 14, z: 160 }, { x: 0, z: 290 }, { x: -12, z: 382 }],
    fairwayHalf: 16,
    fairwayProfile: [[0, 13], [150, 20], [250, 16], [320, 16], [386, 12]],
    green: { cx: -12, cz: 382, rx: 14, rz: 16, rot: -0.3 },
    pin: { x: -10, z: 385 },
    bunkers: [
      { cx: 34, cz: 245, rx: 8, rz: 13, rot: 0.5, depth: 1.1 },
      { cx: 4, cz: 372, rx: 5, rz: 8, rot: -0.2, depth: 1.3 },
      { cx: 16, cz: 300, rx: 6, rz: 9, rot: 0.4, depth: 1.0 },
    ],
    water: [{ type: 'channel', width: 26, pts: [
      { x: -52, z: -10 }, { x: -40, z: 150 }, { x: -34, z: 290 }, { x: -42, z: 400 },
    ] }],
    treeDensity: 1.05, windMax: 7,
  },
];

// Total playing length of a hole along its path, meters.
export function holeLength(hole) {
  let L = 0;
  for (let i = 1; i < hole.path.length; i++) {
    L += Math.hypot(hole.path[i].x - hole.path[i - 1].x, hole.path[i].z - hole.path[i - 1].z);
  }
  return L;
}
