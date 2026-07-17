import { HOLES } from './holes.js?v=gspro-21';
import { PEBBLE_PRIVATE_HOLES, PEBBLE_PRIVATE_WORLD } from './pebble-private.js?v=gspro-21';
import { PEBBLE_OSM_BY_HOLE, PEBBLE_OSM_WORLD } from './pebble-osm.js?v=gspro-21';
import { PEBBLE_ELEVATION } from './pebble-elevation.js?v=gspro-21';
import { PEBBLE_WORLD_REALISM } from './pebble-world-data.js?v=gspro-21';
import { AUGUSTA_PRIVATE_HOLES, AUGUSTA_PRIVATE_WORLD } from './augusta-private.js?v=gspro-21';
import { AUGUSTA_OSM_BY_HOLE } from './augusta-osm.js?v=gspro-21';
import { AUGUSTA_ELEVATION } from './augusta-elevation.js?v=gspro-21';
import { AUGUSTA_WORLD_REALISM } from './augusta-world-data.js?v=gspro-21';
import { AUGUSTA_TREES } from './augusta-trees.js?v=gspro-21';
import { STANDREWS_PRIVATE_HOLES, STANDREWS_PRIVATE_WORLD } from './standrews-private.js?v=gspro-21';
import { STANDREWS_OSM_BY_HOLE } from './standrews-osm.js?v=gspro-21';
import { STANDREWS_ELEVATION } from './standrews-elevation.js?v=gspro-21';
import { STANDREWS_WORLD_REALISM } from './standrews-world-data.js?v=gspro-21';

const PEBBLE_HOLES_WITH_OSM = PEBBLE_PRIVATE_HOLES.map((hole) => ({
  ...hole,
  osm: PEBBLE_OSM_BY_HOLE[hole.id] || null,
}));

const AUGUSTA_HOLES_WITH_OSM = AUGUSTA_PRIVATE_HOLES.map((hole) => ({
  ...hole,
  osm: AUGUSTA_OSM_BY_HOLE[hole.id] || null,
}));

const STANDREWS_HOLES_WITH_OSM = STANDREWS_PRIVATE_HOLES.map((hole) => ({
  ...hole,
  osm: STANDREWS_OSM_BY_HOLE[hole.id] || null,
}));

export const LOCAL_COURSES = [
  {
    courseId: 'pine-hollow',
    courseName: 'Pine Hollow National',
    sub: 'Built-in routed island course',
    holes: HOLES,
    world: {
      profile: 'island',
      // Carolina parkland setup: mixed pine/hardwood corridors, deeper
      // greens-and-olive palette (the pale defaults bloomed to milk).
      conditions: { stimp: 10, firmness: 0.95, gustiness: 0.2 },
      visualZones: {
        roughColor: 0x55693c,
        deepColor: 0x475a33,
        sandColor: 0xe2d7b8,
        forest: { pineShare: 0.55, scaleMin: 0.8, scaleRange: 0.5 },
      },
    },
    local: true,
  },
  {
    courseId: 'pebble-private',
    courseName: 'Cypress Coast Links',
    sub: 'Coastal links course · OSM surfaces + USGS terrain',
    holes: PEBBLE_HOLES_WITH_OSM,
    world: {
      profile: 'coastal',
      ...PEBBLE_PRIVATE_WORLD,
      ...PEBBLE_OSM_WORLD,
      ...PEBBLE_WORLD_REALISM,
      elevation: PEBBLE_ELEVATION,
      // Monterey golden hour: dry coastal scrub beyond the corridors, low
      // dune mounding, richer turf tones over the generated zones.
      visualZones: {
        ...(PEBBLE_WORLD_REALISM.visualZones || {}),
        roughColor: 0x5d7040,
        deepColor: 0x4b5b36,
        sandColor: 0xe6ddc4,
        dunes: { amp: 0.9, freq: 0.028 },
        forestFloor: { color: 0xa89a6e, start: 16 },
      },
    },
    local: true,
  },
  {
    courseId: 'augusta-national',
    courseName: 'Augusta National',
    sub: 'Georgia parkland classic · OSM surfaces + USGS terrain',
    holes: AUGUSTA_HOLES_WITH_OSM,
    world: {
      ...AUGUSTA_PRIVATE_WORLD,
      ...AUGUSTA_WORLD_REALISM,
      elevation: AUGUSTA_ELEVATION,
      // Augusta's signature look: hyper-vibrant emerald turf, a lush (never
      // brown) second cut, and the club's brilliant white sand.
      visualZones: {
        ...(AUGUSTA_WORLD_REALISM.visualZones || {}),
        fairA: 0x69bb3e, fairB: 0x4c9330,
        firstCut: 0x5aa53c, fringe: 0x57a03a,
        greenA: 0x77c452, greenB: 0x6cb847, teeColor: 0x69b449,
        roughColor: 0x46812d, deepColor: 0x396c26,
        sandColor: 0xf3eede,
        waterColor: 0x123a2b,
        // Real treelines: ~25k tree positions + canopy heights measured from
        // USGS 3DEP LiDAR (public domain) — the actual trees, not a scatter.
        realTrees: AUGUSTA_TREES,
        // Amen Corner's stone bridges over Rae's Creek — Augusta's most
        // recognisable furniture. Each renders only on the holes it sits in.
        bridges: [
          { x: 54.59, z: -508, rot: Math.PI / 2, span: 13 }, // Hogan Bridge — 12th green
          { x: -150, z: -240, rot: -0.9, span: 9 },          // Nelson Bridge — 13th
        ],
        // Members' green tee markers.
        teeMarkColor: 0x2f6b3a,
        // Clean white gallery rope-and-post line down the corridors instead of
        // the links OB stakes.
        galleryFence: true,
        // Tiered spectator grandstands set behind a few greens — Augusta's
        // amphitheatre cue. Each renders only on the hole it sits inside.
        // rot = atan2(approachDirX, approachDirZ) so the seating faces the green.
        grandstands: [
          { x: 321, z: 317, rot: 0.60, w: 34, tiers: 8 },   // behind 18th green (HOLLY)
          { x: -271, z: 63, rot: -0.44, w: 44, tiers: 9 },  // 16th amphitheatre (REDBUD)
          { x: -202, z: -33, rot: -1.28, w: 30, tiers: 7 }, // behind 15th green (FIRETHORN)
        ],
      },
    },
    local: true,
  },
  {
    courseId: 'standrews-old',
    courseName: 'St Andrews Old Course',
    sub: 'The Home of Golf · links · OSM + EU-DEM terrain',
    holes: STANDREWS_HOLES_WITH_OSM,
    world: {
      ...STANDREWS_PRIVATE_WORLD,
      ...STANDREWS_WORLD_REALISM,
      elevation: STANDREWS_ELEVATION,
    },
    local: true,
  },
];

export function getLocalCourse(courseId) {
  return LOCAL_COURSES.find((course) => course.courseId === courseId) || null;
}
