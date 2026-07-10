import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Courses — Augusta, St Andrews, Pebble & more",
  description:
    "Play famous courses in the True Carry simulator — St Andrews Old Course, Augusta National, and Pebble-style coastal links, built from real course and elevation data.",
  alternates: { canonical: "/course" },
  openGraph: {
    title: "True Carry Courses — real data, real elevation",
    description: "St Andrews, Augusta National, and coastal links — built from real course and terrain data.",
    url: "/course",
  },
};

export default function CourseLayout({ children }: { children: React.ReactNode }) {
  return children;
}
