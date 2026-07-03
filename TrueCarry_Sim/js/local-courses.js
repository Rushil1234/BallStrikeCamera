import { HOLES } from './holes.js?v=gspro-1';
import { PEBBLE_PRIVATE_HOLES, PEBBLE_PRIVATE_WORLD } from './pebble-private.js?v=gspro-1';
import { PEBBLE_OSM_BY_HOLE, PEBBLE_OSM_WORLD } from './pebble-osm.js?v=gspro-1';
import { PEBBLE_ELEVATION } from './pebble-elevation.js?v=gspro-1';
import { PEBBLE_WORLD_REALISM } from './pebble-world-data.js?v=gspro-1';
import { AUGUSTA_PRIVATE_HOLES, AUGUSTA_PRIVATE_WORLD } from './augusta-private.js?v=gspro-1';
import { AUGUSTA_OSM_BY_HOLE } from './augusta-osm.js?v=gspro-1';
import { AUGUSTA_ELEVATION } from './augusta-elevation.js?v=gspro-1';
import { AUGUSTA_WORLD_REALISM } from './augusta-world-data.js?v=gspro-1';

const PEBBLE_HOLES_WITH_OSM = PEBBLE_PRIVATE_HOLES.map((hole) => ({
  ...hole,
  osm: PEBBLE_OSM_BY_HOLE[hole.id] || null,
}));

const AUGUSTA_HOLES_WITH_OSM = AUGUSTA_PRIVATE_HOLES.map((hole) => ({
  ...hole,
  osm: AUGUSTA_OSM_BY_HOLE[hole.id] || null,
}));

export const LOCAL_COURSES = [
  {
    courseId: 'pine-hollow',
    courseName: 'Pine Hollow National',
    sub: 'Built-in routed island course',
    holes: HOLES,
    world: { profile: 'island' },
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
    },
    local: true,
  },
];

export function getLocalCourse(courseId) {
  return LOCAL_COURSES.find((course) => course.courseId === courseId) || null;
}
