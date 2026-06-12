// Pine Hollow National — 18 holes, par 72, ~6,900 yards.
// All coordinates in meters, each hole in its own local space (the tee is
// path[0], the last path point is the green center). Bunkers/greens are
// rotated ellipses; water is an ellipse pond or a channel (polyline+width).

export const HOLES = [
  // ---------------- FRONT NINE (par 36) ----------------
  {
    id: 1, name: 'PINEHURST BEND', par: 4, seed: 1117,
    path: [{ x: 0, z: 0 }, { x: 2, z: 120 }, { x: -18, z: 235 }, { x: -30, z: 330 }],
    fairwayHalf: 17,
    green: { cx: -30, cz: 330, rx: 14, rz: 18, rot: -0.25 },
    pin: { x: -27, z: 334 },
    bunkers: [
      { cx: 14, cz: 228, rx: 9, rz: 16, rot: 0.5, depth: 1.1 },
      { cx: -44, cz: 318, rx: 6, rz: 9, rot: 0.3, depth: 1.2 },
      { cx: -16, cz: 316, rx: 5, rz: 7, rot: -0.4, depth: 1.0 },
    ],
    water: [],
    treeDensity: 1.0, windMax: 5,
  },
  {
    id: 2, name: 'MIRROR CARRY', par: 3, seed: 2229,
    path: [{ x: 0, z: 0 }, { x: 8, z: 163 }],
    fairwayHalf: 12,
    green: { cx: 8, cz: 163, rx: 15, rz: 13, rot: 0.35 },
    pin: { x: 11, z: 166 },
    bunkers: [
      { cx: -8, cz: 172, rx: 6, rz: 9, rot: 0.6, depth: 1.2 },
      { cx: 22, cz: 154, rx: 5, rz: 7, rot: -0.3, depth: 1.0 },
    ],
    water: [{ type: 'pond', cx: 6, cz: 92, rx: 42, rz: 52, rot: 0.15 }],
    treeDensity: 1.25, windMax: 7,
  },
  {
    id: 3, name: 'CREEKSIDE LONG', par: 5, seed: 3331,
    path: [{ x: 0, z: 0 }, { x: -5, z: 150 }, { x: 15, z: 300 }, { x: 60, z: 420 }, { x: 75, z: 470 }],
    fairwayHalf: 16,
    green: { cx: 75, cz: 470, rx: 13, rz: 17, rot: 0.5 },
    pin: { x: 77, z: 474 },
    bunkers: [
      { cx: -24, cz: 215, rx: 8, rz: 14, rot: -0.4, depth: 1.1 },
      { cx: 38, cz: 352, rx: 7, rz: 11, rot: 0.7, depth: 1.0 },
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
    green: { cx: 45, cz: 372, rx: 13, rz: 16, rot: 0.3 },
    pin: { x: 47, z: 375 },
    bunkers: [
      { cx: -20, cz: 225, rx: 8, rz: 13, rot: -0.3, depth: 1.1 },
      { cx: 58, cz: 362, rx: 5, rz: 8, rot: 0.4, depth: 1.2 },
      { cx: 33, cz: 357, rx: 5, rz: 6, rot: -0.2, depth: 1.0 },
    ],
    water: [],
    treeDensity: 1.1, windMax: 5,
  },
  {
    id: 5, name: 'POSTAGE STAMP', par: 3, seed: 5557,
    path: [{ x: 0, z: 0 }, { x: -6, z: 139 }],
    fairwayHalf: 9,
    green: { cx: -6, cz: 139, rx: 10, rz: 11, rot: 0.2 },
    pin: { x: -4, z: 141 },
    bunkers: [
      { cx: -20, cz: 135, rx: 5, rz: 8, rot: 0.5, depth: 1.3 },
      { cx: 6, cz: 130, rx: 4, rz: 6, rot: -0.4, depth: 1.1 },
      { cx: -11, cz: 153, rx: 5, rz: 6, rot: 0.1, depth: 1.2 },
    ],
    water: [],
    treeDensity: 1.3, windMax: 8,
  },
  {
    id: 6, name: 'TWIN PINES', par: 4, seed: 6661,
    path: [{ x: 0, z: 0 }, { x: 4, z: 150 }, { x: -12, z: 260 }, { x: -20, z: 355 }],
    fairwayHalf: 15,
    green: { cx: -20, cz: 355, rx: 13, rz: 16, rot: -0.2 },
    pin: { x: -18, z: 358 },
    bunkers: [
      { cx: 24, cz: 235, rx: 8, rz: 13, rot: 0.4, depth: 1.1 },
      { cx: -34, cz: 245, rx: 7, rz: 11, rot: -0.5, depth: 1.0 },
      { cx: -33, cz: 345, rx: 5, rz: 8, rot: 0.2, depth: 1.2 },
    ],
    water: [],
    treeDensity: 1.0, windMax: 5,
  },
  {
    id: 7, name: 'THE GAUNTLET', par: 5, seed: 7771,
    path: [{ x: 0, z: 0 }, { x: 8, z: 170 }, { x: -25, z: 330 }, { x: 15, z: 440 }, { x: 28, z: 490 }],
    fairwayHalf: 15,
    green: { cx: 28, cz: 490, rx: 13, rz: 16, rot: 0.4 },
    pin: { x: 30, z: 493 },
    bunkers: [
      { cx: -18, cz: 240, rx: 8, rz: 13, rot: -0.4, depth: 1.1 },
      { cx: 5, cz: 395, rx: 7, rz: 10, rot: 0.5, depth: 1.0 },
      { cx: 12, cz: 480, rx: 5, rz: 8, rot: 0.3, depth: 1.2 },
    ],
    water: [{ type: 'pond', cx: 58, cz: 438, rx: 26, rz: 34, rot: 0.2 }],
    treeDensity: 1.0, windMax: 6,
  },
  {
    id: 8, name: 'HIGH NOON', par: 4, seed: 8881,
    path: [{ x: 0, z: 0 }, { x: 12, z: 180 }, { x: -8, z: 290 }, { x: -2, z: 362 }],
    fairwayHalf: 15,
    green: { cx: -2, cz: 362, rx: 13, rz: 15, rot: -0.3 },
    pin: { x: 0, z: 365 },
    bunkers: [
      { cx: 24, cz: 250, rx: 8, rz: 12, rot: 0.5, depth: 1.1 },
      { cx: -16, cz: 352, rx: 5, rz: 8, rot: -0.3, depth: 1.2 },
    ],
    water: [],
    treeDensity: 0.95, windMax: 7,
  },
  {
    id: 9, name: 'HOMEWARD', par: 4, seed: 9991,
    path: [{ x: 0, z: 0 }, { x: -5, z: 180 }, { x: 15, z: 310 }, { x: 22, z: 399 }],
    fairwayHalf: 15,
    green: { cx: 22, cz: 399, rx: 13, rz: 16, rot: 0.25 },
    pin: { x: 24, z: 402 },
    bunkers: [
      { cx: 28, cz: 245, rx: 8, rz: 13, rot: 0.4, depth: 1.1 },
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
    green: { cx: -38, cz: 322, rx: 14, rz: 16, rot: -0.3 },
    pin: { x: -36, z: 325 },
    bunkers: [
      { cx: -30, cz: 215, rx: 9, rz: 14, rot: -0.5, depth: 1.2 },
      { cx: -30, cz: 308, rx: 5, rz: 8, rot: 0.2, depth: 1.1 },
    ],
    water: [],
    treeDensity: 1.0, windMax: 4,
  },
  {
    id: 11, name: 'WELLSPRING', par: 3, seed: 11113,
    path: [{ x: 0, z: 0 }, { x: 10, z: 152 }],
    fairwayHalf: 10,
    green: { cx: 10, cz: 152, rx: 13, rz: 12, rot: 0.3 },
    pin: { x: 12, z: 154 },
    bunkers: [
      { cx: 26, cz: 148, rx: 5, rz: 8, rot: 0.4, depth: 1.1 },
    ],
    water: [{ type: 'pond', cx: -18, cz: 95, rx: 30, rz: 45, rot: 0.1 }],
    treeDensity: 1.15, windMax: 6,
  },
  {
    id: 12, name: 'LONG MARCH', par: 5, seed: 12119,
    path: [{ x: 0, z: 0 }, { x: -8, z: 180 }, { x: 10, z: 360 }, { x: 18, z: 519 }],
    fairwayHalf: 15,
    green: { cx: 18, cz: 519, rx: 13, rz: 17, rot: 0.2 },
    pin: { x: 20, z: 523 },
    bunkers: [
      { cx: -26, cz: 230, rx: 8, rz: 13, rot: -0.4, depth: 1.1 },
      { cx: 28, cz: 300, rx: 7, rz: 11, rot: 0.5, depth: 1.0 },
      { cx: 2, cz: 470, rx: 7, rz: 10, rot: -0.2, depth: 1.0 },
      { cx: 32, cz: 512, rx: 5, rz: 8, rot: 0.4, depth: 1.2 },
    ],
    water: [],
    treeDensity: 0.85, windMax: 6,
  },
  {
    id: 13, name: 'AMEN OAK', par: 4, seed: 13127,
    path: [{ x: 0, z: 0 }, { x: -4, z: 155 }, { x: 35, z: 270 }, { x: 48, z: 355 }],
    fairwayHalf: 15,
    green: { cx: 48, cz: 355, rx: 13, rz: 15, rot: 0.35 },
    pin: { x: 50, z: 358 },
    bunkers: [
      { cx: 45, cz: 240, rx: 8, rz: 12, rot: 0.6, depth: 1.2 },
      { cx: 34, cz: 346, rx: 5, rz: 8, rot: -0.2, depth: 1.1 },
    ],
    water: [],
    treeDensity: 1.25, windMax: 5,
  },
  {
    id: 14, name: 'THE BEAST', par: 4, seed: 14143,
    path: [{ x: 0, z: 0 }, { x: -14, z: 190 }, { x: 20, z: 310 }, { x: 28, z: 392 }],
    fairwayHalf: 15,
    green: { cx: 28, cz: 392, rx: 14, rz: 16, rot: 0.25 },
    pin: { x: 30, z: 395 },
    bunkers: [
      { cx: -30, cz: 260, rx: 8, rz: 13, rot: -0.4, depth: 1.1 },
      { cx: 34, cz: 280, rx: 7, rz: 11, rot: 0.5, depth: 1.0 },
      { cx: 14, cz: 382, rx: 5, rz: 8, rot: 0.1, depth: 1.2 },
    ],
    water: [],
    treeDensity: 0.9, windMax: 7,
  },
  {
    id: 15, name: 'RIVER RUN', par: 5, seed: 15149,
    path: [{ x: 0, z: 0 }, { x: -10, z: 170 }, { x: 8, z: 330 }, { x: -15, z: 430 }, { x: -22, z: 487 }],
    fairwayHalf: 15,
    green: { cx: -22, cz: 487, rx: 13, rz: 16, rot: -0.3 },
    pin: { x: -20, z: 490 },
    bunkers: [
      { cx: 12, cz: 250, rx: 8, rz: 12, rot: 0.4, depth: 1.1 },
      { cx: -8, cz: 478, rx: 5, rz: 8, rot: 0.3, depth: 1.2 },
    ],
    water: [{ type: 'channel', width: 10, pts: [
      { x: 60, z: 80 }, { x: 45, z: 260 }, { x: -5, z: 375 }, { x: -90, z: 390 },
    ] }],
    treeDensity: 0.95, windMax: 5,
  },
  {
    id: 16, name: 'EDGE OF NIGHT', par: 4, seed: 16157,
    path: [{ x: 0, z: 0 }, { x: 6, z: 190 }, { x: -18, z: 320 }, { x: -26, z: 407 }],
    fairwayHalf: 15,
    green: { cx: -26, cz: 407, rx: 13, rz: 16, rot: -0.25 },
    pin: { x: -24, z: 410 },
    bunkers: [
      { cx: -32, cz: 255, rx: 8, rz: 13, rot: -0.5, depth: 1.1 },
      { cx: 22, cz: 270, rx: 7, rz: 11, rot: 0.4, depth: 1.0 },
      { cx: -40, cz: 396, rx: 5, rz: 8, rot: 0.2, depth: 1.2 },
      { cx: -12, cz: 394, rx: 5, rz: 7, rot: -0.3, depth: 1.1 },
    ],
    water: [],
    treeDensity: 1.0, windMax: 6,
  },
  {
    id: 17, name: 'ISLAND LOOK', par: 3, seed: 17167,
    path: [{ x: 0, z: 0 }, { x: 5, z: 172 }],
    fairwayHalf: 10,
    green: { cx: 5, cz: 172, rx: 13, rz: 12, rot: 0.2 },
    pin: { x: 7, z: 174 },
    bunkers: [
      { cx: 10, cz: 190, rx: 6, rz: 6, rot: 0, depth: 1.1 },
    ],
    water: [{ type: 'pond', cx: 2, cz: 105, rx: 38, rz: 48, rot: 0.1 }],
    treeDensity: 1.2, windMax: 7,
  },
  {
    id: 18, name: 'CLUBHOUSE TURN', par: 4, seed: 18181,
    path: [{ x: 0, z: 0 }, { x: 10, z: 175 }, { x: -20, z: 300 }, { x: -30, z: 384 }],
    fairwayHalf: 16,
    green: { cx: -30, cz: 384, rx: 14, rz: 16, rot: -0.3 },
    pin: { x: -28, z: 387 },
    bunkers: [
      { cx: 26, cz: 240, rx: 8, rz: 13, rot: 0.5, depth: 1.1 },
      { cx: -16, cz: 375, rx: 5, rz: 8, rot: -0.2, depth: 1.2 },
    ],
    water: [{ type: 'pond', cx: -62, cz: 350, rx: 26, rz: 40, rot: 0.15 }],
    treeDensity: 1.05, windMax: 6,
  },
];

// Driving range: flat, straight, no scoring.
export const RANGE = {
  id: 0, name: 'RANGE', par: null, seed: 9999, isRange: true,
  path: [{ x: 0, z: 0 }, { x: 0, z: 350 }],
  fairwayHalf: 80,
  obMargin: 9999,
  green: { cx: 0, cz: 350, rx: 30, rz: 30, rot: 0 },
  pin: { x: 0, z: 350 },
  bunkers: [],
  water: [],
  treeDensity: 0,
  windMax: 8,
};

// Total playing length of a hole along its path, meters.
export function holeLength(hole) {
  let L = 0;
  for (let i = 1; i < hole.path.length; i++) {
    L += Math.hypot(hole.path[i].x - hole.path[i - 1].x, hole.path[i].z - hole.path[i - 1].z);
  }
  return L;
}
