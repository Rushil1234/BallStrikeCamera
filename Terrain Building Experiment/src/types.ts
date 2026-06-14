export interface TerrainConfig {
  lat: number;
  lng: number;
  widthMeters: number;
  heightMeters: number;
  resolution: 128 | 256 | 512;
}

export interface ElevationGrid {
  heightmap: number[][];  // [row][col], row 0 = northernmost
  minElevation: number;
  maxElevation: number;
  rows: number;
  cols: number;
}

export interface InspectInfo {
  lat: number;
  lng: number;
  elevation: number;
  worldX: number;
  worldZ: number;
}

export interface ViewSettings {
  elevExaggeration: number;
  smoothingPasses: number;
  showSatellite: boolean;
  sunAzimuth: number;
}
