import * as THREE from 'three';
import type { ElevationGrid } from '../types';
import { smoothHeightmap, smoothPctToPasses } from '../utils/TerrainMath';

export interface BuildOptions {
  widthMeters: number;
  heightMeters: number;
  elevExaggeration: number;
  smoothingPct: number;
}

export function buildTerrainGeometry(
  elevGrid: ElevationGrid,
  opts: BuildOptions
): THREE.BufferGeometry {
  const { widthMeters, heightMeters, elevExaggeration, smoothingPct } = opts;
  const passes = smoothPctToPasses(smoothingPct);
  const heightmap = passes > 0
    ? smoothHeightmap(elevGrid.heightmap, passes)
    : elevGrid.heightmap;

  const rows = elevGrid.rows;
  const cols = elevGrid.cols;
  const baseElev = elevGrid.minElevation;

  const positions = new Float32Array(rows * cols * 3);
  const uvs = new Float32Array(rows * cols * 2);
  const indices: number[] = [];

  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      const i = row * cols + col;

      // row 0 = north (+z), row N-1 = south (-z)
      // col 0 = west (-x), col N-1 = east (+x)
      const x = -widthMeters / 2 + col * (widthMeters / (cols - 1));
      const z = heightMeters / 2 - row * (heightMeters / (rows - 1));
      const y = (heightmap[row][col] - baseElev) * elevExaggeration;

      positions[i * 3 + 0] = x;
      positions[i * 3 + 1] = y;
      positions[i * 3 + 2] = z;

      // UV: u 0→1 west→east, v 1→0 north→south
      // (Three.js flipY=true: V=1 = north = top of canvas)
      uvs[i * 2 + 0] = col / (cols - 1);
      uvs[i * 2 + 1] = 1 - row / (rows - 1);
    }
  }

  for (let row = 0; row < rows - 1; row++) {
    for (let col = 0; col < cols - 1; col++) {
      const tl = row * cols + col;
      const tr = row * cols + col + 1;
      const bl = (row + 1) * cols + col;
      const br = (row + 1) * cols + col + 1;
      indices.push(tl, bl, tr);
      indices.push(tr, bl, br);
    }
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  geo.setAttribute('uv', new THREE.BufferAttribute(uvs, 2));
  geo.setIndex(indices);
  geo.computeVertexNormals();
  return geo;
}

export function sampleElevationAt(
  worldX: number,
  worldZ: number,
  elevGrid: ElevationGrid,
  widthMeters: number,
  heightMeters: number
): number {
  const col = Math.round(((worldX + widthMeters / 2) / widthMeters) * (elevGrid.cols - 1));
  const row = Math.round(((heightMeters / 2 - worldZ) / heightMeters) * (elevGrid.rows - 1));
  const r = Math.max(0, Math.min(elevGrid.rows - 1, row));
  const c = Math.max(0, Math.min(elevGrid.cols - 1, col));
  return elevGrid.heightmap[r][c];
}
