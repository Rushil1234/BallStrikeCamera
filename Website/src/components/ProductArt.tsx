// Line-art product marks, drawn to match the store's existing aesthetic (gold
// on the forest gradient already supplied by .product-art). Deliberately not
// photography: stock/scraped product photos would be someone else's copyright
// on a commercial storefront. Swap any of these for a real photo by replacing
// the <svg> with an <Image> — the container sizing stays the same.

import type { JSX } from "react";

type Props = { kind: string };

const S = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.6,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

function NfcTag() {
  return (
    <svg viewBox="0 0 120 80" role="img" aria-label="NFC club tag">
      <rect x="20" y="16" width="46" height="48" rx="9" {...S} />
      <circle cx="43" cy="40" r="4.5" {...S} />
      {/* radiating NFC waves */}
      <path d="M78 26a20 20 0 0 1 0 28" {...S} opacity="0.9" />
      <path d="M88 20a30 30 0 0 1 0 40" {...S} opacity="0.6" />
      <path d="M98 14a40 40 0 0 1 0 52" {...S} opacity="0.35" />
      <path d="M43 27v5M43 48v5" {...S} opacity="0.7" />
    </svg>
  );
}

function FoamBalls() {
  const dimples = [
    [46, 32], [54, 30], [62, 33], [44, 40], [53, 39], [62, 41], [48, 48], [57, 47],
  ];
  return (
    <svg viewBox="0 0 120 80" role="img" aria-label="Foam practice balls">
      <circle cx="53" cy="40" r="22" {...S} />
      {dimples.map(([cx, cy], i) => (
        <circle key={i} cx={cx} cy={cy} r="2.1" {...S} strokeWidth={1.1} opacity="0.55" />
      ))}
      {/* two behind, suggesting a set */}
      <circle cx="86" cy="30" r="12" {...S} opacity="0.55" />
      <circle cx="92" cy="53" r="9" {...S} opacity="0.35" />
    </svg>
  );
}

function Tripod() {
  return (
    <svg viewBox="0 0 120 80" role="img" aria-label="True Carry tripod">
      {/* phone in landscape on the head */}
      <rect x="41" y="12" width="38" height="22" rx="3" {...S} />
      <circle cx="72" cy="23" r="2.4" {...S} strokeWidth={1.2} opacity="0.8" />
      {/* head + column */}
      <path d="M60 34v8" {...S} />
      <path d="M52 42h16" {...S} />
      {/* three legs */}
      <path d="M60 42 38 68M60 42l22 26M60 42v22" {...S} />
      <path d="M46 58h10" {...S} opacity="0.45" />
    </svg>
  );
}

function Polo() {
  return (
    <svg viewBox="0 0 120 80" role="img" aria-label="True Carry polo">
      {/* body + shoulders */}
      <path d="M44 20 32 27l5 11 6-3v29h34V35l6 3 5-11-12-7" {...S} />
      {/* collar */}
      <path d="M44 20l16 10 16-10" {...S} />
      <path d="M52 15h16" {...S} opacity="0.5" />
      {/* placket */}
      <path d="M60 30v12" {...S} opacity="0.8" />
      <circle cx="60" cy="35" r="1.2" {...S} strokeWidth={1.1} opacity="0.7" />
    </svg>
  );
}

function GiftCard() {
  return (
    <svg viewBox="0 0 120 80" role="img" aria-label="True Carry gift card">
      <rect x="30" y="22" width="60" height="38" rx="6" {...S} />
      {/* ribbon */}
      <path d="M60 22v38" {...S} opacity="0.8" />
      <path d="M30 36h60" {...S} opacity="0.8" />
      {/* bow */}
      <path d="M60 22c-6-6-14-4-12 2 1.6 4.6 8 3 12-2Z" {...S} strokeWidth={1.3} />
      <path d="M60 22c6-6 14-4 12 2-1.6 4.6-8 3-12-2Z" {...S} strokeWidth={1.3} />
    </svg>
  );
}

const MARKS: Record<string, () => JSX.Element> = {
  "nfc-tag": NfcTag,
  "foam-balls": FoamBalls,
  tripod: Tripod,
  polo: Polo,
  "gift-card": GiftCard,
};

export default function ProductArt({ kind }: Props) {
  const Mark = MARKS[kind];
  if (!Mark) return null;
  return (
    <div className="product-mark" aria-hidden={false}>
      <Mark />
    </div>
  );
}
