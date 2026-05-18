import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "True Carry — Golf Launch Monitor",
  description: "Camera-based launch monitor for golfers. Track every shot, know every yard.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
