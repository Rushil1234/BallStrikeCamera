export const METERS_PER_DEG_LAT = 111320;

export function metersPerDegreeLng(lat: number): number {
  return Math.cos((lat * Math.PI) / 180) * 111320;
}

export function latLngToTile(
  lat: number,
  lng: number,
  zoom: number
): { x: number; y: number } {
  const n = Math.pow(2, zoom);
  const x = Math.floor(((lng + 180) / 360) * n);
  const latRad = (lat * Math.PI) / 180;
  const y = Math.floor(
    ((1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI) / 2) * n
  );
  return { x, y };
}

export function latLngToTileFrac(
  lat: number,
  lng: number,
  zoom: number
): { x: number; y: number } {
  const n = Math.pow(2, zoom);
  const x = ((lng + 180) / 360) * n;
  const latRad = (lat * Math.PI) / 180;
  const y =
    ((1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI) / 2) * n;
  return { x, y };
}

export function centerToBounds(
  lat: number,
  lng: number,
  widthMeters: number,
  heightMeters: number
): { minLat: number; maxLat: number; minLng: number; maxLng: number } {
  const halfLatDeg = heightMeters / 2 / METERS_PER_DEG_LAT;
  const halfLngDeg = widthMeters / 2 / metersPerDegreeLng(lat);
  return {
    minLat: lat - halfLatDeg,
    maxLat: lat + halfLatDeg,
    minLng: lng - halfLngDeg,
    maxLng: lng + halfLngDeg,
  };
}

// Zoom level so tile pixels are finer than areaMeters/targetPixels
export function pickElevZoom(lat: number, areaMeters: number, targetPixels: number): number {
  const earthC = 40075016.686 * Math.cos((lat * Math.PI) / 180);
  const minZoom = Math.ceil(Math.log2((earthC * targetPixels) / (256 * areaMeters)));
  return Math.max(10, Math.min(15, minZoom));
}

// Satellite: aim for ~5 tiles across, cap at z17
export function pickSatZoom(lat: number, areaMeters: number): number {
  const earthC = 40075016.686 * Math.cos((lat * Math.PI) / 180);
  const zoom = Math.round(Math.log2((earthC * 5) / (256 * areaMeters)));
  return Math.max(12, Math.min(17, zoom));
}
