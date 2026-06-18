import { HOLES } from './holes.js?v=range-upgrade-1';
import { PEBBLE_PRIVATE_HOLES, PEBBLE_PRIVATE_WORLD } from './pebble-private.js?v=range-upgrade-1';
import { PEBBLE_OSM_BY_HOLE, PEBBLE_OSM_WORLD } from './pebble-osm.js?v=range-upgrade-1';
import { PEBBLE_ELEVATION } from './pebble-elevation.js?v=range-upgrade-1';
import { PEBBLE_WORLD_REALISM } from './pebble-world-data.js?v=range-upgrade-1';

const PEBBLE_HOLES_WITH_OSM = PEBBLE_PRIVATE_HOLES.map((hole) => ({
  ...hole,
  osm: PEBBLE_OSM_BY_HOLE[hole.id] || null,
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
];

export function getLocalCourse(courseId) {
  return LOCAL_COURSES.find((course) => course.courseId === courseId) || null;
}
