// Weighted box blur (Gaussian approximation)
export function smoothHeightmap(heightmap: number[][], passes: number): number[][] {
  if (passes === 0) return heightmap;
  const rows = heightmap.length;
  const cols = heightmap[0].length;
  let cur = heightmap.map((r) => [...r]);
  for (let p = 0; p < passes; p++) {
    const next = cur.map((r) => [...r]);
    for (let r = 1; r < rows - 1; r++) {
      for (let c = 1; c < cols - 1; c++) {
        next[r][c] =
          (cur[r - 1][c - 1] +
            cur[r - 1][c] * 2 +
            cur[r - 1][c + 1] +
            cur[r][c - 1] * 2 +
            cur[r][c] * 4 +
            cur[r][c + 1] * 2 +
            cur[r + 1][c - 1] +
            cur[r + 1][c] * 2 +
            cur[r + 1][c + 1]) /
          16;
      }
    }
    cur = next;
  }
  return cur;
}

export function heightmapStats(heightmap: number[][]): { min: number; max: number; mean: number } {
  let min = Infinity, max = -Infinity, sum = 0, count = 0;
  for (const row of heightmap) {
    for (const v of row) {
      if (v < min) min = v;
      if (v > max) max = v;
      sum += v;
      count++;
    }
  }
  return { min, max, mean: sum / count };
}

// Map smoothing percent (0-100) to blur passes
export function smoothPctToPasses(pct: number): number {
  if (pct === 0) return 0;
  if (pct <= 25) return 1;
  if (pct <= 50) return 3;
  if (pct <= 75) return 6;
  return 12;
}
