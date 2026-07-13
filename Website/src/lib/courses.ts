/**
 * The one source of truth for playable sim courses, shared by /play and
 * /course so course lists never drift. `id` must match the sim bundle's
 * courseId (public/sim/js/local-courses.js).
 */
export type SimCourse = {
  id: string;
  name: string;
  sub: string;
  detail: string;
  meta: string;
  mark: string;
  hrefMode: "range" | "course";
  holes: number;
  par: number;
  location: string;
  preview: string;
  disabled?: boolean;
};

export const SIM_COURSES: SimCourse[] = [
  {
    id: "range",
    name: "Range",
    sub: "Free practice · no scoring",
    detail: "Target greens, dispersion feedback, carry windows, and club gapping without starting a round.",
    meta: "Practice",
    mark: "R",
    hrefMode: "range",
    holes: 0,
    par: 0,
    location: "True Carry built-in",
    preview: "/sim-preview.jpg",
  },
  {
    id: "pine-hollow",
    name: "Pine Hollow National",
    sub: "18 holes · par 72 · 6,900 yd",
    detail: "The built-in parkland course with the current scoring, map, hole picker, and full round flow.",
    meta: "Classic",
    mark: "18",
    hrefMode: "course",
    holes: 18,
    par: 72,
    location: "True Carry built-in",
    preview: "/pine-hollow-preview.jpg",
  },
  {
    id: "pebble-private",
    name: "Cypress Coast Links",
    sub: "18 holes · coastal links · par 72",
    detail: "A rugged Pacific-style routing with ocean edges, cliffside holes, cypress belts, and coastal wind visuals.",
    meta: "Coastal",
    mark: "CC",
    hrefMode: "course",
    holes: 18,
    par: 72,
    location: "Coastal links",
    preview: "/pebble-preview.jpg",
  },
  {
    id: "standrews-old",
    name: "St Andrews Old Course",
    sub: "18 holes · par 72 · 7,297 yd",
    detail: "The Home of Golf, shared double greens, the Swilcan Burn, Hell Bunker, and the Road Hole, built from real links data with EU-DEM terrain.",
    meta: "New course",
    mark: "SA",
    hrefMode: "course",
    holes: 18,
    par: 72,
    location: "Scottish links",
    preview: "/standrews-preview.jpg",
  },
  {
    id: "augusta-national",
    name: "Augusta National",
    sub: "18 holes · par 72 · 7,555 yd",
    detail: "The Georgia parkland major venue, towering pines, azaleas, white sand, and Rae's Creek, built from real course data with USGS terrain.",
    meta: "Major venue",
    mark: "A",
    hrefMode: "course",
    holes: 18,
    par: 72,
    location: "Georgia parkland",
    preview: "/augusta-preview.jpg",
  },
];

export function simCoursePath(course: SimCourse): string {
  return course.hrefMode === "range"
    ? "/sim/index.html?mode=range"
    : `/sim/index.html?mode=course&course=${course.id}`;
}
