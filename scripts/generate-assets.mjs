import fs from "node:fs";
import path from "node:path";

const outDir = path.resolve("assets");
fs.mkdirSync(outDir, { recursive: true });

const svg = (name, width, height, body) => {
  const file = path.join(outDir, name);
  fs.writeFileSync(
    file,
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${body}</svg>\n`,
    "utf8"
  );
};

svg(
  "park-bg.svg",
  1600,
  1000,
  `
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#243f32"/>
      <stop offset=".58" stop-color="#16271d"/>
      <stop offset="1" stop-color="#101713"/>
    </linearGradient>
    <filter id="noise">
      <feTurbulence baseFrequency=".012" numOctaves="3" seed="8"/>
      <feColorMatrix type="saturate" values=".35"/>
      <feBlend mode="multiply" in2="SourceGraphic"/>
    </filter>
  </defs>
  <rect width="1600" height="1000" fill="url(#sky)"/>
  <g filter="url(#noise)" opacity=".62">
    <rect width="1600" height="1000" fill="#29442c"/>
  </g>
  <path d="M0 760 C240 660 350 800 565 690 C820 560 980 750 1200 640 C1390 548 1510 610 1600 560 L1600 1000 L0 1000Z" fill="#0e1c15" opacity=".85"/>
  <path d="M0 565 C260 460 450 620 690 520 C940 415 1120 510 1600 390" fill="none" stroke="#365b3b" stroke-width="58" opacity=".5"/>
  <circle cx="1260" cy="210" r="90" fill="#d7a64c" opacity=".22"/>
  <g opacity=".45" fill="#101713">
    ${Array.from({ length: 90 }, (_, i) => {
      const x = (i * 197) % 1600;
      const y = 400 + ((i * 83) % 550);
      const h = 70 + ((i * 31) % 130);
      return `<path d="M${x} ${y} l${20 + (i % 5) * 6} ${h} h-${42 + (i % 5) * 8}z"/>`;
    }).join("")}
  </g>`
);

svg(
  "ranger.svg",
  128,
  128,
  `
  <rect width="128" height="128" rx="18" fill="#21342a"/>
  <ellipse cx="64" cy="78" rx="36" ry="42" fill="#7f6a45"/>
  <path d="M31 58 C44 34 82 28 98 56 L91 63 C78 54 52 54 38 64Z" fill="#38452a"/>
  <circle cx="50" cy="66" r="6" fill="#16140f"/>
  <circle cx="78" cy="66" r="6" fill="#16140f"/>
  <path d="M47 90 C58 100 73 99 83 90" fill="none" stroke="#2a170f" stroke-width="5" stroke-linecap="round"/>
  <path d="M35 101 C50 88 78 88 94 101 L102 128 H26Z" fill="#b28b48"/>
  <path d="M48 104 H80 L74 128 H54Z" fill="#263826"/>
  <path d="M23 43 H105 L94 31 H38Z" fill="#4b5e35"/>
  <circle cx="64" cy="43" r="9" fill="#d6b153"/>
  `
);

svg(
  "raptor.svg",
  128,
  128,
  `
  <ellipse cx="63" cy="67" rx="42" ry="22" fill="#60764e"/>
  <path d="M83 58 C105 43 120 44 124 57 C111 58 103 66 91 73Z" fill="#6f8758"/>
  <path d="M25 68 C9 61 2 51 5 42 C21 48 33 52 43 58Z" fill="#536847"/>
  <path d="M51 82 L43 114 H34 L42 79Z" fill="#4a5f40"/>
  <path d="M75 82 L88 115 H78 L65 81Z" fill="#4a5f40"/>
  <path d="M102 58 L116 49 M102 64 L119 66" stroke="#e8dfc4" stroke-width="3" stroke-linecap="round"/>
  <circle cx="108" cy="54" r="4" fill="#f1d35e"/>
  <path d="M34 54 C52 41 76 42 96 55" fill="none" stroke="#26381f" stroke-width="5" opacity=".45"/>
  <path d="M44 48 l8 -13 l8 14 l8 -13 l9 15" fill="none" stroke="#465c3c" stroke-width="4" stroke-linejoin="round"/>
  `
);

svg(
  "trex.svg",
  160,
  160,
  `
  <ellipse cx="77" cy="86" rx="49" ry="31" fill="#7b6846"/>
  <path d="M95 69 C132 43 154 48 158 74 C140 73 128 84 107 94Z" fill="#8e7b54"/>
  <path d="M34 89 C7 83 -4 68 4 51 C24 60 41 64 56 72Z" fill="#66583d"/>
  <path d="M58 108 L48 151 H35 L45 103Z" fill="#5d4e36"/>
  <path d="M92 108 L113 151 H99 L78 104Z" fill="#5d4e36"/>
  <path d="M125 70 L151 59 M125 80 L153 82" stroke="#f2e9ce" stroke-width="5" stroke-linecap="round"/>
  <circle cx="136" cy="65" r="5" fill="#f5d96a"/>
  <path d="M38 72 C62 51 94 51 121 68" fill="none" stroke="#473a29" stroke-width="7" opacity=".5"/>
  <path d="M49 64 l10 -18 l12 20 l12 -18 l12 20 l12 -17" fill="none" stroke="#5b4b33" stroke-width="5" stroke-linejoin="round"/>
  `
);

svg(
  "turret.svg",
  96,
  96,
  `
  <circle cx="48" cy="56" r="28" fill="#4d5f5e"/>
  <circle cx="48" cy="56" r="20" fill="#71817b"/>
  <rect x="44" y="10" width="10" height="42" rx="4" fill="#272d2e"/>
  <rect x="38" y="5" width="22" height="14" rx="5" fill="#a4ada8"/>
  <path d="M23 78 H73 L84 94 H12Z" fill="#2a3330"/>
  <circle cx="48" cy="56" r="6" fill="#e4b55f"/>
  `
);

svg(
  "fence.svg",
  96,
  96,
  `
  <rect x="18" y="16" width="9" height="68" rx="3" fill="#69756c"/>
  <rect x="69" y="16" width="9" height="68" rx="3" fill="#69756c"/>
  <path d="M20 29 H76 M20 48 H76 M20 67 H76" stroke="#a9b3a9" stroke-width="6" stroke-linecap="round"/>
  <path d="M25 24 L71 72 M71 24 L25 72" stroke="#4c574e" stroke-width="5"/>
  <path d="M31 42 l8 -9 l8 9 l8 -9 l8 9" fill="none" stroke="#e7d567" stroke-width="3"/>
  `
);

svg(
  "trap.svg",
  96,
  96,
  `
  <circle cx="48" cy="48" r="31" fill="#2b3c41"/>
  <circle cx="48" cy="48" r="23" fill="#507078"/>
  <path d="M22 48 H74 M48 22 V74" stroke="#9ed8df" stroke-width="5"/>
  <path d="M32 32 L64 64 M64 32 L32 64" stroke="#162226" stroke-width="5"/>
  <circle cx="48" cy="48" r="8" fill="#e4b55f"/>
  `
);

svg(
  "generator.svg",
  128,
  128,
  `
  <rect x="22" y="38" width="84" height="58" rx="10" fill="#52615d"/>
  <rect x="32" y="48" width="38" height="22" rx="4" fill="#1e2a2c"/>
  <circle cx="88" cy="59" r="10" fill="#e4b55f"/>
  <path d="M55 48 L43 68 H58 L48 88 L78 58 H62 L72 48Z" fill="#71d5ff"/>
  <path d="M30 96 H98 L108 112 H20Z" fill="#27322f"/>
  <path d="M104 54 C118 51 121 77 106 75" fill="none" stroke="#2e3936" stroke-width="8" stroke-linecap="round"/>
  `
);

svg(
  "visitor-center.svg",
  180,
  180,
  `
  <ellipse cx="90" cy="133" rx="70" ry="23" fill="#111813" opacity=".45"/>
  <path d="M30 84 L90 36 L150 84 V136 H30Z" fill="#7d5e39"/>
  <path d="M18 89 L90 28 L162 89 L151 99 L90 49 L29 99Z" fill="#b47b3e"/>
  <rect x="47" y="92" width="28" height="44" fill="#1d2b2e"/>
  <rect x="105" y="92" width="28" height="44" fill="#1d2b2e"/>
  <rect x="79" y="93" width="23" height="43" fill="#3e2e1d"/>
  <circle cx="90" cy="70" r="17" fill="#d7b75c"/>
  <text x="90" y="76" font-size="17" font-family="Arial, sans-serif" font-weight="900" text-anchor="middle" fill="#352016">JP</text>
  <path d="M31 136 H149" stroke="#e1c07a" stroke-width="5"/>
  `
);

svg(
  "tree.svg",
  96,
  96,
  `
  <rect x="42" y="52" width="13" height="36" rx="5" fill="#694a2f"/>
  <circle cx="35" cy="48" r="22" fill="#315b36"/>
  <circle cx="56" cy="39" r="28" fill="#3e7541"/>
  <circle cx="63" cy="60" r="20" fill="#2f6136"/>
  <circle cx="39" cy="66" r="18" fill="#477e45"/>
  `
);

svg(
  "crate.svg",
  96,
  96,
  `
  <rect x="22" y="24" width="52" height="50" rx="5" fill="#8b6a3b"/>
  <path d="M22 38 H74 M22 59 H74 M37 24 V74 M59 24 V74" stroke="#4f3a23" stroke-width="5"/>
  <path d="M28 30 L68 69 M68 30 L28 69" stroke="#b89458" stroke-width="4"/>
  `
);
