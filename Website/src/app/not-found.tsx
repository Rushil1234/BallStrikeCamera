import Link from "next/link";

/* Branded 404 — the default Next.js white page looked like a different site. */
export default function NotFound() {
  return (
    <div
      style={{
        minHeight: "100vh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: 18,
        background: "radial-gradient(ellipse at 50% 40%, #16241a 0%, #0a120d 70%)",
        textAlign: "center",
        padding: 24,
      }}
    >
      <div style={{ fontFamily: "Georgia, serif", fontSize: 30, letterSpacing: "0.08em", color: "#ece4d2" }}>
        True <i style={{ color: "#c9a86a" }}>Carry.</i>
      </div>
      <div style={{ fontSize: 12, letterSpacing: "0.32em", color: "#8fa08a", textTransform: "uppercase" }}>
        Out of bounds
      </div>
      <p style={{ color: "#b9c4b2", fontSize: 15, maxWidth: 380, margin: 0 }}>
        This page doesn&apos;t exist. Take a drop and head back to the clubhouse.
      </p>
      <Link
        href="/"
        style={{
          marginTop: 8,
          padding: "10px 26px",
          border: "1px solid #c9a86a",
          borderRadius: 999,
          color: "#ece4d2",
          fontSize: 13,
          letterSpacing: "0.12em",
          textTransform: "uppercase",
          textDecoration: "none",
        }}
      >
        Back to the clubhouse
      </Link>
    </div>
  );
}
