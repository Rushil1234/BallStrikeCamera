# Terrain Building Experiment

Browser-based 3D terrain generation from real-world coordinates.
Enter a lat/lng, click Generate, and explore a photorealistic terrain mesh in 30 seconds.

## Quick Start

```bash
cd "Terrain Building Experiment"
npm install
npm run dev
# → http://localhost:5174
```

---

## Architecture

```
src/
├── pages/TerrainExperiment.tsx   — main page, orchestrates all state
├── components/
│   ├── TerrainViewer.tsx         — React Three Fiber canvas + terrain mesh
│   ├── TerrainControls.tsx       — left panel UI (inputs, sliders, inspector)
│   └── CameraController.tsx      — OrbitControls wrapper with auto-position
├── services/
│   ├── ElevationService.ts       — fetch + decode AWS Terrarium tiles
│   ├── SatelliteService.ts       — fetch + stitch ESRI World Imagery tiles
│   └── TerrainBuilder.ts         — build THREE.BufferGeometry from heightmap
└── utils/
    ├── CoordinateUtils.ts         — lat/lng ↔ tile ↔ world coordinate math
    └── TerrainMath.ts             — heightmap smoothing, stats
```

---

## Data Sources

### Elevation: AWS Terrain Tiles (Terrarium format)
- **URL**: `https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png`
- **Format**: RGB PNG where `elevation = R*256 + G + B/256 - 32768` (metres)
- **Resolution**: ~2–10m/pixel depending on zoom (auto-selected)
- **Cost**: Free, no API key, CORS enabled
- **Coverage**: Global

### Satellite: ESRI World Imagery
- **URL**: `https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}`
- **Resolution**: Sub-metre at zoom 17–18 for most regions
- **Cost**: Free, no API key, CORS enabled
- **Coverage**: Global, ~0.5m/pixel in populated areas

---

## Coordinate System

```
World origin (0, 0, 0) = center of terrain area (input lat/lng)
x = east-west metres (east = positive)
y = elevation above terrain minimum (metres, optionally exaggerated)
z = north-south metres (north = positive)

1 unit = 1 real-world metre
```

UV mapping:
```
U = 0 (west edge) → 1 (east edge)
V = 1 (north edge) → 0 (south edge)   ← Three.js flipY=true convention
```

---

## ElevationProvider Interface

To swap elevation sources, implement:

```typescript
interface ElevationProvider {
  fetchElevationGrid(
    centerLat: number,
    centerLng: number,
    widthMeters: number,
    heightMeters: number,
    resolution: number,
    onProgress?: (msg: string) => void
  ): Promise<ElevationGrid>;
}

interface ElevationGrid {
  heightmap: number[][];   // [row][col], row 0 = northernmost
  minElevation: number;
  maxElevation: number;
  rows: number;
  cols: number;
}
```

**Alternative providers**: Mapbox Terrain-RGB (`mapbox.terrain-rgb`), USGS 3DEP WCS, OpenTopography API.

---

## SatelliteProvider Interface

```typescript
interface SatelliteProvider {
  fetchSatelliteTexture(
    centerLat: number,
    centerLng: number,
    widthMeters: number,
    heightMeters: number,
    onProgress?: (msg: string) => void
  ): Promise<THREE.CanvasTexture>;
}
```

**Alternative providers**: Mapbox Satellite (API key required), Google Maps Static API (API key required).

---

## Performance Notes

| Resolution | Vertices | Build time | Tile fetches (1200m) |
|-----------|----------|------------|----------------------|
| 128×128   | 16,384   | <20ms      | ~4 elev + ~25 sat   |
| 256×256   | 65,536   | ~50ms      | ~4 elev + ~25 sat   |
| 512×512   | 262,144  | ~200ms     | ~4 elev + ~25 sat   |

- Tile fetches are fully parallel (Promise.all)
- Total load time: 5–20 seconds depending on network
- Satellite tile count depends on area size (zoom auto-selected for ~5 tiles across)
- Geometry rebuilds instantly when adjusting smoothing/exaggeration (no re-fetch)

---

## Recommended Next Steps for Golf Course Mapping

1. **Overlay course geometry**: Parse `pinchbrook.json` hole/fairway/green polygons, project into world XZ, render as wireframe overlays to verify alignment with terrain.

2. **Per-vertex surface classification**: Run pip() (point-in-polygon) at each terrain vertex against OSM polygons — same approach as the CourseBuilder pipeline.

3. **Heightmap refinement**: At 512×512 with zoom-15 elevation tiles, you get ~3m resolution — enough to see cart path crowning and green undulation. Zoom-16 tiles would give ~1.5m.

4. **Web Worker offload**: Move heightmap sampling + geometry building to a Web Worker for non-blocking 512×512 generation.

5. **Texture atlas**: For large areas (>3km), switch from a single stitched canvas to a texture atlas with multiple draw calls per terrain chunk.
