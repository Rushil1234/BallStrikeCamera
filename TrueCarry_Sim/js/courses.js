// Loads sim courses from Supabase sim_courses table.
// Falls back gracefully to the built-in HOLES from holes.js if none found.

const SUPABASE_URL  = 'https://aoxturoezgecwceudeef.supabase.co';
const SUPABASE_ANON = 'sb_publishable_Qk0gdBkqnTb2PV2bEfW-3A_COWs5lOU';

/**
 * Fetches all courses from sim_courses.
 * Returns an array of { courseId, courseName, holes, latitude, longitude }.
 * Empty array if the table doesn't exist or is empty.
 */
export async function fetchSimCourses() {
  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/sim_courses?select=course_id,course_name,holes_json,latitude,longitude&order=course_name.asc`,
      {
        headers: {
          'apikey':        SUPABASE_ANON,
          'Authorization': `Bearer ${SUPABASE_ANON}`,
          'Accept':        'application/json',
        },
      }
    );
    if (!res.ok) return [];
    const rows = await res.json();
    return (rows || []).map(r => ({
      courseId:   r.course_id,
      courseName: r.course_name,
      holes:      r.holes_json || [],
      latitude:   r.latitude,
      longitude:  r.longitude,
    })).filter(c => c.holes.length > 0);
  } catch {
    return [];
  }
}
