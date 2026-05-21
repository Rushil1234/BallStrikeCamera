"use client";

import { useEffect, useRef, useState, type ReactNode, type CSSProperties } from "react";

/** Fades + lifts children into view on scroll. Respects reduced-motion via CSS. */
export default function Reveal({
  children,
  delay = 0,
  as: Tag = "div",
  className = "",
  style,
}: {
  children: ReactNode;
  delay?: number;
  as?: "div" | "section" | "li" | "span";
  className?: string;
  style?: CSSProperties;
}) {
  const ref = useRef<HTMLElement | null>(null);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setShown(true);
          io.disconnect();
        }
      },
      { threshold: 0.15, rootMargin: "0px 0px -8% 0px" }
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);

  const Comp = Tag as "div";
  return (
    <Comp
      // @ts-expect-error ref polymorphism
      ref={ref}
      className={`reveal${shown ? " in" : ""} ${className}`}
      style={{ transitionDelay: `${delay}ms`, ...style }}
    >
      {children}
    </Comp>
  );
}
