import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Watch a live round",
  description:
    "Spectate a live True Carry simulator round in your browser — every shot, distance, and score as it happens. Enter a session code to start watching.",
  alternates: { canonical: "/watch" },
  openGraph: {
    title: "Watch a live True Carry round",
    description: "Follow every shot and score of a live sim round, live in your browser.",
    url: "/watch",
  },
};

export default function WatchLayout({ children }: { children: React.ReactNode }) {
  return children;
}
