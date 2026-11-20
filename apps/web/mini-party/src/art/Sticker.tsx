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
 */

import { useId, type CSSProperties, type ReactNode } from "react";
import { GAME_STICKERS } from "../games/catalog";

// One sticker per mini-game: flat, chunky emblems in the brand palette with a
// white die-cut border and a hard ink shadow. Drawn in a 120 x 120 box. The
// border comes from one SVG filter that grows each shape's outline, so every
// emblem gets the same edge without drawing it twice.

const INK = "#0F0C29";
const PINK = "#FF0080";
const CYAN = "#00F2FF";
const GREEN = "#4ECCA3";
const GOLD = "#FFD700";
const RED = "#FF4D4D";
const BLUE = "#4D79FF";
const YELLOW = "#FFD93D";
const MINT = "#6BCB77";
const WHITE = "#FFFFFF";

const art: Record<string, ReactNode> = {
  // ZAP! — react the instant it flashes.
  reaction: (
    <polygon points="68,6 22,68 54,68 44,114 98,46 64,46 78,6" fill={GOLD} />
  ),
  // BOOST! — mash your button.
  mash: (
    <>
      <ellipse cx="60" cy="88" rx="48" ry="18" fill={CYAN} />
      <path d="M26 66 v16 a34 16 0 0 0 68 0 v-16 z" fill="#B8005C" />
      <ellipse cx="60" cy="66" rx="34" ry="16" fill={PINK} />
      <ellipse cx="50" cy="61" rx="10" ry="4" fill={WHITE} stroke="none" />
      <path
        d="M60 12 v16 M30 22 l9 12 M90 22 l-9 12"
        stroke={GOLD}
        strokeWidth="7"
        strokeLinecap="round"
        fill="none"
      />
    </>
  ),
  // ECHO! — repeat the sequence.
  pattern: (
    <>
      <rect x="10" y="10" width="47" height="47" rx="12" fill={RED} />
      <rect x="63" y="10" width="47" height="47" rx="12" fill={BLUE} />
      <rect x="10" y="63" width="47" height="47" rx="12" fill={YELLOW} />
      <rect x="63" y="63" width="47" height="47" rx="12" fill={MINT} />
      <circle cx="33" cy="33" r="7" fill={WHITE} stroke="none" opacity="0.8" />
    </>
  ),
  // PINPOINT! — stop it on the mark.
  stop: (
    <>
      <rect x="50" y="8" width="20" height="14" rx="4" fill={PINK} />
      <rect
        x="86"
        y="24"
        width="14"
        height="10"
        rx="3"
        fill={PINK}
        transform="rotate(40 93 29)"
      />
      <circle cx="60" cy="68" r="44" fill={CYAN} />
      <circle cx="60" cy="68" r="33" fill={WHITE} />
      <path
        d="M60 68 L60 42"
        stroke={INK}
        strokeWidth="7"
        strokeLinecap="round"
      />
      <path
        d="M60 68 L78 78"
        stroke={PINK}
        strokeWidth="6"
        strokeLinecap="round"
      />
      <circle cx="60" cy="68" r="5" fill={INK} />
    </>
  ),
  // GLANCE! — count at a glance.
  count: (
    <>
      <path d="M6 60 Q60 4 114 60 Q60 116 6 60 Z" fill={WHITE} />
      <circle cx="60" cy="60" r="25" fill={GREEN} />
      <circle cx="60" cy="60" r="12" fill={INK} />
      <circle cx="53" cy="53" r="5" fill={WHITE} stroke="none" />
    </>
  ),
  // SNIPE! — hit the target.
  target: (
    <>
      <circle cx="60" cy="60" r="48" fill={WHITE} />
      <circle cx="60" cy="60" r="36" fill={PINK} />
      <circle cx="60" cy="60" r="24" fill={WHITE} />
      <circle cx="60" cy="60" r="11" fill={PINK} />
      <path
        d="M60 2 v22 M60 96 v22 M2 60 h22 M96 60 h22"
        stroke={INK}
        strokeWidth="6"
        strokeLinecap="round"
      />
    </>
  ),
  // TUG! — pull the rope your way.
  tug: (
    <>
      <path
        d="M10 74 C 38 48, 82 98, 110 64"
        stroke={GOLD}
        strokeWidth="22"
        strokeLinecap="round"
        fill="none"
      />
      <path
        d="M10 74 C 38 48, 82 98, 110 64"
        stroke="#C99A00"
        strokeWidth="4"
        strokeDasharray="3 11"
        strokeLinecap="round"
        fill="none"
      />
      <path d="M60 72 L60 28 L92 40 L60 52" fill={PINK} />
      <circle cx="12" cy="74" r="14" fill={RED} />
      <circle cx="108" cy="64" r="14" fill={BLUE} />
    </>
  ),
  // STABLE! — keep the bubble centred.
  balance: (
    <>
      <rect x="6" y="40" width="108" height="40" rx="20" fill={GREEN} />
      <rect x="22" y="50" width="76" height="20" rx="10" fill={WHITE} />
      <path d="M48 50 v20 M72 50 v20" stroke={INK} strokeWidth="3" />
      <circle cx="60" cy="60" r="8" fill={CYAN} />
    </>
  ),
  // COLOR! — match the colour.
  match: (
    <>
      <rect
        x="43"
        y="14"
        width="34"
        height="86"
        rx="10"
        fill={BLUE}
        transform="rotate(-24 60 104)"
      />
      <rect
        x="43"
        y="14"
        width="34"
        height="86"
        rx="10"
        fill={GOLD}
        transform="rotate(0 60 104)"
      />
      <rect
        x="43"
        y="14"
        width="34"
        height="86"
        rx="10"
        fill={PINK}
        transform="rotate(24 60 104)"
      />
      <circle cx="60" cy="96" r="5" fill={WHITE} />
    </>
  ),
  // PUMP! — fill it up, but don't burst it.
  fuel: (
    <>
      <path
        d="M60 92 C 62 104, 50 106, 56 118"
        stroke={WHITE}
        strokeWidth="3"
        fill="none"
      />
      <ellipse cx="60" cy="48" rx="36" ry="42" fill={PINK} />
      <path d="M52 96 L60 86 L68 96 Z" fill={PINK} />
      <ellipse
        cx="46"
        cy="32"
        rx="8"
        ry="13"
        fill={WHITE}
        stroke="none"
        opacity="0.85"
        transform="rotate(-25 46 32)"
      />
    </>
  ),
  // SEARCH! — find the odd one out.
  scan: (
    <>
      <path
        d="M74 74 L106 106"
        stroke={INK}
        strokeWidth="16"
        strokeLinecap="round"
      />
      <path
        d="M74 74 L106 106"
        stroke={GOLD}
        strokeWidth="8"
        strokeLinecap="round"
      />
      <circle cx="50" cy="50" r="36" fill={BLUE} />
      <circle cx="50" cy="50" r="25" fill="#E6FBFF" />
      <path
        d="M38 40 a16 16 0 0 1 14 -8"
        stroke={WHITE}
        strokeWidth="6"
        strokeLinecap="round"
        fill="none"
      />
    </>
  ),
  // AVOID! — switch lanes, dodge what falls.
  dodge: (
    <>
      <path
        d="M100 6 L72 32 M114 22 L86 46 M84 2 L62 22"
        stroke={GOLD}
        strokeWidth="7"
        strokeLinecap="round"
      />
      <circle cx="58" cy="46" r="22" fill={PINK} />
      <circle cx="51" cy="42" r="5" fill="#B8005C" />
      <circle cx="64" cy="53" r="4" fill="#B8005C" />
      <rect x="16" y="82" width="38" height="28" rx="8" fill={GREEN} />
      <path
        d="M62 96 h40 M88 86 l14 10 -14 10"
        stroke={CYAN}
        strokeWidth="8"
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
    </>
  ),
  // SMASH! — hammer it.
  smash: (
    <>
      <rect
        x="54"
        y="44"
        width="16"
        height="70"
        rx="7"
        fill={GOLD}
        transform="rotate(-24 62 79)"
      />
      <rect
        x="18"
        y="14"
        width="76"
        height="38"
        rx="9"
        fill={BLUE}
        transform="rotate(-24 56 33)"
      />
      <rect
        x="18"
        y="14"
        width="18"
        height="38"
        rx="5"
        fill="#2F55D4"
        transform="rotate(-24 56 33)"
      />
      <path
        d="M92 96 l10 -6 M98 108 l12 0 M84 106 l-2 10"
        stroke={PINK}
        strokeWidth="6"
        strokeLinecap="round"
      />
    </>
  ),
};

export const STICKER_IDS = [...Object.keys(art), ...Object.keys(GAME_STICKERS)];

interface StickerProps {
  id: string;
  className?: string;
  // Draw the white die-cut border and shadow. Off for faint background use.
  diecut?: boolean;
  title?: string;
  style?: CSSProperties;
}

export function Sticker({
  id,
  className,
  diecut = true,
  title,
  style,
}: StickerProps) {
  const filterId = `sticker-${useId().replace(/:/g, "")}`;
  const shape = art[id] ?? GAME_STICKERS[id];
  if (!shape) return null;
  return (
    <svg
      viewBox="-12 -12 144 144"
      className={className}
      style={style}
      role={title ? "img" : undefined}
      aria-hidden={title ? undefined : true}
    >
      {title && <title>{title}</title>}
      {diecut && (
        <defs>
          <filter id={filterId} x="-20%" y="-20%" width="140%" height="140%">
            <feMorphology
              in="SourceAlpha"
              operator="dilate"
              radius="6"
              result="edge"
            />
            <feOffset in="edge" dx="5" dy="7" result="drop" />
            <feFlood floodColor={INK} floodOpacity="0.55" />
            <feComposite in2="drop" operator="in" result="shadow" />
            <feFlood floodColor={WHITE} />
            <feComposite in2="edge" operator="in" result="border" />
            <feMerge>
              <feMergeNode in="shadow" />
              <feMergeNode in="border" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>
      )}
      <g
        filter={diecut ? `url(#${filterId})` : undefined}
        stroke={INK}
        strokeWidth="3"
        strokeLinejoin="round"
      >
        {shape}
      </g>
    </svg>
  );
}
