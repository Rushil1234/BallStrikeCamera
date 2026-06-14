import * as THREE from 'three';
import {
  latLngToTile,
  latLngToTileFrac,
  centerToBounds,
  pickSatZoom,
} from '../utils/CoordinateUtils';

// ESRI World Imagery — free, no API key, CORS enabled
// Note: ESRI tile URL order is z/y/x (not z/x/y)
const ESRI_URL = (z: number, y: number, x: number) =>
  `https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/${z}/${y}/${x}`;

async function loadImg(url: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error(`Satellite tile failed: ${url}`));
    img.src = url;
  });
}

export async function fetchSatelliteTexture(
  centerLat: number,
  centerLng: number,
  widthMeters: number,
  heightMeters: number,
  onProgress?: (msg: string) => void
): Promise<THREE.CanvasTexture> {
  const areaMeters = Math.max(widthMeters, heightMeters);
  const zoom = pickSatZoom(centerLat, areaMeters);
  const bounds = centerToBounds(centerLat, centerLng, widthMeters, heightMeters);

  const tl = latLngToTile(bounds.maxLat, bounds.minLng, zoom);
  const br = latLngToTile(bounds.minLat, bounds.maxLng, zoom);
  const minTX = tl.x, maxTX = br.x;
  const minTY = tl.y, maxTY = br.y;
  const tileCountX = maxTX - minTX + 1;
  const tileCountY = maxTY - minTY + 1;

  onProgress?.(
    `Fetching satellite imagery (zoom ${zoom}, ${tileCountX * tileCountY} tiles)…`
  );

  const imgJobs: Promise<{ tx: number; ty: number; img: HTMLImageElement }>[] = [];
  for (let ty = minTY; ty <= maxTY; ty++) {
    for (let tx = minTX; tx <= maxTX; tx++) {
      imgJobs.push(
        loadImg(ESRI_URL(zoom, ty, tx)).then((img) => ({ tx, ty, img }))
      );
    }
  }
  const images = await Promise.all(imgJobs);

  // Stitch all tiles onto one canvas
  const stitchCanvas = document.createElement('canvas');
  stitchCanvas.width = tileCountX * 256;
  stitchCanvas.height = tileCountY * 256;
  const ctx = stitchCanvas.getContext('2d')!;
  for (const { tx, ty, img } of images) {
    ctx.drawImage(img, (tx - minTX) * 256, (ty - minTY) * 256);
  }

  // Crop to exact lat/lng bounds
  const fracTL = latLngToTileFrac(bounds.maxLat, bounds.minLng, zoom);
  const fracBR = latLngToTileFrac(bounds.minLat, bounds.maxLng, zoom);

  const cropX = Math.max(0, (fracTL.x - minTX) * 256);
  const cropY = Math.max(0, (fracTL.y - minTY) * 256);
  const cropW = Math.max(1, Math.min(stitchCanvas.width - cropX, (fracBR.x - minTX) * 256 - cropX));
  const cropH = Math.max(1, Math.min(stitchCanvas.height - cropY, (fracBR.y - minTY) * 256 - cropY));

  const outCanvas = document.createElement('canvas');
  outCanvas.width = Math.round(cropW);
  outCanvas.height = Math.round(cropH);
  outCanvas.getContext('2d')!.drawImage(
    stitchCanvas,
    cropX, cropY, cropW, cropH,
    0, 0, outCanvas.width, outCanvas.height
  );

  const texture = new THREE.CanvasTexture(outCanvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 16;
  return texture;
}
