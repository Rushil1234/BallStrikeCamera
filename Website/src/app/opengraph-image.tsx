import { ImageResponse } from "next/og";

// Dynamic social-share card (1200×630). Rendered once at build; used for
// Open Graph + Twitter previews across the site.
export const runtime = "edge";
export const alt = "True Carry — the camera launch monitor";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OGImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: "80px",
          background:
            "radial-gradient(ellipse at 30% 20%, #1c3322 0%, #0c130d 60%)",
          color: "#ece4d2",
          fontFamily: "Georgia, serif",
        }}
      >
        <div style={{ fontSize: 34, letterSpacing: 4, color: "#c9a86a", textTransform: "uppercase", marginBottom: 12 }}>
          The Camera Launch Monitor
        </div>
        <div style={{ display: "flex", fontSize: 96, fontWeight: 700, lineHeight: 1.02, marginBottom: 24 }}>
          <span>True&nbsp;</span>
          <span style={{ color: "#c9a86a", fontStyle: "italic" }}>Carry.</span>
        </div>
        <div style={{ fontSize: 40, color: "rgba(236,228,210,0.82)", maxWidth: 820, lineHeight: 1.25 }}>
          Tour-grade ball speed, launch, and carry — from the iPhone in your pocket. No extra hardware.
        </div>
        <div style={{ marginTop: 40, fontSize: 30, color: "rgba(236,228,210,0.55)", fontFamily: "monospace" }}>
          truecarry.golf
        </div>
      </div>
    ),
    { ...size }
  );
}
