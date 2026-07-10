import { HOLES } from './holes.js?v=gspro-13';
import { PEBBLE_PRIVATE_HOLES, PEBBLE_PRIVATE_WORLD } from './pebble-private.js?v=gspro-13';
import { PEBBLE_OSM_BY_HOLE, PEBBLE_OSM_WORLD } from './pebble-osm.js?v=gspro-13';
import { PEBBLE_ELEVATION } from './pebble-elevation.js?v=gspro-13';
import { PEBBLE_WORLD_REALISM } from './pebble-world-data.js?v=gspro-13';
import { AUGUSTA_PRIVATE_HOLES, AUGUSTA_PRIVATE_WORLD } from './augusta-private.js?v=gspro-13';
import { AUGUSTA_OSM_BY_HOLE } from './augusta-osm.js?v=gspro-13';
import { AUGUSTA_ELEVATION } from './augusta-elevation.js?v=gspro-13';
import { AUGUSTA_WORLD_REALISM } from './augusta-world-data.js?v=gspro-13';
import { STANDREWS_PRIVATE_HOLES, STANDREWS_PRIVATE_WORLD } from './standrews-private.js?v=gspro-13';
import { STANDREWS_OSM_BY_HOLE } from './standrews-osm.js?v=gspro-13';
import { STANDREWS_ELEVATION } from './standrews-elevation.js?v=gspro-13';
import { STANDREWS_WORLD_REALISM } from './standrews-world-data.js?v=gspro-13';

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
        fairA: 0x63b23c, fairB: 0x54a033,
        firstCut: 0x5aa53c, fringe: 0x57a03a,
        greenA: 0x77c452, greenB: 0x6cb847, teeColor: 0x69b449,
        roughColor: 0x46812d, deepColor: 0x396c26,
        sandColor: 0xf3eede,
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
