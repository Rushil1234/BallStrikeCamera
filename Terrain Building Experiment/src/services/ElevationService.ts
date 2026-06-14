import {
  latLngToTile,
  latLngToTileFrac,
  centerToBounds,
  pickElevZoom,
} from '../utils/CoordinateUtils';
import type { ElevationGrid } from '../types';

// AWS Terrain Tiles — Terrarium RGB format, CORS enabled, no API key required
const TERRARIUM_URL = (z: number, x: number, y: number) =>
  `https://s3.amazonaws.com/elevation-tiles-prod/terrarium/${z}/${x}/${y}.png`;

function decodeTerrarium(r: number, g: number, b: number): number {
  return r * 256 + g + b / 256 - 32768;
}

async function loadTilePixels(url: string): Promise<ImageData> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      const canvas = document.createElement('canvas');
      canvas.width = 256;
      canvas.height = 256;
      const ctx = canvas.getContext('2d')!;
      ctx.drawImage(img, 0, 0);
      resolve(ctx.getImageData(0, 0, 256, 256));
    };
    img.onerror = () => reject(new Error(`Elevation tile failed: ${url}`));
    img.src = url;
  });
}

export async function fetchElevationGrid(
  centerLat: number,
  centerLng: number,
  widthMeters: number,
  heightMeters: number,
  resolution: number,
  onProgress?: (msg: string) => void
): Promise<ElevationGrid> {
  const bounds = centerToBounds(centerLat, centerLng, widthMeters, heightMeters);
  const zoom = pickElevZoom(centerLat, Math.max(widthMeters, heightMeters), resolution);

  const tl = latLngToTile(bounds.maxLat, bounds.minLng, zoom);
  const br = latLngToTile(bounds.minLat, bounds.maxLng, zoom);
  const minTX = tl.x, maxTX = br.x;
  const minTY = tl.y, maxTY = br.y;

  onProgress?.(`Fetching elevation (zoom ${zoom}, ${(maxTX - minTX + 1) * (maxTY - minTY + 1)} tiles)…`);

  const tileJobs: Promise<{ tx: number; ty: number; data: ImageData }>[] = [];
  for (let ty = minTY; ty <= maxTY; ty++) {
    for (let tx = minTX; tx <= maxTX; tx++) {
      tileJobs.push(
        loadTilePixels(TERRARIUM_URL(zoom, tx, ty)).then((data) => ({ tx, ty, data }))
      );
    }
  }
  const tiles = await Promise.all(tileJobs);

  const tileMap = new Map<string, ImageData>();
  for (const t of tiles) tileMap.set(`${t.tx},${t.ty}`, t.data);

  // Sample grid: row 0 = northernmost (maxLat), row N-1 = southernmost (minLat)
  const rows = resolution;
  const cols = resolution;
  const heightmap: number[][] = [];
  let minElevation = Infinity, maxElevation = -Infinity;

  for (let row = 0; row < rows; row++) {
    const lat =
      bounds.maxLat - (row / (rows - 1)) * (bounds.maxLat - bounds.minLat);
    const heightmapRow: number[] = [];

    for (let col = 0; col < cols; col++) {
      const lng =
        bounds.minLng + (col / (cols - 1)) * (bounds.maxLng - bounds.minLng);

      const frac = latLngToTileFrac(lat, lng, zoom);
      const tileX = Math.floor(frac.x);
      const tileY = Math.floor(frac.y);
      const pixX = Math.min(255, Math.max(0, Math.floor((frac.x - tileX) * 256)));
      const pixY = Math.min(255, Math.max(0, Math.floor((frac.y - tileY) * 256)));

      const data = tileMap.get(`${tileX},${tileY}`);
      let elev = 0;
      if (data) {
        const i = (pixY * 256 + pixX) * 4;
        elev = decodeTerrarium(data.data[i], data.data[i + 1], data.data[i + 2]);
      }

      heightmapRow.push(elev);
      if (elev < minElevation) minElevation = elev;
      if (elev > maxElevation) maxElevation = elev;
    }
    heightmap.push(heightmapRow);
  }

  return { heightmap, minElevation, maxElevation, rows, cols };
}
