"use client";

import { useEffect, useState } from "react";

type Theme = "dark" | "light";

function preferredTheme(): Theme {
  if (typeof window === "undefined") return "dark";
  const saved = window.localStorage.getItem("truecarry-theme");
  if (saved === "light" || saved === "dark") return saved;
  return window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
}

export default function ThemeToggle() {
  const [theme, setTheme] = useState<Theme>("dark");

  useEffect(() => {
    const nextTheme = preferredTheme();
    setTheme(nextTheme);
    document.documentElement.dataset.theme = nextTheme;
  }, []);

  function toggleTheme() {
    const nextTheme = theme === "dark" ? "light" : "dark";
    setTheme(nextTheme);
    document.documentElement.dataset.theme = nextTheme;
    window.localStorage.setItem("truecarry-theme", nextTheme);
  }

  return (
    <button
      type="button"
      className="theme-toggle"
      onClick={toggleTheme}
      aria-label={`Switch to ${theme === "dark" ? "light" : "dark"} mode`}
      title={`Switch to ${theme === "dark" ? "light" : "dark"} mode`}
    >
      <span aria-hidden>{theme === "dark" ? "Light" : "Dark"}</span>
    </button>
  );
}
