/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * Adapted from savvy-progress in johnnyvizz/claude-kit (MIT License; see
 * LICENSE-THIRD-PARTY) with James Nguyen's custom chibi mascots (MASCOTS).
 */

import { atom, read, update } from "claude-code";
import type { EngineInterface, Register } from "claude-code";

import type {
  BurnDown,
  Flow,
  FlowEvent,
  Panel,
  Phase,
  PlanTaskInput,
  Run,
  SpendSummary,
  TaskBoardRow,
  TaskState,
  Tier,
} from "../types";
import {
  burnDown,
  initialFlow,
  reduce,
  remaining,
  runCost,
  spend,
  taskBoard,
} from "./lib/orchestrator-core.mjs";

const PLUGIN = "vitruvian-orchestrator";
const PANE = "vitruvian-orchestrator";
const PANE_TITLE = "Orchestrator";
const TOOL = "mcp__vitruvian-orchestrator__progress";
const STEP_TOOL = "mcp__vitruvian-orchestrator__step";
const PHASES: readonly Phase[] = [
  "plan",
  "design",
  "delegate",
  "review",
  "close",
];
const TIERS: readonly Tier[] = ["lead", "core", "fast"];

const flow = atom(
  { plugin: "vitruvian-orchestrator", key: "flow" } as const,
  initialFlow(),
);
const panel = atom(
  { plugin: "vitruvian-orchestrator", key: "panel" } as const,
  {
    isCompact: false,
    autoOpenedFor: "",
  },
);
const now = atom({ plugin: "vitruvian-orchestrator", key: "now" } as const, 0);

type ProgressInput = {
  title?: string;
  phase?: Phase;
  tasks?: {
    title?: string;
    specialist?: string;
    tier?: Tier;
    after?: number[];
  }[];
  accept?: number;
  return?: number;
  finished?: boolean;
};

type StepInput = {
  done?: number;
  total?: number;
  note?: string;
};

// ---------------------------------------------------------------------------
// Status colours: accepted/done green, running blue, review/waiting amber,
// returned/error red, everything else neutral.

const GREEN = "#3B9C5F";
const BLUE = "#378ADD";
const AMBER = "#D99B26";
const RED = "#D0453F";
const NEUTRAL = "#888780";

const statusHex = (state: string): string => {
  if (state === "accepted" || state === "done") return GREEN;
  if (state === "running") return BLUE;
  if (state === "review" || state === "waiting") return AMBER;
  if (state === "returned" || state === "error") return RED;
  return NEUTRAL;
};

const statusTermColor = (
  state: string,
): "green" | "blue" | "yellow" | "red" | undefined => {
  if (state === "accepted" || state === "done") return "green";
  if (state === "running") return "blue";
  if (state === "review" || state === "waiting") return "yellow";
  if (state === "returned" || state === "error") return "red";
  return undefined;
};

const STATUS_GLYPH: Record<string, string> = {
  accepted: "✓",
  done: "✓",
  running: "●",
  review: "◈",
  waiting: "◷",
  returned: "↩",
  error: "✗",
  ready: "○",
};

// ---------------------------------------------------------------------------
// Formatting & helpers

const windowOf = (model: string): number =>
  /haiku/i.test(model) ? 200_000 : 1_000_000;

const fmtTokens = (n: number): string =>
  n >= 1e6
    ? `${(n / 1e6).toFixed(1)}M`
    : n >= 1e3
      ? `${Math.round(n / 1e3)}k`
      : `${Math.round(n)}`;

const fmtCost = (usd: number): string =>
  `$${usd < 10 ? usd.toFixed(2) : usd.toFixed(1)}`;

const fmtTime = (ms: number): string => {
  const s = Math.max(0, Math.round(ms / 1000));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = String(s % 60).padStart(2, "0");
  return h ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
};

const runTotalTokens = (r: Run): number =>
  (r.tokens.input || 0) +
  (r.tokens.output || 0) +
  (r.tokens.cacheRead || 0) +
  (r.tokens.cacheWrite || 0);

const runElapsed = (r: Run, at: number): number =>
  (r.endedAt ?? Math.max(at, r.startedAt)) - r.startedAt;

const SPARK = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"] as const;

const sparkline = (points: { remaining: number }[], maxVal: number): string => {
  if (points.length === 0) return "—";
  const hi = Math.max(1, maxVal, ...points.map((p) => p.remaining));
  return points
    .map((p) => {
      if (p.remaining <= 0) return "▁";
      const idx = Math.min(
        SPARK.length - 1,
        Math.max(1, Math.round((p.remaining / hi) * (SPARK.length - 1))),
      );
      return SPARK[idx];
    })
    .join("");
};

const barText = (ratioVal: number, width: number): string => {
  const clamped = Math.max(0, Math.min(1, ratioVal));
  const filled = Math.round(width * clamped);
  return "█".repeat(filled) + "░".repeat(Math.max(0, width - filled));
};

// ---------------------------------------------------------------------------
// SVG helpers, dithering & James's chibi mascots (adapted from savvy-progress)

const H = 22;
const BAR_H = 16;
const CRAB_W = 26;
const CELL = 3;
const FONT =
  "-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI',sans-serif";

const noise = (x: number, y: number): number => {
  const s = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453;
  return s - Math.floor(s);
};

const xml = (s: string): string =>
  s.replace(
    /[&<>"]/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c] ?? c,
  );

const charEm = (ch: string): number =>
  /[\s.,:;'|!il1()[\]]/.test(ch)
    ? 0.3
    : /[A-ZА-ЯЁmwшщжюМШЩЖЮ@%]/.test(ch)
      ? 0.72
      : 0.56;

const textWidth = (s: string, size: number): number =>
  [...s].reduce((w, ch) => w + charEm(ch) * size, 0);

const fitText = (s: string, size: number, maxW: number): string => {
  if (textWidth(s, size) <= maxW) return s;
  let out = "";
  for (const ch of s) {
    if (textWidth(out + ch + "…", size) > maxW) break;
    out += ch;
  }
  return out + "…";
};

const TIER_COLOR: Record<string, string> = {
  lead: "#BA7517",
  core: "#378ADD",
  fast: "#1D9E75",
  fable: "#7F77DD",
  heavy: "#D85A30",
  careful: "#BA7517",
  medium: "#378ADD",
  light: "#1D9E75",
  other: "#888780",
};

const PANE_CSS = `<style>
.t{fill:#1f1f1f}.s{fill:#6b6b68}.m{fill:#9a9a96}.k{fill:#ecebe8}.ln{stroke:#e4e4e1}.tile{fill:#f4f3f0}
@media (prefers-color-scheme: dark){.t{fill:#ececec}.s{fill:#a8a8a4}.m{fill:#7d7d79}.k{fill:#2c2c2b}.ln{stroke:#333331}.tile{fill:#262625}}
.live{animation:p 1.6s ease-in-out infinite}@keyframes p{50%{opacity:.3}}
@media (prefers-reduced-motion: reduce){.live{animation:none}}
</style>`;

const CLAY = "#D97757";
const INK = "#1F1E1D";
const STEEL = "#8E929A";
const DARK = "#3A3A3C";
const WHITE = "#F8F6F1";
const GOLD = "#F5C542";
const WOOD = "#7A4A26";
const SKIN = "#F6D3B3";
const NAVY = "#3A4466";
const CLOTH = "#D5DAE6";

type Fill = (
  x: number,
  y: number,
  w: number,
  h: number,
  c: string,
  cls?: string,
) => void;

const stamp = (
  f: Fill,
  x: number,
  y: number,
  rows: string[],
  map: Record<string, string>,
  cls?: string,
): void =>
  rows.forEach((row, dy) =>
    [...row].forEach(
      (ch, dx) => map[ch] && f(x + dx, y + dy, 1, 1, map[ch] ?? "", cls),
    ),
  );

const CRAB_CSS = `<style>
.run .la{animation:st .5s steps(1) infinite}.run .lb{animation:st .5s steps(1) infinite -.25s}
.run .bd{animation:bob .5s steps(1) infinite -.125s}
.run g{transform-box:fill-box}
@keyframes st{50%{transform:translateY(-1px)}}@keyframes bob{50%{transform:translateY(1px)}}
.c-fable.run{animation:float 1s ease-in-out infinite}
.c-fable.run .la,.c-fable.run .lb,.c-fable.run .bd{animation:none}
.c-fable.run .ant{animation:blink 1s steps(1) infinite}
.c-fable.run .star{animation:blink .5s steps(1) infinite -.25s}
@keyframes float{50%{transform:translateY(-2px)}}@keyframes blink{50%{opacity:.15}}
.c-heavy.run .it{animation:scan 1s steps(1) infinite}
.c-heavy.run .gl{animation:blink 1s steps(1) infinite -.5s}
@keyframes scan{25%{transform:translate(-1px,1px)}50%{transform:translate(-2px,2px)}75%{transform:translate(-1px,1px)}}
.c-careful.run .it,.c-lead.run .it{transform-origin:100% 100%;animation:twist .5s ease-in-out infinite}
@keyframes twist{50%{transform:rotate(-35deg)}}
.c-medium.run .pan,.c-core.run .pan{transform-origin:0 50%;animation:tilt 1s ease-in-out infinite}
.c-medium.run .egg,.c-core.run .egg{animation:flip 1s ease-in-out infinite}
@keyframes tilt{20%,40%{transform:rotate(-12deg)}}@keyframes flip{30%{transform:translateY(-5px) scaleY(-1)}60%{transform:translateY(0)}}
.c-light.run .la,.c-fast.run .la{animation-duration:.25s}.c-light.run .lb,.c-fast.run .lb{animation-duration:.25s;animation-delay:-.125s}
.c-light.run .flag,.c-fast.run .flag{transform-origin:0 50%;animation:wave .25s steps(1) infinite}
@keyframes wave{50%{transform:skewY(-12deg) scaleX(.85)}}
.c-explore.run .it{transform-origin:50% 100%;animation:fence .5s ease-in-out infinite}
@keyframes fence{50%{transform:rotate(25deg)}}
@media (prefers-reduced-motion: reduce){.run,.run g{animation:none!important}}
</style>`;

type Cut =
  | "spiky"
  | "short"
  | "bob"
  | "long"
  | "twin"
  | "pony"
  | "buns"
  | "knot"
  | "none";

const CAP = [
  "....hhhhhhhh....",
  "..hhhhhhhhhhhh..",
  ".hhhhhhhhhhhhhh.",
  "hhhhhhhhhhhhhhhh",
  "hhhhhhhhhhhhhhhh",
  "hhhhhhhhhhhhhhhh",
];

const BANGS = {
  jag: ["hhh.hhhh.hhh.hhh", "hh...hh...h...hh"],
  hime: ["hhhhhhhhhhhhhhhh", "hh............hh"],
  part: ["hhhhhhhhhh..hhhh", "hhhhhhh......hhh"],
  swept: ["hhhhhhhhhhhh.hhh", "h..hhhhhh.....hh"],
  open: ["hh............hh", "h..............h"],
} as const;

type Look = {
  hair: string;
  cut: Cut;
  bangs: keyof typeof BANGS;
  eye: string;
  outfit: string;
  trim?: string;
  legs?: string;
  armL?: boolean;
  armR?: boolean;
  clsL?: string;
  clsR?: string;
};

const chibi = (f: Fill, L: Look): void => {
  const h = L.hair;
  const trim = L.trim ?? L.outfit;
  if (L.cut === "long") {
    f(6, 5, 2, 16, h);
    f(22, 5, 2, 16, h);
  }
  f(8, 8, 14, 8, SKIN);
  f(9, 16, 12, 1, SKIN);
  for (const x of [10, 17]) {
    f(x, 10, 3, 1, INK);
    f(x, 11, 3, 2, L.eye);
    f(x, 11, 1, 1, "#fff");
  }
  f(14, 14, 2, 1, "#B5664F");
  f(9, 13, 1, 1, "#EFA08C");
  f(20, 13, 1, 1, "#EFA08C");
  if (L.cut !== "none") {
    stamp(f, 7, 2, CAP, { h });
    stamp(f, 7, 8, [...BANGS[L.bangs]], { h });
  }
  if (L.cut === "spiky") {
    stamp(f, 6, 0, ["...h....h...h..h..", "..hh..hhh..hhh.hh."], { h });
    f(5, 4, 2, 2, h);
    f(23, 4, 2, 2, h);
    f(6, 7, 1, 3, h);
    f(23, 7, 1, 3, h);
  }
  if (L.cut === "short" || L.cut === "buns" || L.cut === "knot") {
    f(7, 8, 1, 3, h);
    f(22, 8, 1, 3, h);
  }
  if (L.cut === "bob") {
    f(6, 6, 2, 9, h);
    f(22, 6, 2, 9, h);
  }
  if (L.cut === "long") {
    f(7, 8, 1, 9, h);
    f(22, 8, 1, 9, h);
  }
  if (L.cut === "twin") {
    f(6, 5, 2, 2, trim);
    f(22, 5, 2, 2, trim);
    stamp(
      f,
      3,
      6,
      [".hh", "hhh", "hhh", "hhh", "hhh", "hh.", "hh.", "h.."],
      { h },
      "tl",
    );
    stamp(
      f,
      24,
      6,
      ["hh.", "hhh", "hhh", "hhh", "hhh", ".hh", ".hh", "..h"],
      { h },
      "tr",
    );
  }
  if (L.cut === "pony") {
    f(6, 4, 1, 2, trim);
    stamp(
      f,
      2,
      3,
      ["..hh", ".hhh", "hhhh", "hhh.", "hhh.", "hh..", "hh..", "h..."],
      { h },
      "tl",
    );
  }
  if (L.cut === "buns") {
    f(5, 1, 4, 4, h);
    f(21, 1, 4, 4, h);
    f(6, 0, 2, 1, h);
    f(22, 0, 2, 1, h);
  }
  if (L.cut === "knot") {
    f(13, 0, 4, 2, h);
    f(14, 2, 2, 1, trim);
  }
  f(11, 17, 8, 6, L.outfit);
  f(14, 17, 2, 1, SKIN);
  f(11, 22, 8, 1, trim);
  if (L.armL) {
    f(8, 17, 3, 2, L.outfit, L.clsL);
    f(7, 14, 2, 3, L.outfit, L.clsL);
    f(6, 12, 2, 2, SKIN, L.clsL);
  } else {
    f(9, 17, 2, 4, L.outfit);
    f(9, 21, 2, 1, SKIN);
  }
  if (L.armR) {
    f(19, 17, 3, 2, L.outfit, L.clsR);
    f(21, 14, 2, 3, L.outfit, L.clsR);
    f(22, 12, 2, 2, SKIN, L.clsR);
  } else {
    f(19, 17, 2, 4, L.outfit);
    f(19, 21, 2, 1, SKIN);
  }
  const legs = L.legs ?? NAVY;
  f(12, 23, 2, 2, legs, "la");
  f(12, 25, 3, 1, DARK, "la");
  f(16, 23, 2, 2, legs, "lb");
  f(16, 25, 3, 1, DARK, "lb");
};

const glasses = (f: Fill, c = GOLD): void => {
  f(9, 13, 5, 1, c);
  f(16, 13, 5, 1, c);
  f(14, 11, 2, 1, c);
  f(9, 10, 1, 3, c);
  f(20, 10, 1, 3, c);
};

const COSTUMES: Record<string, (f: Fill, t: string) => void> = {
  fable: (f, t) => {
    chibi(f, {
      hair: "#B9B3F0",
      cut: "short",
      bangs: "swept",
      eye: t,
      outfit: CLOTH,
      trim: t,
      legs: CLOTH,
    });
    f(13, 19, 4, 2, t);
    f(6, 1, 18, 1, "#E6E8EE");
    f(5, 2, 1, 15, "#E6E8EE");
    f(24, 2, 1, 15, "#E6E8EE");
    f(6, 17, 18, 1, "#C9CCD2");
    f(6, 2, 18, 15, "rgba(169,214,245,.22)");
    f(7, 3, 2, 1, "#fff");
    f(7, 4, 1, 2, "#fff");
    f(25, 4, 2, 1, STEEL);
    f(27, 2, 1, 3, STEEL);
    f(26, 0, 3, 2, t, "ant");
    f(27, 9, 1, 3, GOLD, "star");
    f(26, 10, 3, 1, GOLD, "star");
  },
  heavy: (f, t) => {
    chibi(f, {
      hair: "#5A3519",
      cut: "short",
      bangs: "swept",
      eye: WOOD,
      outfit: "#C8A46A",
      trim: "#8A6A3A",
      legs: "#5A4A2E",
      armR: true,
      clsR: "it",
    });
    stamp(
      f,
      6,
      1,
      [
        "......bbbbbb......",
        "....bbcbbcbbbb....",
        "...bbbbbbbbbbbb...",
        "..bcbbcbbcbbcbbb..",
        ".bbbbbbbbbbbbbbbb.",
        "dddddddddddddddddd",
      ],
      { b: WOOD, c: "#A0703F", d: "#5A3519" },
    );
    f(7, 7, 16, 1, t);
    f(14, 18, 2, 4, "#8A6A3A");
    stamp(
      f,
      22,
      3,
      [".kkk.", "k...k", "k...k", "k...k", ".kkk."],
      { k: DARK },
      "it",
    );
    f(23, 4, 3, 3, "rgba(169,214,245,.7)", "it");
    f(24, 8, 1, 4, WOOD, "it");
    f(23, 4, 1, 1, "#fff", "gl");
  },
  careful: (f, t) => {
    chibi(f, {
      hair: "#4A3A2A",
      cut: "short",
      bangs: "jag",
      eye: WOOD,
      outfit: "#6E7686",
      trim: t,
      legs: "#6E7686",
      armR: true,
      clsR: "it",
    });
    stamp(
      f,
      6,
      1,
      [
        ".....yyyyyyyy.....",
        "...yyyyyhhyyyyy...",
        "..yyyyyyhhyyyyyy..",
        "..yyyyyyhhyyyyyy..",
        ".yyyyyyyhhyyyyyyy.",
        "dddddddddddddddddd",
      ],
      { y: GOLD, h: "#FBE08A", d: "#C99A1E" },
    );
    f(13, 2, 4, 2, t);
    f(12, 17, 1, 3, t);
    f(17, 17, 1, 3, t);
    stamp(
      f,
      21,
      1,
      [
        "s.s..",
        "sss..",
        ".ss..",
        "..ss.",
        "..ss.",
        "...ss",
        "...ss",
        "..ss.",
        "..s..",
        "..s..",
        "..s..",
      ],
      { s: "#C9CCD2" },
      "it",
    );
  },
  lead: (f, t) => COSTUMES.careful?.(f, t),
  medium: (f, t) => {
    chibi(f, {
      hair: WOOD,
      cut: "short",
      bangs: "hime",
      eye: "#3B6FB0",
      outfit: CLOTH,
      trim: "#B9C0D0",
      armR: true,
      clsR: "pan",
    });
    stamp(
      f,
      7,
      0,
      [
        "....wwwwwwww....",
        "..wwwwwwwwwwww..",
        ".wwwwwwwwwwwwww.",
        ".wwwwwwwwwwwwww.",
        "..wwwwwwwwwwww..",
        "..gggggggggggg..",
        "..wwwwwwwwwwww..",
        "..tttttttttttt..",
      ],
      { w: "#E9ECF2", g: "#B9C0D0", t },
    );
    f(12, 17, 6, 1, t);
    f(13, 19, 1, 1, "#B9C0D0");
    f(16, 19, 1, 1, "#B9C0D0");
    f(13, 21, 1, 1, "#B9C0D0");
    f(16, 21, 1, 1, "#B9C0D0");
    f(23, 10, 7, 2, "#4A4A48", "pan");
    f(22, 11, 2, 1, "#4A4A48", "pan");
    f(25, 9, 3, 1, "#F5B731", "egg");
  },
  core: (f, t) => COSTUMES.medium?.(f, t),
  light: (f, t) => {
    chibi(f, {
      hair: t,
      cut: "none",
      bangs: "open",
      eye: "#1F7A52",
      outfit: CLOTH,
      trim: t,
      legs: t,
      armR: true,
    });
    stamp(f, 7, 2, CAP, { h: t });
    f(7, 8, 16, 2, t);
    f(7, 10, 2, 6, t);
    f(21, 10, 2, 6, t);
    f(14, 2, 2, 8, WHITE);
    f(9, 9, 12, 1, DARK);
    f(14, 18, 2, 4, t);
    f(23, 1, 1, 11, STEEL);
    stamp(f, 24, 1, ["wkwk", "kwkw", "wkwk"], { w: WHITE, k: INK }, "flag");
  },
  fast: (f, t) => COSTUMES.light?.(f, t),
  explore: (f) => {
    chibi(f, {
      hair: "#2E3247",
      cut: "long",
      bangs: "open",
      eye: WOOD,
      outfit: "#9A3530",
      trim: GOLD,
      legs: "#55514C",
      armR: true,
      clsR: "it",
    });
    stamp(
      f,
      5,
      2,
      [
        ".kk..............kk.",
        ".kkk....kkkk....kkk.",
        "..kkkkkkkwwkkkkkkk..",
        "..kkkkkkkkkkkkkkkk..",
        ".gggggggggggggggggg.",
        "..kkkkkkkkkkkkkkkk..",
      ],
      { k: "#55514C", w: WHITE, g: GOLD },
    );
    f(8, 9, 14, 1, INK);
    f(16, 10, 5, 3, INK);
    f(22, 2, 2, 9, "#C9CCD2", "it");
    f(23, 1, 1, 1, "#C9CCD2", "it");
    f(21, 11, 4, 1, GOLD, "it");
  },
  other: (f) => {
    chibi(f, {
      hair: "#6B6B68",
      cut: "short",
      bangs: "jag",
      eye: "#55514C",
      outfit: CLAY,
      trim: "#B45F43",
    });
  },
};

type Mascot = {
  color: string;
  draw: (f: Fill, t: string) => void;
  css?: string;
};

export const MASCOTS: Record<string, Mascot> = {
  beacon: {
    color: "#E0A106",
    draw: (f, t) => {
      chibi(f, {
        hair: GOLD,
        cut: "spiky",
        bangs: "jag",
        eye: "#D0453F",
        outfit: NAVY,
        trim: t,
      });
      f(10, 16, 10, 2, "#D0453F");
      stamp(
        f,
        1,
        15,
        ["...rrrrr.", ".rrrrrrrr", "rrr.rrrrr", "r....rr.."],
        { r: "#D0453F" },
        "flag",
      );
      f(27, 0, 1, 5, t, "star");
      f(25, 2, 5, 1, t, "star");
      f(26, 1, 3, 3, GOLD, "star");
    },
    css: "& .flag{transform-origin:100% 50%;animation:wave .5s steps(1) infinite}& .star{animation:blink 1s steps(1) infinite}",
  },
  wren: {
    color: "#A0703F",
    draw: (f, t) => {
      chibi(f, {
        hair: t,
        cut: "bob",
        bangs: "hime",
        eye: "#3B9C5F",
        outfit: "#EAD9B8",
        trim: "#C8A46A",
        armR: true,
      });
      f(13, 19, 4, 2, "#C8A46A");
      stamp(
        f,
        21,
        5,
        [
          "t..bbb..",
          "tt.bkbo.",
          ".bbbbb..",
          ".bwwb...",
          "..bwb...",
          "..y.y...",
        ],
        {
          b: "#8A5A34",
          t: WOOD,
          w: "#EAD9B8",
          k: INK,
          o: "#F2913D",
          y: "#C99A1E",
        },
        "it",
      );
    },
    css: "& .it{animation:hop .5s steps(1) infinite}",
  },
  atlas: {
    color: "#378ADD",
    draw: (f, t) => {
      chibi(f, {
        hair: "#2B5FA8",
        cut: "short",
        bangs: "swept",
        eye: "#7FE3F5",
        outfit: CLOTH,
        trim: t,
        legs: "#5A6274",
        armR: true,
      });
      f(8, 10, 14, 3, DARK);
      f(9, 11, 12, 1, "#7FE3F5", "vis");
      f(11, 19, 8, 1, t);
      f(14, 18, 2, 3, t);
      stamp(
        f,
        22,
        3,
        [
          "..oooo..",
          ".oggooo.",
          "ogggoogo",
          "oogooggo",
          "ooooogoo",
          ".ogoooo.",
          "..oooo..",
        ],
        { o: "rgba(127,227,245,.75)", g: t },
        "it",
      );
      f(21, 10, 10, 1, "rgba(127,227,245,.45)", "it");
    },
    css: "& .it{animation:hop 1s ease-in-out infinite}& .vis{animation:blink 1s steps(1) infinite}",
  },
  ridge: {
    color: "#1D9E75",
    draw: (f, t) => {
      chibi(f, {
        hair: "#16614B",
        cut: "none",
        bangs: "open",
        eye: "#F5C542",
        outfit: "#16614B",
        trim: t,
        legs: "#16614B",
        armR: true,
      });
      stamp(f, 7, 2, CAP, { h: "#16614B" });
      f(7, 8, 16, 2, "#16614B");
      f(7, 10, 2, 7, "#16614B");
      f(21, 10, 2, 7, "#16614B");
      f(9, 13, 12, 4, "#16614B");
      f(11, 6, 8, 3, STEEL);
      f(13, 7, 4, 1, "#C9CCD2");
      stamp(f, 1, 8, ["..tt", ".ttt", "ttt.", "tt.."], { t }, "flag");
      stamp(
        f,
        23,
        6,
        ["..s..", ".sss.", "ssdss", ".sss.", "..s.."],
        { s: "#C9CCD2", d: DARK },
        "ndl",
      );
    },
    css: "& .ndl{transform-origin:50% 50%;animation:turn .5s steps(4) infinite}& .flag{transform-origin:100% 50%;animation:wave .5s steps(1) infinite}",
  },
  forge: {
    color: "#D85A30",
    draw: (f, t) => {
      chibi(f, {
        hair: "#C4332B",
        cut: "spiky",
        bangs: "jag",
        eye: "#F5B731",
        outfit: "#5A3519",
        trim: t,
        armR: true,
        clsR: "it",
      });
      f(7, 7, 16, 1, WHITE);
      f(5, 7, 2, 1, WHITE);
      f(4, 8, 2, 2, WHITE);
      f(12, 18, 6, 4, WOOD);
      f(23, 4, 1, 9, WOOD, "it");
      f(21, 1, 6, 3, STEEL, "it");
      f(21, 1, 6, 1, "#C9CCD2", "it");
      f(28, 2, 1, 1, GOLD, "sp");
      f(29, 5, 1, 1, t, "sp");
      f(27, 5, 1, 1, GOLD, "sq");
      f(29, 0, 1, 1, t, "sq");
    },
    css: "& .it{transform-origin:20% 100%;animation:strike .5s ease-in infinite}& .sp{animation:blink .5s steps(1) infinite}& .sq{animation:blink .5s steps(1) infinite -.25s}",
  },
  scout: {
    color: "#3B9C5F",
    draw: (f, t) => {
      chibi(f, {
        hair: t,
        cut: "pony",
        bangs: "jag",
        eye: GOLD,
        outfit: "#C8A46A",
        trim: "#8A6A3A",
        legs: "#5A4A2E",
        armR: true,
      });
      f(10, 16, 10, 2, "#2C7A49");
      f(9, 18, 2, 3, "#2C7A49");
      f(23, 1, 1, 11, STEEL);
      stamp(
        f,
        24,
        1,
        ["ggggw", "gggwg", "wgwgg", "gwggg"],
        { g: t, w: WHITE },
        "flag",
      );
    },
    css: "& .flag{transform-origin:0 50%;animation:wave .5s steps(1) infinite}",
  },
  aegis: {
    color: "#5B6CC9",
    draw: (f, t) => {
      chibi(f, {
        hair: "#B4BAD0",
        cut: "long",
        bangs: "hime",
        eye: t,
        outfit: "#AEB4C4",
        trim: GOLD,
        legs: "#7C8498",
      });
      f(10, 6, 10, 1, GOLD);
      f(14, 5, 2, 1, t);
      f(13, 19, 4, 2, t);
      stamp(
        f,
        19,
        15,
        [
          "sssssss",
          "sbbwbbs",
          "sbbwbbs",
          "swwwwws",
          "sbbwbbs",
          "sbbwbbs",
          ".sbwbs.",
          "..sss..",
        ],
        { s: GOLD, b: t, w: WHITE },
      );
      f(20, 16, 1, 2, "#fff", "gl");
    },
    css: "& .gl{animation:blink 1s steps(1) infinite}",
  },
  compass: {
    color: "#D0453F",
    draw: (f, t) => {
      chibi(f, {
        hair: "#B8322C",
        cut: "short",
        bangs: "part",
        eye: "#12A5A0",
        outfit: "#D9C9A3",
        trim: "#8A6A3A",
        legs: "#6B5A3A",
        armR: true,
      });
      f(14, 0, 1, 2, "#B8322C");
      f(15, 0, 2, 1, "#B8322C");
      f(17, 1, 1, 1, "#B8322C");
      f(11, 16, 8, 2, t);
      f(14, 18, 2, 2, t);
      stamp(
        f,
        22,
        4,
        [
          "..ggg..",
          ".gwwwg.",
          "gwwwwwg",
          "gwwwwwg",
          "gwwwwwg",
          ".gwwwg.",
          "..ggg..",
        ],
        { g: GOLD, w: WHITE },
      );
      f(25, 5, 1, 3, t, "ndl");
      f(25, 8, 1, 2, DARK, "ndl");
    },
    css: "& .ndl{transform-origin:50% 60%;animation:swing 1s ease-in-out infinite}",
  },
  pace: {
    color: "#12A5A0",
    draw: (f, t) => {
      chibi(f, {
        hair: t,
        cut: "pony",
        bangs: "swept",
        eye: "#E0559A",
        outfit: CLOTH,
        trim: t,
        legs: t,
        armR: true,
      });
      f(7, 6, 16, 1, WHITE);
      f(11, 19, 8, 1, t);
      f(14, 20, 2, 2, t);
      f(24, 3, 3, 1, DARK);
      f(25, 4, 1, 1, DARK);
      stamp(
        f,
        22,
        5,
        [
          ".kkkkk.",
          "kwwwwwk",
          "kwwwwwk",
          "kwwwwwk",
          "kwwwwwk",
          "kwwwwwk",
          ".kkkkk.",
        ],
        { k: DARK, w: WHITE },
      );
      f(25, 6, 1, 3, t, "ndl");
    },
    css: "& .la{animation-duration:.25s}& .lb{animation-duration:.25s;animation-delay:-.125s}& .ndl{transform-origin:50% 100%;animation:turn 1s steps(4) infinite}",
  },
  quill: {
    color: "#8A63D2",
    draw: (f, t) => {
      chibi(f, {
        hair: t,
        cut: "long",
        bangs: "part",
        eye: "#5E3FA3",
        outfit: "#3A3350",
        trim: t,
        armR: true,
        clsR: "it",
      });
      glasses(f);
      f(14, 18, 2, 1, WHITE);
      f(13, 19, 4, 1, WHITE);
      stamp(
        f,
        22,
        1,
        [
          ".....ww",
          "....www",
          "...wwwg",
          "...wwg.",
          "..wwg..",
          "..wg...",
          ".wg....",
          ".g.....",
          "k......",
          "k......",
          "k......",
        ],
        { w: "#E8D9A8", g: "#B9A66A", k: WOOD },
        "it",
      );
    },
    css: "& .it{animation:scan .5s steps(1) infinite}",
  },
  tower: {
    color: "#D0453F",
    draw: (f, t) => {
      chibi(f, {
        hair: "#4A4E69",
        cut: "short",
        bangs: "swept",
        eye: t,
        outfit: NAVY,
        trim: GOLD,
        armR: true,
      });
      stamp(
        f,
        6,
        1,
        [
          "....kkkkkkkkkk....",
          "..kkkkkkkkkkkkkk..",
          "..kkkkkkyykkkkkk..",
          "..rrrrrrrrrrrrrr..",
          ".kkkkkkkkkkkkkkkkkk",
        ],
        { k: NAVY, y: GOLD, r: t },
      );
      f(9, 19, 2, 6, NAVY);
      f(19, 19, 2, 6, NAVY);
      f(12, 19, 1, 3, GOLD);
      f(17, 19, 1, 3, GOLD);
      f(22, 9, 2, 3, DARK);
      f(21, 5, 4, 4, t, "ant");
      f(22, 4, 2, 1, t, "ant");
      f(22, 6, 1, 1, "#fff", "ant");
    },
    css: "& .ant{animation:blink .5s steps(1) infinite}",
  },
  navigator: {
    color: "#4A6FC0",
    draw: (f, t) => {
      chibi(f, {
        hair: "#5B8FE0",
        cut: "twin",
        bangs: "hime",
        eye: "#2E4A8A",
        outfit: CLOTH,
        trim: t,
        armR: true,
        clsR: "pan",
      });
      f(10, 1, 10, 2, CLOTH);
      f(9, 3, 12, 1, t);
      f(14, 1, 2, 1, GOLD);
      f(11, 17, 3, 2, t);
      f(16, 17, 3, 2, t);
      f(14, 19, 2, 2, "#D0453F");
      stamp(
        f,
        22,
        4,
        [
          "pppppppp",
          "pbbpppgp",
          "pbpprppp",
          "pppprprp",
          "pgpprrrp",
          "ppgpppxp",
          "pppppppp",
          "pppppppp",
        ],
        { p: "#EAD9B8", b: "#7FB3E6", g: "#8FBF7A", r: "#D0453F", x: INK },
        "pan",
      );
    },
    css: "& .pan{transform-origin:0 100%;animation:tilt 1s ease-in-out infinite}",
  },
  turbine: {
    color: "#2F7FD0",
    draw: (f, t) => {
      chibi(f, {
        hair: t,
        cut: "spiky",
        bangs: "jag",
        eye: "#F2913D",
        outfit: "#6E7686",
        trim: DARK,
        legs: "#6E7686",
        armR: true,
        clsR: "it",
      });
      f(7, 5, 16, 3, DARK);
      f(9, 5, 5, 3, "#A9D6F5");
      f(16, 5, 5, 3, "#A9D6F5");
      f(9, 5, 1, 1, "#fff");
      f(16, 5, 1, 1, "#fff");
      f(12, 17, 1, 3, t);
      f(17, 17, 1, 3, t);
      f(12, 19, 6, 3, t);
      stamp(
        f,
        21,
        1,
        [
          "s.s..",
          "sss..",
          ".ss..",
          "..ss.",
          "..ss.",
          "...ss",
          "...ss",
          "..ss.",
          "..s..",
          "..s..",
          "..s..",
        ],
        { s: "#C9CCD2" },
        "it",
      );
    },
    css: "& .it{transform-origin:50% 100%;animation:fence .5s ease-in-out infinite}",
  },
  jetstream: {
    color: "#2BB3C0",
    draw: (f, t) => {
      chibi(f, {
        hair: t,
        cut: "short",
        bangs: "swept",
        eye: "#1B7F8A",
        outfit: WOOD,
        trim: "#EAD9B8",
        legs: "#5A4A2E",
      });
      f(7, 5, 16, 3, WOOD);
      f(9, 5, 5, 3, "#A9D6F5");
      f(16, 5, 5, 3, "#A9D6F5");
      f(9, 5, 1, 1, "#fff");
      f(16, 5, 1, 1, "#fff");
      f(10, 16, 10, 2, "#F2913D");
      stamp(
        f,
        0,
        14,
        ["....wwww..", "..wwwwwwww", "wwww.wwwww", "ww....ww.."],
        { w: "#F2913D" },
        "flag",
      );
      f(13, 19, 4, 1, GOLD);
    },
    css: "& .flag{transform-origin:100% 50%;animation:wave .25s steps(1) infinite}",
  },
  avionics: {
    color: "#7F77DD",
    draw: (f, t) => {
      chibi(f, {
        hair: t,
        cut: "buns",
        bangs: "hime",
        eye: "#5E3FA3",
        outfit: CLOTH,
        trim: "#C9CCD2",
        armR: true,
      });
      glasses(f, "#C9CCD2");
      f(14, 18, 2, 4, t);
      f(22, 2, 8, 9, "rgba(127,227,245,.28)");
      f(22, 2, 8, 1, "#7FE3F5");
      f(22, 10, 8, 1, "#7FE3F5");
      f(23, 7, 1, 3, t);
      f(25, 6, 1, 4, t);
      f(28, 8, 1, 2, t);
      f(24, 5, 1, 5, "#3BD671", "b1");
      f(26, 4, 1, 6, "#3BD671", "b2");
      f(27, 6, 1, 4, "#3BD671", "b1");
    },
    css: "& .b1{transform-origin:50% 100%;animation:grow 1s steps(2) infinite}& .b2{transform-origin:50% 100%;animation:grow 1s steps(2) infinite -.5s}",
  },
  altimeter: {
    color: "#2FA36B",
    draw: (f, t) => {
      chibi(f, {
        hair: "#1F7A52",
        cut: "bob",
        bangs: "part",
        eye: t,
        outfit: CLOTH,
        trim: t,
        legs: "#1F5A40",
      });
      f(16, 9, 5, 1, GOLD);
      f(16, 13, 5, 1, GOLD);
      f(16, 10, 1, 3, GOLD);
      f(20, 10, 1, 3, GOLD);
      f(21, 13, 1, 4, GOLD);
      f(11, 17, 3, 3, "#1F5A40");
      f(16, 17, 3, 3, "#1F5A40");
      f(10, 19, 10, 5, DARK);
      f(11, 20, 8, 3, "#14261C");
      f(11, 22, 1, 1, t);
      f(13, 20, 1, 1, t);
      f(16, 20, 1, 1, t);
      f(18, 22, 1, 1, t);
      f(15, 20, 1, 3, "#FF6B5E", "ndl");
    },
    css: "& .ndl{transform-origin:50% 100%;animation:swing 1s ease-in-out infinite}",
  },
  radar: {
    color: "#3BD671",
    draw: (f, t) => {
      chibi(f, {
        hair: "#2BA356",
        cut: "short",
        bangs: "jag",
        eye: t,
        outfit: "#3A3350",
        trim: t,
      });
      stamp(
        f,
        6,
        0,
        [".h..", "hhh.", "hphh"],
        { h: "#2BA356", p: "#F3A6C0" },
        "el",
      );
      stamp(
        f,
        20,
        0,
        ["..h.", ".hhh", "hhph"],
        { h: "#2BA356", p: "#F3A6C0" },
        "er",
      );
      f(13, 19, 4, 2, t);
      f(9, 13, 2, 1, WHITE);
      f(19, 13, 2, 1, WHITE);
      f(24, 6, 1, 1, t, "p1");
      f(26, 5, 1, 3, t, "p2");
      f(28, 4, 1, 5, t, "p3");
      stamp(f, 21, 20, ["..hh", ".hh.", "hh.."], { h: "#2BA356" }, "tr");
    },
    css: "& .el{transform-origin:50% 100%;animation:twitch 1s steps(1) infinite}& .er{transform-origin:50% 100%;animation:twitch 1s steps(1) infinite -.5s}& .p1{animation:ping 1s steps(1) infinite}& .p2{animation:ping 1s steps(1) infinite -.66s}& .p3{animation:ping 1s steps(1) infinite -.33s}",
  },
  tarmac: {
    color: "#F26B21",
    draw: (f, t) => {
      chibi(f, {
        hair: t,
        cut: "short",
        bangs: "jag",
        eye: "#7A4A26",
        outfit: "#E4F01F",
        trim: "#C9CCD2",
        legs: "#4A4E69",
        armL: true,
        armR: true,
        clsL: "wl",
        clsR: "wr",
      });
      f(8, 3, 14, 1, DARK);
      f(6, 8, 2, 5, DARK);
      f(22, 8, 2, 5, DARK);
      f(11, 19, 8, 1, "#C9CCD2");
      f(12, 17, 1, 6, t);
      f(17, 17, 1, 6, t);
      f(5, 10, 2, 2, DARK, "wl");
      f(3, 2, 2, 8, "#FF4D2E", "wl");
      f(4, 9, 2, 2, "#FF4D2E", "wl");
      f(3, 1, 2, 1, GOLD, "wl");
      f(23, 10, 2, 2, DARK, "wr");
      f(25, 2, 2, 8, "#FF4D2E", "wr");
      f(24, 9, 2, 2, "#FF4D2E", "wr");
      f(25, 1, 2, 1, GOLD, "wr");
    },
    css: "& .wl{transform-origin:100% 100%;animation:fenceb .5s ease-in-out infinite}& .wr{transform-origin:0 100%;animation:fence .5s ease-in-out infinite}",
  },
  checkpoint: {
    color: "#5578C8",
    draw: (f, t) => {
      chibi(f, {
        hair: "#2E3247",
        cut: "knot",
        bangs: "open",
        eye: "#6F8FB8",
        outfit: t,
        trim: "#2E3247",
        legs: "#2E3247",
        armR: true,
        clsR: "it",
      });
      f(9, 9, 5, 1, "#2E3247");
      f(16, 9, 5, 1, "#2E3247");
      f(13, 17, 1, 2, WHITE);
      f(16, 17, 1, 2, WHITE);
      f(14, 18, 2, 1, WHITE);
      f(11, 23, 8, 1, "#2E3247");
      f(22, 14, 2, 1, WOOD, "it");
      f(21, 11, 4, 1, GOLD, "it");
      f(22, 0, 2, 11, "#E6E8EE", "it");
      f(23, 0, 1, 11, "#AEB4C4", "it");
      f(22, 0, 1, 1, "#AEB4C4", "it");
      f(22, 3, 1, 2, "#fff", "gl");
    },
    css: "& .it{animation:lift 1s steps(1) infinite}& .gl{animation:glint 1s steps(1) infinite}",
  },
  manifest: {
    color: "#C27A1A",
    draw: (f, t) => {
      chibi(f, {
        hair: t,
        cut: "short",
        bangs: "part",
        eye: "#7A4A26",
        outfit: NAVY,
        trim: GOLD,
        armR: true,
      });
      glasses(f, DARK);
      f(13, 17, 4, 2, WHITE);
      f(14, 18, 2, 4, "#D0453F");
      stamp(
        f,
        21,
        2,
        [
          "..ssss..",
          "bbbbbbbb",
          "bwwwwwwb",
          "bwwwwwwb",
          "bwwwwwwb",
          "bwwwwwwb",
          "bwwwwwwb",
          "bwwwwwwb",
          "bbbbbbbb",
        ],
        { s: STEEL, b: WOOD, w: WHITE },
      );
      f(25, 4, 3, 1, "#9a9a96");
      f(25, 6, 3, 1, "#9a9a96");
      f(25, 8, 3, 1, "#9a9a96");
      f(23, 4, 1, 1, "#3B9C5F", "c1");
      f(23, 6, 1, 1, "#3B9C5F", "c2");
      f(23, 8, 1, 1, "#3B9C5F", "c3");
    },
    css: "& .c1{animation:tick 1s steps(1) infinite}& .c2{animation:tick 1s steps(1) infinite -.66s}& .c3{animation:tick 1s steps(1) infinite -.33s}",
  },
  logbook: {
    color: "#B5527A",
    draw: (f, t) => {
      chibi(f, {
        hair: "#E08FB0",
        cut: "long",
        bangs: "hime",
        eye: GOLD,
        outfit: "#5A2A44",
        trim: t,
        legs: "#5A2A44",
      });
      stamp(
        f,
        3,
        0,
        [
          "...........tt...........",
          "..........tttt..........",
          ".........tttttt.........",
          "........tttttttt........",
          ".......ggggggggggg......",
          "......tttttttttttt......",
          "..tttttttttttttttttttt..",
          "tttttttttttttttttttttttt",
        ],
        { t, g: GOLD },
      );
      f(14, 19, 2, 2, GOLD);
      f(21, 13, 9, 6, t, "it");
      f(22, 13, 3, 5, WHITE, "it");
      f(26, 13, 3, 5, WHITE, "it");
      f(25, 13, 1, 6, "#8A3A5A", "it");
      f(26, 13, 3, 5, "#EDEBE4", "pg");
      f(22, 10, 1, 1, GOLD, "sp");
      f(28, 11, 1, 1, GOLD, "sq");
      f(25, 9, 1, 1, GOLD, "sp");
    },
    css: "& .it{animation:hop 1s ease-in-out infinite}& .pg{transform-origin:0 50%;animation:page 1s steps(1) infinite}& .sp{animation:blink .5s steps(1) infinite}& .sq{animation:blink .5s steps(1) infinite -.25s}",
  },
};

const MASCOT_CSS = `<style>
@keyframes hop{50%{transform:translateY(-2px)}}@keyframes sway{25%{transform:rotate(-6deg)}75%{transform:rotate(6deg)}}
@keyframes strike{0%,100%{transform:rotate(0)}50%{transform:rotate(-40deg)}}@keyframes swing{0%,100%{transform:rotate(-45deg)}50%{transform:rotate(45deg)}}
@keyframes turn{to{transform:rotate(360deg)}}@keyframes whirl{50%{transform:scaleX(.25)}}
@keyframes grow{50%{transform:scaleY(.5)}}@keyframes pan{25%{transform:scaleX(.5)}50%{transform:scaleX(-1)}75%{transform:scaleX(.5)}}
@keyframes ping{0%{opacity:1}33%,100%{opacity:.12}}@keyframes fenceb{50%{transform:rotate(-25deg)}}
@keyframes lift{50%{transform:translateY(-1px)}}@keyframes tick{0%{opacity:0}33%,100%{opacity:1}}
@keyframes page{0%{transform:scaleX(1)}33%{transform:scaleX(.4)}66%,100%{transform:scaleX(0)}}
@keyframes twitch{50%{transform:rotate(-12deg)}}@keyframes glint{0%{transform:translateY(0);opacity:1}33%{transform:translateY(3px)}66%{transform:translateY(6px)}80%,100%{opacity:0}}
.run .tl{transform-origin:100% 0;animation:sway 1s ease-in-out infinite}.run .tr{transform-origin:0 0;animation:sway 1s ease-in-out infinite -.5s}
@media (prefers-color-scheme: dark){rect[fill="${DARK}"]{fill:#9A9AA2}rect[fill="#3A4466"]{fill:#7F90CC}rect[fill="#1E6B45"]{fill:#2F9A66}rect[fill="#5A3519"]{fill:#8A5A34}rect[fill="#3A3350"]{fill:#6A6190}rect[fill="#2E3247"]{fill:#5F6690}rect[fill="#5A2A44"]{fill:#8E4A6E}rect[fill="#16614B"]{fill:#238F6E}}
${Object.entries(MASCOTS)
  .map(([name, m]) => (m.css ?? "").replaceAll("&", `.c-${name}.run`))
  .join("\n")}
</style>`;

const mascotOf = (type: string): string | undefined => {
  const bare = type.replace(/^[^:]*:/, "").toLowerCase();
  return bare in MASCOTS ? bare : undefined;
};

const tierOf = (type: string): string => {
  const bare = type.replace(/^[^:]*:/, "").toLowerCase();
  const stripped = bare.replace(/^savvy-/, "");
  return stripped in TIER_COLOR ? stripped : "other";
};

const costumeOf = (type: string): string =>
  mascotOf(type) ?? (type === "Explore" ? "explore" : tierOf(type));

const colorOf = (costume: string): string =>
  MASCOTS[costume]?.color ?? TIER_COLOR[costume] ?? "#888780";

const CRAB_SCALE = 1.1;

const crab = (
  x: number,
  y: number,
  costume: string,
  dim = false,
  isWalking = false,
  scale = CRAB_SCALE,
): string => {
  const groups = new Map<string, string[]>([["bd", []]]);
  const f: Fill = (cx, cy, w, h, c, cls = "bd") => {
    if (!groups.has(cls)) groups.set(cls, []);
    groups
      .get(cls)
      ?.push(
        `<rect x="${cx}" y="${cy}" width="${w}" height="${h}" fill="${c}"/>`,
      );
  };
  const draw =
    COSTUMES[costume] ??
    MASCOTS[costume]?.draw ??
    COSTUMES.other ??
    (() => undefined);
  draw(f, colorOf(costume));
  const group = (cls: string) =>
    `<g class="${cls}">${(groups.get(cls) ?? []).join("")}</g>`;
  const props = [...groups.keys()].filter(
    (k) => k !== "bd" && k !== "la" && k !== "lb",
  );
  const body = `<g class="bd">${(groups.get("bd") ?? []).join("")}${props.map(group).join("")}</g>`;
  return `<g transform="translate(${x},${y}) scale(${scale})" opacity="${dim ? 0.45 : 1}" shape-rendering="crispEdges"><g class="c-${costume}${isWalking ? " run" : ""}">${body}${group("la")}${group("lb")}</g></g>`;
};

const svg = (W: number, H_px: number, body: string): string =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H_px}" viewBox="0 0 ${W} ${H_px}">${PANE_CSS}${CRAB_CSS}${MASCOT_CSS}${body}</svg>`;

// ---------------------------------------------------------------------------
// Desktop SVG builders for the 5 sections and AbovePrompt band

const bandSvg = (f: Flow, W: number, isWorking: boolean): string => {
  const total = f.tasks.length;
  const accepted = total - remaining(f);
  const runningCount = f.tasks.filter((t) => t.state === "running").length;
  const ratioVal = f.closedAt !== null ? 1 : total > 0 ? accepted / total : 0;
  const title = fitText(f.title || "Orchestrator", 13, Math.max(60, W * 0.35));
  const BAR_X = Math.round(16 + textWidth(title, 13) + 12);
  const BAR_W = Math.max(60, W - BAR_X - 46 - CRAB_W);
  const color = f.closedAt !== null ? GREEN : BLUE;
  const y0 = (H - BAR_H) / 2;
  const fillW = Math.round(BAR_W * ratioVal);
  const runW = total
    ? Math.round((BAR_W * Math.min(total, accepted + runningCount)) / total)
    : 0;
  const dots: string[] = [];

  const cols = Math.floor(fillW / CELL);
  const rows = Math.floor(BAR_H / CELL);
  for (let c = 0; c < cols; c++) {
    const density = 0.35 + 0.6 * Math.pow(c / Math.max(1, cols), 1.2);
    for (let r = 0; r < rows; r++) {
      if (noise(c, r) < density) {
        dots.push(
          `<rect class="t${Math.floor(noise(r, c) * 4)}" x="${c * CELL + 1}" y="${r * CELL + 1}" width="2" height="2"/>`,
        );
      }
    }
  }
  const faint: string[] = [];
  for (let c = cols; c < Math.floor(runW / CELL); c++) {
    for (let r = 0; r < rows; r++) {
      if (noise(c + 7, r + 3) < 0.2) {
        faint.push(
          `<rect class="t${Math.floor(noise(r + 5, c) * 4)}" x="${c * CELL + 1}" y="${r * CELL + 1}" width="1.7" height="1.7"/>`,
        );
      }
    }
  }

  const pillText = `${f.phase} · ${accepted} of ${total} accepted`;
  const pillW = Math.min(BAR_W, Math.round(18 + pillText.length * 6.2));
  const pillX = Math.max(
    0,
    Math.min(BAR_W - pillW, Math.max(fillW - pillW, 0)),
  );
  const percent = `${Math.round(ratioVal * 100)}%`;

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
<style>
.t{fill:#1f1f1f}.m{fill:#8a8a8a}.k{fill:#e4e4e2}.tk{fill:#b4b4b0}
@media (prefers-color-scheme: dark){.t{fill:#ececec}.m{fill:#9a9a9a}.k{fill:#2c2c2c}.tk{fill:#5a5a5a}}
.t0,.t1,.t2,.t3{animation:tw ${f.closedAt !== null ? 3.2 : 2.2}s ease-in-out infinite}
@keyframes tw{0%,100%{opacity:1}50%{opacity:${f.closedAt !== null ? 0.8 : 0.3}}}
@media (prefers-reduced-motion: reduce){.t0,.t1,.t2,.t3{animation:none}}
</style>
<defs><clipPath id="c"><rect x="0" y="0" width="${BAR_W}" height="${BAR_H}" rx="${BAR_H / 2}"/></clipPath></defs>
<circle cx="5" cy="${H / 2}" r="4" fill="${color}"/>
<text class="t" x="16" y="${H / 2 + 4.5}" font-family="${FONT}" font-size="13" font-weight="500">${xml(title)}</text>
<g transform="translate(${BAR_X},${y0})">
<rect class="k" width="${BAR_W}" height="${BAR_H}" rx="${BAR_H / 2}"/>
<g clip-path="url(#c)">
<g fill="${color}">${dots.join("")}</g>
<g fill="${color}" opacity="0.45">${faint.join("")}</g>
</g>
<rect x="${pillX}" width="${pillW}" height="${BAR_H}" rx="${BAR_H / 2}" fill="${color}"/>
<text x="${pillX + pillW / 2}" y="${BAR_H / 2 + 4}" text-anchor="middle" font-family="${FONT}" font-size="10.5" font-weight="600" fill="#ffffff">${xml(pillText)}</text>
</g>
<text class="m" x="${W - CRAB_W - 6}" y="${H / 2 + 4.5}" text-anchor="end" font-family="${FONT}" font-size="12" font-variant-numeric="tabular-nums">${percent}</text>
${CRAB_CSS}${MASCOT_CSS}${crab(W - CRAB_W + 1, 0, "beacon", false, isWorking, 0.8)}
</svg>`;
};

const headerSvg = (W: number, f: Flow, sp: SpendSummary): string => {
  const total = f.tasks.length;
  const accepted = total - remaining(f);
  const phaseIdx = PHASES.indexOf(f.phase);
  const pillGap = 4;
  const pillW = Math.max(
    36,
    Math.floor((W - pillGap * (PHASES.length - 1)) / PHASES.length),
  );
  const pills = PHASES.map((ph, i) => {
    const isDone = f.closedAt !== null || i < phaseIdx;
    const isCurrent = f.closedAt === null && i === phaseIdx;
    const x = i * (pillW + pillGap);
    const fill = isCurrent ? BLUE : isDone ? "rgba(59,156,95,0.18)" : "";
    const textCls = isCurrent ? "" : isDone ? "s" : "m";
    const textFill = isCurrent ? ' fill="#ffffff"' : "";
    const label = isDone ? `✓ ${ph}` : ph;
    return `<rect${fill ? ` fill="${fill}"` : ' class="tile"'} x="${x}" y="24" width="${pillW}" height="20" rx="10"/>
<text${textCls ? ` class="${textCls}"` : ""}${textFill} x="${x + pillW / 2}" y="38" text-anchor="middle" font-family="${FONT}" font-size="11" font-weight="${isCurrent ? "600" : "400"}">${xml(label)}</text>`;
  }).join("");

  const rightSummary = `accepted ${accepted} of ${total} · est. ${fmtCost(sp.total)}`;
  const titleMaxW = Math.max(80, W - textWidth(rightSummary, 11) - 12);
  return svg(
    W,
    50,
    `<text class="t" x="0" y="15" font-family="${FONT}" font-size="14" font-weight="600">${xml(fitText(f.title || "Flow", 14, titleMaxW))}</text>
<text class="s" x="${W}" y="15" text-anchor="end" font-family="${FONT}" font-size="11" font-variant-numeric="tabular-nums">${xml(rightSummary)}</text>
${pills}`,
  );
};

const burnDownSvg = (W: number, bd: BurnDown, totalTasks: number): string => {
  const H_px = 76;
  const padL = 26;
  const padR = 12;
  const padT = 12;
  const padB = 18;
  const pw = Math.max(40, W - padL - padR);
  const ph = H_px - padT - padB;

  const maxY = Math.max(
    1,
    totalTasks,
    ...bd.points.map((p) => p.remaining),
    ...bd.replans.map((r) => r.total),
  );
  const t0 = bd.ideal[0]?.at ?? bd.points[0]?.at ?? 0;
  const t1 = Math.max(
    t0,
    bd.ideal[1]?.at ?? t0,
    ...bd.points.map((p) => p.at),
    ...bd.replans.map((r) => r.at),
  );
  const tSpan = t1 - t0;

  const xOf = (at: number, idx: number, count: number): number => {
    if (tSpan > 0) return Math.round(padL + ((at - t0) / tSpan) * pw);
    if (count <= 1) return padL;
    return Math.round(padL + (idx / (count - 1)) * pw);
  };
  const yOf = (val: number): number =>
    Math.round(padT + ph - (Math.max(0, Math.min(maxY, val)) / maxY) * ph);

  const idealStart = bd.ideal[0]?.remaining ?? maxY;
  const idealLine = `<line x1="${padL}" y1="${yOf(idealStart)}" x2="${padL + pw}" y2="${yOf(0)}" stroke="#9a9a96" stroke-width="1.4" stroke-dasharray="4 3"/>`;

  const pts = bd.points.map((p, i) => ({
    x: xOf(p.at, i, bd.points.length),
    y: yOf(p.remaining),
    rem: p.remaining,
  }));
  const poly =
    pts.length > 1
      ? `<polyline fill="none" stroke="${BLUE}" stroke-width="2" points="${pts.map((p) => `${p.x},${p.y}`).join(" ")}"/>`
      : "";
  const dots = pts
    .map(
      (p) =>
        `<circle cx="${p.x}" cy="${p.y}" r="3" fill="${p.rem === 0 ? GREEN : BLUE}"/>`,
    )
    .join("");

  const replanMarks = bd.replans
    .map((r, i) => {
      const rx =
        tSpan > 0
          ? Math.round(padL + ((r.at - t0) / tSpan) * pw)
          : Math.round(padL + ((i + 1) / (bd.replans.length + 1)) * pw);
      return `<line x1="${rx}" y1="${padT}" x2="${rx}" y2="${padT + ph}" stroke="${AMBER}" stroke-width="1.4" stroke-dasharray="2 2"/>
<polygon points="${rx},${padT - 3} ${rx + 3.5},${padT + 1} ${rx},${padT + 5} ${rx - 3.5},${padT + 1}" fill="${AMBER}"/>`;
    })
    .join("");

  return svg(
    W,
    H_px,
    `<rect class="tile" x="0" y="0" width="${W}" height="${H_px}" rx="6"/>
<text class="m" x="6" y="${padT + 4}" font-family="${FONT}" font-size="10">${maxY}</text>
<text class="m" x="6" y="${padT + ph}" font-family="${FONT}" font-size="10">0</text>
<line class="ln" x1="${padL}" y1="${padT + ph}" x2="${padL + pw}" y2="${padT + ph}"/>
${idealLine}${replanMarks}${poly}${dots}
<text class="m" x="${padL}" y="${H_px - 4}" font-family="${FONT}" font-size="9.5">dashed = ideal${bd.replans.length ? ` · ♦ ${bd.replans.length} re-plan` : ""}</text>`,
  );
};

const agentRowSvg = (W: number, r: Run, at: number): string => {
  const costume = costumeOf(r.agent);
  const color = statusHex(r.status);
  const mascotColor = colorOf(costume);
  const textW = Math.max(80, W - 44 - 16);
  const cost = runCost(r);
  const costLabel = cost !== null ? `est. ${fmtCost(cost)}` : "unpriced";
  const tokLabel = `${fmtTokens(runTotalTokens(r))} tok`;
  const timeLabel = fmtTime(runElapsed(r, at));
  const stepText =
    r.steps && r.steps.total > 0
      ? `${r.steps.done}/${r.steps.total}${r.steps.note ? " · " + r.steps.note : ""}`
      : `ctx ${r.contextPct ?? 0}%`;
  const ratioVal =
    r.status === "done"
      ? 1
      : r.steps && r.steps.total > 0
        ? Math.min(1, r.steps.done / r.steps.total)
        : Math.min(1, (r.contextPct ?? 0) / 100);
  const fillW = Math.round(textW * ratioVal);
  const meta = [
    r.model || "—",
    ...(r.effort ? [r.effort] : []),
    ...(r.role === "lead" ? ["lead"] : []),
    r.status,
  ].join(" · ");
  const stats = `${stepText} · ${tokLabel} · ${costLabel} · ${timeLabel}`;

  return svg(
    W,
    58,
    `${crab(0, 10, costume, false, r.status === "running")}
<text class="t" x="42" y="16" font-family="${FONT}" font-size="12.5" font-weight="600">${xml(fitText(`${r.agent}: ${r.title || r.agent}`, 12.5, textW))}</text>
<text x="42" y="31" font-family="${FONT}" font-size="11"><tspan fill="${mascotColor}">${xml(r.agent)}</tspan><tspan class="s">  ${xml(fitText(meta, 11, textW - 40))}</tspan></text>
<text class="s" x="42" y="45" font-family="${FONT}" font-size="10.5" font-variant-numeric="tabular-nums">${xml(fitText(stats, 10.5, textW))}</text>
<rect class="k" x="42" y="50" width="${textW}" height="3.5" rx="1.75"/>
<rect x="42" y="50" width="${fillW}" height="3.5" rx="1.75" fill="${color}"/>
<circle${r.status === "running" ? ' class="live"' : ""} cx="${W - 8}" cy="14" r="3.5" fill="${color}"/>`,
  );
};

// ---------------------------------------------------------------------------
// Pane open/close helpers & state reducers

async function togglePane($: EngineInterface): Promise<boolean> {
  const isOpen = (await $.ui.panes()).some((p) => p.id === PANE);
  if (isOpen) {
    await $.ui.close({ id: PANE });
    return false;
  }
  const at = await $.clock.now();
  await update($, now, () => at);
  await $.ui.open({ id: PANE, title: PANE_TITLE });
  return true;
}

async function autoOpen($: EngineInterface, key: string): Promise<void> {
  const p = await read($, panel);
  if (p.autoOpenedFor === key) return;
  await update($, panel, (prev) => ({ ...prev, autoOpenedFor: key }));
  void $.ui.open({ id: PANE, title: PANE_TITLE });
}

const cleanTasks = (raw: ProgressInput["tasks"]): PlanTaskInput[] =>
  (raw ?? [])
    .filter((t) => typeof t.title === "string" && t.title.trim().length > 0)
    .map((t) => {
      const rawTier = String(t.tier ?? "core")
        .trim()
        .toLowerCase();
      const tier: Tier = (TIERS as readonly string[]).includes(rawTier)
        ? (rawTier as Tier)
        : "core";
      return {
        title: String(t.title ?? "").trim(),
        specialist: String(t.specialist ?? "wren").trim(),
        tier,
        after: Array.isArray(t.after)
          ? t.after.filter((n) => Number.isInteger(n) && n > 0)
          : [],
      };
    });

// Per-dispatch transient correlations (cleaned up in finally / turn.complete).
const effortByToolUseId = new Map<string, string | null>();
const spawnedToolUseIds = new Set<string>();
const seenStepTurns = new Set<string>();

export const register: Register = (on) => {
  on("session.start", async ($, e, next) => {
    const started = await next(e);
    effortByToolUseId.clear();
    spawnedToolUseIds.clear();
    seenStepTurns.clear();

    await $.tool.register({
      name: "progress",
      description:
        "Report lead orchestrator flow state to the Orchestrator live panel and above-prompt band. " +
        "Call with tasks and title to plan or re-plan, phase to transition phases, accept or return " +
        "with a 1-based task number after review, and finished: true to close.",
      inputSchema: {
        type: "object",
        properties: {
          title: {
            type: "string",
            description: "Short name of the flow.",
          },
          phase: {
            type: "string",
            enum: [...PHASES],
            description: "Current orchestration phase.",
          },
          tasks: {
            type: "array",
            description:
              "Planned tasks in order (numbered from 1). Each title must equal the Agent tool description used when dispatching.",
            items: {
              type: "object",
              properties: {
                title: { type: "string" },
                specialist: { type: "string" },
                tier: { type: "string", enum: [...TIERS] },
                after: { type: "array", items: { type: "integer" } },
              },
              required: ["title", "specialist", "tier"],
            },
          },
          accept: {
            type: "integer",
            minimum: 1,
            description: "1-based task number accepted after review.",
          },
          return: {
            type: "integer",
            minimum: 1,
            description: "1-based task number returned for rework.",
          },
          finished: {
            type: "boolean",
            description: "True to close the flow.",
          },
        },
      },
    });

    await $.tool.register({
      name: "step",
      description:
        "For worker subagents: report your own step progress (done, total, note) to the Orchestrator live panel.",
      inputSchema: {
        type: "object",
        properties: {
          done: {
            type: "integer",
            minimum: 0,
            description: "Steps completed so far.",
          },
          total: {
            type: "integer",
            minimum: 1,
            description: "Total planned steps for this task.",
          },
          note: {
            type: "string",
            description: "Short label for the current step.",
          },
        },
        required: ["done", "total"],
      },
    });

    await $.command.register({
      name: "orchestrator",
      description:
        "Show or hide the Orchestrator live panel (flow header, burn-down, task board, agents, and spend)",
    });

    $.clock.every(1000, () => {
      void (async () => {
        const f = await read($, flow);
        if (!f || !f.runs.some((r) => r.status === "running")) return;
        const at = await $.clock.now();
        await update($, now, () => at);
      })();
    });

    return started;
  });

  on("command.run", { command: "orchestrator" }, async ($) => {
    const isOpen = await togglePane($);
    return {
      text: isOpen
        ? "Orchestrator panel opened."
        : "Orchestrator panel closed.",
    };
  });

  on("tool.call", { tool: TOOL }, async ($, e) => {
    const input = e as unknown as ProgressInput;
    const at = await $.clock.now();
    const prevFlow = await read($, flow);
    const isFirstPlan = prevFlow === null && Array.isArray(input.tasks);

    const nextFlow = await update($, flow, (prev) => {
      let f = prev;
      // Apply in contract order: tasks -> phase -> accept -> return -> finished
      if (Array.isArray(input.tasks)) {
        const planEv: FlowEvent = {
          type: "plan",
          at,
          ...(input.title !== undefined ? { title: input.title } : {}),
          tasks: cleanTasks(input.tasks),
        };
        f = reduce(f, planEv);
      }
      if (
        typeof input.phase === "string" &&
        (PHASES as readonly string[]).includes(input.phase)
      ) {
        f = reduce(f, { type: "phase", at, phase: input.phase });
      }
      if (typeof input.accept === "number" && Number.isInteger(input.accept)) {
        f = reduce(f, { type: "task.accept", at, n: input.accept });
      }
      if (typeof input.return === "number" && Number.isInteger(input.return)) {
        f = reduce(f, { type: "task.return", at, n: input.return });
      }
      if (input.finished === true) {
        f = reduce(f, { type: "close", at });
      }
      return f;
    });

    await update($, now, () => at);
    if (isFirstPlan && nextFlow) {
      await autoOpen($, `${nextFlow.startedAt}:${nextFlow.title || "flow"}`);
    }

    const total = nextFlow ? nextFlow.tasks.length : 0;
    const accepted = nextFlow ? total - remaining(nextFlow) : 0;
    return { result: `flow updated: ${accepted}/${total} accepted` };
  });

  on("tool.call", { tool: STEP_TOOL }, async ($, e) => {
    const input = e as unknown as StepInput;
    const agentId = e.agentId;
    if (!agentId) {
      return { result: "ignored: only subagents report steps" };
    }
    const current = await read($, flow);
    if (!current || !current.runs.some((r) => r.id === agentId)) {
      return { result: `ignored: no matching run for agent ${agentId}` };
    }
    const at = await $.clock.now();
    await update($, flow, (prev) => {
      if (!prev) return prev;
      const existing = prev.runs.find((r) => r.id === agentId);
      if (!existing) return prev;
      const total = Math.max(
        0,
        Math.round(input.total ?? existing.steps?.total ?? 0),
      );
      const rawDone = Math.max(
        0,
        Math.round(input.done ?? existing.steps?.done ?? 0),
      );
      const done = total > 0 ? Math.min(total, rawDone) : rawDone;
      const note =
        typeof input.note === "string"
          ? input.note.trim()
          : (existing.steps?.note ?? "");
      return reduce(prev, {
        type: "run.progress",
        at,
        id: agentId,
        steps: { done, total, note },
      });
    });
    await update($, now, () => at);
    return { result: "ok" };
  });

  // Capture effort from the Agent tool call and provide a fallback run.start when
  // a test invokes $.tool.call({ tool: 'Agent', ... }) without raising agent.spawn.
  on("tool.call", { tool: "Agent" }, async ($, e, next) => {
    const corrKey = e.tool_use_id || "agent-call";
    const effort = typeof e.effort === "string" ? e.effort : null;
    effortByToolUseId.set(corrKey, effort);
    spawnedToolUseIds.delete(corrKey);
    try {
      const ran = await next(e);
      if (!spawnedToolUseIds.has(corrKey) && !("deny" in ran) && !ran.isError) {
        const at = await $.clock.now();
        const rec = ran.result as
          { agentId?: string; resolvedModel?: string } | undefined;
        const id = rec?.agentId || e.tool_use_id || `agent-${at}`;
        const model =
          rec?.resolvedModel ||
          (typeof e.model === "string" && e.model
            ? e.model
            : "claude-sonnet-5-5");
        const agent = String(e.subagent_type || "general-purpose");
        const title = String(e.description || "");
        await update($, flow, (prev) => {
          if (!prev || prev.runs.some((r) => r.id === id)) return prev;
          return reduce(prev, {
            type: "run.start",
            at,
            id,
            harness: "claude-code",
            agent,
            model,
            effort,
            title,
            role: "worker",
          });
        });
        await update($, now, () => at);
      }
      return ran;
    } finally {
      effortByToolUseId.delete(corrKey);
      spawnedToolUseIds.delete(corrKey);
    }
  });

  on("agent.spawn", async ($, e, next) => {
    const started = await next(e);
    if (started.deny !== undefined) return started;

    const corrKey = e.tool_use_id || "agent-call";
    spawnedToolUseIds.add(corrKey);
    const at = await $.clock.now();
    const id = started.agentId ?? e.tool_use_id;
    const effort = effortByToolUseId.get(corrKey) ?? null;
    const model =
      started.model || e.model || e.parentModel || "claude-sonnet-5-5";

    await update($, flow, (prev) => {
      if (!prev) return prev;
      return reduce(prev, {
        type: "run.start",
        at,
        id,
        harness: "claude-code",
        agent: e.subagentType,
        model,
        effort,
        title: e.description,
        role: "worker",
      });
    });
    await update($, now, () => at);
    return started;
  });

  on("turn.step", async function* ($, e, next) {
    const result = yield* next(e);
    const usage = result.usage;
    if (!usage) return result;

    const at = await $.clock.now();
    const isLead = !e.agentId;
    const id = e.agentId ?? "lead";
    const role = isLead ? "lead" : "worker";
    // Keep the full model id so orchestrator-core's price table matches.
    const model = usage.model || e.model;
    const effort =
      typeof e.effort === "string"
        ? e.effort
        : typeof e.effort === "number"
          ? String(e.effort)
          : null;

    seenStepTurns.add(`${id}:${e.turnId}`);

    await update($, flow, (prev) => {
      if (!prev) return prev;
      let f: Flow | null = prev;
      let existing = f.runs.find((r) => r.id === id);
      if (!existing) {
        f = reduce(f, {
          type: "run.start",
          at,
          id,
          harness: "claude-code",
          agent: isLead ? "lead" : id,
          model,
          effort,
          title: isLead ? "Lead orchestrator" : id,
          role,
        });
        existing = f?.runs.find((r) => r.id === id);
      }
      const prevTokens = existing?.tokens ?? {
        input: 0,
        output: 0,
        cacheRead: 0,
        cacheWrite: 0,
      };
      const stepIn = usage.input_tokens || 0;
      const stepOut = usage.output_tokens || 0;
      const stepRead = usage.cache_read_input_tokens || 0;
      const stepWrite = usage.cache_creation_input_tokens || 0;
      const ctxTokens = stepIn + stepOut + stepRead + stepWrite;
      const contextPct = Math.min(
        100,
        Math.round((ctxTokens / windowOf(model)) * 100),
      );

      return reduce(f, {
        type: "run.progress",
        at,
        id,
        tokens: {
          input: prevTokens.input + stepIn,
          output: prevTokens.output + stepOut,
          cacheRead: prevTokens.cacheRead + stepRead,
          cacheWrite: prevTokens.cacheWrite + stepWrite,
        },
        contextPct,
      });
    });
    await update($, now, () => at);
    return result;
  });

  on("turn.complete", async ($, e, next) => {
    const at = await $.clock.now();
    const id = e.agentId ?? "lead";
    const hadSteps = seenStepTurns.delete(`${id}:${e.turnId}`);
    const usage = e.usage;

    if (e.agentId) {
      const status = e.reason === "answer" ? "done" : "error";
      await update($, flow, (prev) => {
        if (!prev) return prev;
        const existing = prev.runs.find((r) => r.id === e.agentId);
        if (!existing) return prev;
        const prevTokens = existing.tokens;
        const tokens =
          !hadSteps && usage
            ? {
                input: prevTokens.input + (usage.input_tokens || 0),
                output: prevTokens.output + (usage.output_tokens || 0),
                cacheRead:
                  prevTokens.cacheRead + (usage.cache_read_input_tokens || 0),
                cacheWrite:
                  prevTokens.cacheWrite +
                  (usage.cache_creation_input_tokens || 0),
              }
            : undefined;
        return reduce(prev, {
          type: "run.end",
          at,
          id: e.agentId,
          status,
          ...(tokens ? { tokens } : {}),
        });
      });
      await update($, now, () => at);
    } else if (!hadSteps && usage) {
      const model = usage.model || "claude-opus-5-5";
      await update($, flow, (prev) => {
        if (!prev) return prev;
        let f: Flow | null = prev;
        let existing = f.runs.find((r) => r.id === "lead");
        if (!existing) {
          f = reduce(f, {
            type: "run.start",
            at,
            id: "lead",
            harness: "claude-code",
            agent: "lead",
            model,
            effort: null,
            title: "Lead orchestrator",
            role: "lead",
          });
          existing = f?.runs.find((r) => r.id === "lead");
        }
        const prevTokens = existing?.tokens ?? {
          input: 0,
          output: 0,
          cacheRead: 0,
          cacheWrite: 0,
        };
        return reduce(f, {
          type: "run.progress",
          at,
          id: "lead",
          tokens: {
            input: prevTokens.input + (usage.input_tokens || 0),
            output: prevTokens.output + (usage.output_tokens || 0),
            cacheRead:
              prevTokens.cacheRead + (usage.cache_read_input_tokens || 0),
            cacheWrite:
              prevTokens.cacheWrite + (usage.cache_creation_input_tokens || 0),
          },
        });
      });
      await update($, now, () => at);
    }

    return next(e);
  });

  on("ui.render", { component: "Pane", requestId: PANE }, async ($, e) => {
    const ui = $.ui.resolve(e);
    const { Box, Text, Button } = ui;
    const f = await read($, flow);
    const p: Panel = await read($, panel);
    const cols = Math.max(40, e.props.bodyColumns || 60);

    const wrapWords = (
      text: string,
      maxCols: number,
      firstIndent = "",
      restIndent = "  ",
    ): string[] => {
      const words = text.trim().split(/\s+/).filter(Boolean);
      if (words.length === 0) return [firstIndent];
      const lines: string[] = [];
      let current = firstIndent;
      let prefixLen = firstIndent.length;
      for (const w of words) {
        if (current.length === prefixLen) {
          current += w;
        } else if (current.length + 1 + w.length <= maxCols) {
          current += ` ${w}`;
        } else {
          lines.push(current);
          current = `${restIndent}${w}`;
          prefixLen = restIndent.length;
        }
      }
      if (current.length > 0) lines.push(current);
      return lines;
    };

    const wrapSegments = (
      segments: string[],
      maxCols: number,
      firstIndent = "  ",
      restIndent = "  ",
    ): string[] => {
      const clean = segments.map((s) => s.trim()).filter(Boolean);
      if (clean.length === 0) return [];
      const lines: string[] = [];
      let current = firstIndent;
      let prefixLen = firstIndent.length;
      for (const seg of clean) {
        if (current.length === prefixLen) {
          if (firstIndent.length + seg.length <= maxCols) {
            current += seg;
          } else {
            const wrapped = wrapWords(seg, maxCols, firstIndent, restIndent);
            lines.push(...wrapped.slice(0, -1));
            current = wrapped[wrapped.length - 1] ?? restIndent;
            prefixLen = restIndent.length;
          }
        } else if (current.length + 3 + seg.length <= maxCols) {
          current += ` · ${seg}`;
        } else {
          lines.push(current);
          if (restIndent.length + seg.length <= maxCols) {
            current = `${restIndent}${seg}`;
            prefixLen = restIndent.length;
          } else {
            const wrapped = wrapWords(seg, maxCols, restIndent, restIndent);
            lines.push(...wrapped.slice(0, -1));
            current = wrapped[wrapped.length - 1] ?? restIndent;
            prefixLen = restIndent.length;
          }
        }
      }
      if (current.length > prefixLen) lines.push(current);
      return lines;
    };

    if (!f) {
      return (
        <Box flexDirection="column">
          <Text dimColor>No active flow yet — this panel fills in</Text>
          <Text dimColor>when the lead skill reports a plan.</Text>
        </Box>
      );
    }

    const at = Math.max(
      await read($, now),
      f.startedAt,
      ...f.runs.map((r) => r.endedAt ?? r.startedAt),
      0,
    );
    const board: TaskBoardRow[] = taskBoard(f);
    const bd: BurnDown = burnDown(f);
    const sp: SpendSummary = spend(f);
    const total = f.tasks.length;
    const accepted = total - remaining(f);
    const phaseIdx = PHASES.indexOf(f.phase);
    const phasePillsText = PHASES.map((ph, i) => {
      const isDone = f.closedAt !== null || i < phaseIdx;
      const isCurrent = f.closedAt === null && i === phaseIdx;
      if (isCurrent) return `[${ph}]`;
      if (isDone) return `✓ ${ph}`;
      return ph;
    }).join(" · ");

    const toggleCompact = (
      <Button
        key="compact"
        label={p.isCompact ? "Expand" : "Collapse"}
        plain
        onPress={() =>
          update($, panel, (prev) => ({ ...prev, isCompact: !prev.isCompact }))
        }
      />
    );

    const spark = sparkline(bd.points, total);
    const countsTrail =
      bd.points.map((pt) => pt.remaining).join("→") || String(remaining(f));
    const replanLabel =
      bd.replans.length > 0
        ? ` · ${bd.replans.length} re-plan${bd.replans.length === 1 ? "" : "s"}`
        : "";
    const modelEntries = Object.entries(sp.byModel);
    const hasDesktopSvg = e.surface === "desktop" && "Svg" in ui;
    const W = Math.max(240, Math.min(900, (e.props.bodyColumns || 48) * 8 - 8));

    const headerTitleLines = wrapWords(
      f.title || "Orchestrator",
      Math.max(24, cols - 10),
      "",
      "  ",
    );
    const burnDownLines = wrapWords(
      `Burn-down: ${spark} (${countsTrail} remaining${replanLabel})`,
      cols,
      "",
      "  ",
    );

    const renderTaskRow = (t: TaskBoardRow) => {
      const prefix = `${STATUS_GLYPH[t.state] ?? "○"} #${t.n} `;
      const wrappedTitle = wrapWords(
        t.title,
        cols,
        " ".repeat(prefix.length),
        "  ",
      );
      const firstTitle = (wrappedTitle[0] ?? "").slice(prefix.length);
      const restTitles = wrappedTitle.slice(1);
      const metaSegments = [
        `${t.specialist} · ${t.tier}`,
        t.state,
        `round ${t.round}`,
        ...(t.waitingOn.length > 0
          ? [`waits on ${t.waitingOn.map((n) => `#${n}`).join(", ")}`]
          : []),
      ];
      const metaLines = wrapSegments(metaSegments, cols, "  ", "  ");
      return (
        <Box key={`task-${t.n}`} flexDirection="column" marginBottom={1}>
          <Text>
            <Text color={statusTermColor(t.state)}>
              {STATUS_GLYPH[t.state] ?? "○"} #{t.n}
            </Text>{" "}
            <Text bold>{firstTitle}</Text>
          </Text>
          {restTitles.map((line, i) => (
            <Text key={`task-${t.n}-title-${i}`} bold>
              {line}
            </Text>
          ))}
          {metaLines.map((line, i) => (
            <Text key={`task-${t.n}-meta-${i}`} dimColor>
              {line}
            </Text>
          ))}
        </Box>
      );
    };

    const renderAgentRow = (r: Run) => {
      const cost = runCost(r);
      const costText = cost !== null ? `est. ${fmtCost(cost)}` : "unpriced";
      const stepOrCtx =
        r.steps && r.steps.total > 0
          ? `steps ${r.steps.done}/${r.steps.total}${r.steps.note ? ` (${r.steps.note})` : ""}`
          : `ctx ${r.contextPct ?? 0}%`;
      const tokText = `${fmtTokens(runTotalTokens(r))} tok`;
      const elapsedText = fmtTime(runElapsed(r, at));
      const agentName = r.role === "lead" ? "lead" : r.agent;
      const detailLines = wrapSegments(
        [
          r.model,
          ...(r.effort ? [r.effort] : []),
          stepOrCtx,
          tokText,
          costText,
          elapsedText,
        ],
        cols,
        "  ",
        "  ",
      );
      return (
        <Box key={`run-${r.id}`} flexDirection="column" marginBottom={1}>
          {hasDesktopSvg && "Svg" in ui ? (
            <ui.Svg
              source={agentRowSvg(W, r, at)}
              alt={`${agentName} (${r.model}): ${r.status}, ${costText}`}
              width={W}
              height={58}
            />
          ) : null}
          <Text>
            <Text color={statusTermColor(r.status)}>
              {STATUS_GLYPH[r.status] ?? "●"}
            </Text>{" "}
            <Text bold>{agentName}</Text>{" "}
            <Text color={statusTermColor(r.status)}>{r.status}</Text>
          </Text>
          {detailLines.map((line, i) => (
            <Text key={`run-${r.id}-detail-${i}`} dimColor>
              {line}
            </Text>
          ))}
        </Box>
      );
    };

    const spendBreakdownLines = wrapSegments(
      [`lead est. ${fmtCost(sp.lead)}`, `workers est. ${fmtCost(sp.workers)}`],
      cols,
      "  ",
      "  ",
    );

    return (
      <Box flexDirection="column">
        {/* 1. Header */}
        {hasDesktopSvg && "Svg" in ui ? (
          <ui.Svg
            source={headerSvg(W, f, sp)}
            alt={`${f.title}: phase ${f.phase}, accepted ${accepted} of ${total}, est. ${fmtCost(sp.total)}`}
            width={W}
            height={50}
          />
        ) : null}
        <Box flexDirection="row" justifyContent="space-between">
          <Text bold>{headerTitleLines[0]}</Text>
          {toggleCompact}
        </Box>
        {headerTitleLines.slice(1).map((line, i) => (
          <Text key={`hdr-title-${i}`} bold>
            {line}
          </Text>
        ))}
        <Text dimColor>{phasePillsText}</Text>
        <Text>
          accepted {accepted} of {total} · est. {fmtCost(sp.total)}
        </Text>

        {!p.isCompact && (
          <Box flexDirection="column" marginTop={1}>
            {/* 2. Burn-down */}
            {burnDownLines.map((line, i) => (
              <Text key={`bd-${i}`} bold>
                {line}
              </Text>
            ))}
            {hasDesktopSvg && "Svg" in ui ? (
              <ui.Svg
                source={burnDownSvg(W, bd, total)}
                alt={`Burn-down: ${countsTrail} remaining${replanLabel}`}
                width={W}
                height={76}
              />
            ) : null}

            {/* 3. Task board */}
            <Box flexDirection="column" marginTop={1}>
              <Text bold>
                Task board ({accepted} of {total} accepted)
              </Text>
              {board.length === 0 ? (
                <Text dimColor>No tasks planned yet.</Text>
              ) : (
                board.map(renderTaskRow)
              )}
            </Box>

            {/* 4. Agents */}
            <Box flexDirection="column" marginTop={1}>
              <Text bold>Agents ({f.runs.length})</Text>
              {f.runs.length === 0 ? (
                <Text dimColor>No runs recorded yet.</Text>
              ) : (
                f.runs.map(renderAgentRow)
              )}
            </Box>

            {/* 5. Spend */}
            <Box flexDirection="column" marginTop={1}>
              <Text bold>Spend: est. {fmtCost(sp.total)}</Text>
              {spendBreakdownLines.map((line, i) => (
                <Text key={`spend-role-${i}`} dimColor>
                  {line}
                </Text>
              ))}
              {modelEntries.length > 0 ? (
                modelEntries.flatMap(([m, cost]) =>
                  wrapWords(
                    `${m}: est. ${fmtCost(cost)}`,
                    cols,
                    "  ",
                    "    ",
                  ).map((line, i) => (
                    <Text key={`spend-${m}-${i}`} dimColor>
                      {line}
                    </Text>
                  )),
                )
              ) : (
                <Text dimColor>{"  "}No priced model spend yet.</Text>
              )}
              {sp.unpriced.runs > 0 &&
                wrapWords(
                  `unpriced (${sp.unpriced.runs} ${sp.unpriced.runs === 1 ? "run" : "runs"}): ${fmtTokens(sp.unpriced.tokens)} tokens`,
                  cols,
                  "  ",
                  "    ",
                ).map((line, i) => (
                  <Text key={`spend-unpriced-${i}`} dimColor>
                    {line}
                  </Text>
                ))}
            </Box>
          </Box>
        )}
      </Box>
    );
  });

  on("ui.render", { component: "AbovePrompt" }, async ($, e, next) => {
    const f = await read($, flow);
    if (f === null || e.props.hasSurvey) return next(e);

    const ui = $.ui.resolve(e);
    const { Box, Text, Button } = ui;
    const total = f.tasks.length;
    const accepted = total - remaining(f);
    const unstarted = f.tasks.filter(
      (t) => t.state === "waiting" || t.state === "ready",
    ).length;
    const crew = f.runs.length + unstarted;
    const isWorking = f.runs.some((r) => r.status === "running");
    const ratioVal = f.closedAt !== null ? 1 : total > 0 ? accepted / total : 0;

    const crewButton = (
      <Button
        key="orchestrator-crew"
        label={`×${crew}`}
        plain
        onPress={() => void togglePane($)}
      />
    );
    const dismiss = (
      <Button
        key="orchestrator-dismiss"
        label="✕"
        plain
        role="dismiss"
        onPress={() => update($, flow, () => null)}
      />
    );

    if (e.surface === "desktop" && "Svg" in ui) {
      const { Svg } = ui;
      const width = Math.max(
        180,
        Math.min(1600, (e.props.bodyColumns || 100) * 8 - 96),
      );
      return (
        <Box flexDirection="row" alignItems="center" gap={1}>
          <Svg
            source={bandSvg(f, width, isWorking)}
            alt={`${f.title} · ${f.phase} · ${accepted} of ${total} accepted`}
            width={width}
            height={H}
          />
          <Text dimColor>
            {f.title} · {f.phase} · {accepted} of {total} accepted
          </Text>
          {crewButton}
          {dismiss}
        </Box>
      );
    }

    const cols = Math.max(40, e.props.bodyColumns || 80);
    const textBudget = Math.max(28, cols - 10);
    const barW = Math.max(6, Math.min(14, Math.floor(textBudget / 6)));
    const statusLine = `${barText(ratioVal, barW)} · ${f.phase} · ${accepted} of ${total} accepted`;
    const oneLine = `● ${f.title} · ${statusLine}`;
    const tone = f.closedAt !== null ? "green" : "blue";

    if (oneLine.length <= textBudget) {
      return (
        <Box flexDirection="row" justifyContent="space-between" gap={1}>
          <Text>
            <Text color={tone}>● {f.title}</Text>{" "}
            <Text color={tone}>{barText(ratioVal, barW)}</Text>{" "}
            <Text bold>{f.phase}</Text>{" "}
            <Text dimColor>
              {accepted} of {total} accepted
            </Text>
          </Text>
          <Box flexDirection="row" gap={1}>
            {crewButton}
            {dismiss}
          </Box>
        </Box>
      );
    }

    const titleWords = f.title.trim().split(/\s+/).filter(Boolean);
    const titleLines: string[] = [];
    let cur = "●";
    for (const w of titleWords) {
      if (cur === "●") {
        cur = `● ${w}`;
      } else if (cur.length + 1 + w.length <= textBudget) {
        cur += ` ${w}`;
      } else {
        titleLines.push(cur);
        cur = `  ${w}`;
      }
    }
    if (cur.length > 0) titleLines.push(cur);

    return (
      <Box flexDirection="row" justifyContent="space-between" gap={1}>
        <Box flexDirection="column">
          {titleLines.map((line, i) => (
            <Text key={`band-title-${i}`} color={tone}>
              {line}
            </Text>
          ))}
          <Text>
            {"  "}
            <Text color={tone}>{barText(ratioVal, barW)}</Text>{" "}
            <Text bold>{f.phase}</Text>{" "}
            <Text dimColor>
              {accepted} of {total} accepted
            </Text>
          </Text>
        </Box>
        <Box flexDirection="row" gap={1}>
          {crewButton}
          {dismiss}
        </Box>
      </Box>
    );
  });
};
