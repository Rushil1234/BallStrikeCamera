import { HOLES } from './holes.js?v=pebble-visual-1';
import { PEBBLE_PRIVATE_HOLES, PEBBLE_PRIVATE_WORLD } from './pebble-private.js?v=pebble-visual-1';
import { PEBBLE_OSM_BY_HOLE, PEBBLE_OSM_WORLD } from './pebble-osm.js?v=pebble-visual-1';

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
    courseName: 'Pebble Private Prototype',
    sub: 'Local-only coastal research course · BlueGolf centerlines + OSM polygons',
    holes: PEBBLE_HOLES_WITH_OSM,
    world: { profile: 'coastal', ...PEBBLE_PRIVATE_WORLD, ...PEBBLE_OSM_WORLD },
    local: true,
    private: true,
  },
];

export function getLocalCourse(courseId) {
  return LOCAL_COURSES.find((course) => course.courseId === courseId) || null;
}
