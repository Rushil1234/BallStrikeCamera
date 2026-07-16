"use client";

import { useState } from "react";

export default function CopyCommand({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch {
      /* clipboard blocked, user can still select the text */
    }
  }

  return (
    <button
      onClick={copy}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 12,
        width: "100%",
        textAlign: "left",
        backgroundColor: "rgba(0,0,0,0.28)",
        border: "1px solid rgba(255,255,255,0.12)",
        borderRadius: 12,
        padding: "14px 16px",
        cursor: "pointer",
        fontFamily: "var(--font-mono), monospace",
      }}
    >
      <code
        style={{
          flex: 1,
          fontSize: 13,
          color: "var(--cream)",
          overflowX: "auto",
          whiteSpace: "nowrap",
        }}
      >
        {command}
      </code>
      <span
        style={{
          flexShrink: 0,
          fontSize: 12,
          fontWeight: 700,
          color: copied ? "#3FB68B" : "var(--gold-bright)",
          fontFamily: "var(--font-sans), sans-serif",
        }}
      >
        {copied ? "Copied ✓" : "Copy"}
      </span>
    </button>
  );
}
