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
import * as React from "react";
import { RegistrationMarks } from "./Plate.js";

export type VitruvianPlateVariant =
  | "proportion"
  | "spaces"
  | "tabs"
  | "resources"
  | "topology"
  | "telemetry"
  | "security"
  | "harmonic";

export interface VitruvianPlateProps extends React.SVGProps<SVGSVGElement> {
  /** Which technical drawing plate to render. */
  variant?: VitruvianPlateVariant;
  /** Width/height of the square or 4:3 plate in px (default 160). */
  size?: number;
}

/**
 * Codex-inspired technical vector plates drawn on a 160x120 drafting grid.
 * Uses CSS custom properties (`--color-accent-text`, `--color-sanguine-text`,
 * `--color-divider`, `--color-text-dim`) so every plate adapts automatically
 * between dark (`Board`) and light (`Parchment`) grounds.
 */
export const VitruvianPlate = React.forwardRef<
  SVGSVGElement,
  VitruvianPlateProps
>(function VitruvianPlate(
  { variant = "proportion", size = 160, style, ...rest },
  ref,
) {
  const height = Math.round((size * 3) / 4);
  return (
    <svg
      ref={ref}
      width={size}
      height={height}
      viewBox="0 0 160 120"
      fill="none"
      aria-hidden={rest["aria-label"] ? undefined : "true"}
      style={{ display: "block", ...style }}
      {...rest}
    >
      {/* Subtle construction crosshairs at plate centre */}
      <line
        x1="0"
        y1="60"
        x2="160"
        y2="60"
        stroke="var(--color-line)"
        strokeWidth="1"
      />
      <line
        x1="80"
        y1="0"
        x2="80"
        y2="120"
        stroke="var(--color-line)"
        strokeWidth="1"
      />

      {variant === "proportion" && (
        <g>
          {/* Inscribed square and circle — Leonardo's Vitruvian geometry */}
          <rect
            x="40"
            y="20"
            width="80"
            height="80"
            stroke="var(--color-accent-text)"
            strokeWidth="1.25"
          />
          <circle
            cx="80"
            cy="60"
            r="40"
            stroke="var(--color-accent-text)"
            strokeWidth="1.25"
          />
          <circle
            cx="80"
            cy="60"
            r="24.7"
            stroke="var(--color-divider)"
            strokeWidth="1"
            strokeDasharray="2 2"
          />
          <line
            x1="40"
            y1="20"
            x2="120"
            y2="100"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          <line
            x1="120"
            y1="20"
            x2="40"
            y2="100"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          {/* Sanguine golden-section datum line */}
          <line
            x1="32"
            y1="49.4"
            x2="128"
            y2="49.4"
            stroke="var(--color-sanguine-text)"
            strokeWidth="1"
          />
          {/* Golden-Datum V: raised arms (upper intersections) to grounded feet */}
          <path
            d="M46 26L80 100L114 26"
            stroke="var(--color-accent-text)"
            strokeWidth="1.75"
            strokeLinecap="square"
            strokeLinejoin="miter"
          />
          <circle cx="80" cy="49.4" r="2.5" fill="var(--color-sanguine-text)" />
          <circle cx="80" cy="60" r="2" fill="var(--color-accent-text)" />
        </g>
      )}

      {variant === "spaces" && (
        <g>
          {/* Architectural workspace plan — partitioned bays */}
          <rect
            x="26"
            y="18"
            width="108"
            height="84"
            stroke="var(--color-accent-text)"
            strokeWidth="1.25"
          />
          <line
            x1="68"
            y1="18"
            x2="68"
            y2="102"
            stroke="var(--color-accent-text)"
            strokeWidth="1"
          />
          <line
            x1="68"
            y1="52"
            x2="134"
            y2="52"
            stroke="var(--color-accent-text)"
            strokeWidth="1"
          />
          <rect
            x="34"
            y="26"
            width="26"
            height="18"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          <rect
            x="34"
            y="50"
            width="26"
            height="44"
            stroke="var(--color-divider)"
            strokeWidth="1"
            strokeDasharray="3 2"
          />
          <circle
            cx="101"
            cy="77"
            r="14"
            stroke="var(--color-sanguine-text)"
            strokeWidth="1"
          />
          <path
            d="M97 77h8M101 73v8"
            stroke="var(--color-sanguine-text)"
            strokeWidth="1.2"
          />
        </g>
      )}

      {variant === "tabs" && (
        <g>
          {/* Three layered drafting plates in orthographic offset */}
          <rect
            x="44"
            y="16"
            width="84"
            height="60"
            stroke="var(--color-divider)"
            strokeWidth="1"
            fill="var(--color-bg)"
          />
          <rect
            x="36"
            y="26"
            width="84"
            height="60"
            stroke="var(--color-divider)"
            strokeWidth="1"
            fill="var(--color-bg)"
          />
          <rect
            x="28"
            y="36"
            width="84"
            height="60"
            stroke="var(--color-accent-text)"
            strokeWidth="1.25"
            fill="var(--color-surface)"
          />
          <line
            x1="28"
            y1="48"
            x2="112"
            y2="48"
            stroke="var(--color-accent-text)"
            strokeWidth="1"
          />
          <rect
            x="34"
            y="40"
            width="4"
            height="4"
            fill="var(--color-sanguine-text)"
          />
          <line
            x1="38"
            y1="60"
            x2="92"
            y2="60"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          <line
            x1="38"
            y1="70"
            x2="100"
            y2="70"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          <line
            x1="38"
            y1="80"
            x2="76"
            y2="80"
            stroke="var(--color-accent-text)"
            strokeWidth="1"
          />
        </g>
      )}

      {variant === "resources" && (
        <g>
          {/* Catalog index matrix with compass divider */}
          <rect
            x="28"
            y="20"
            width="104"
            height="80"
            stroke="var(--color-accent-text)"
            strokeWidth="1.25"
          />
          <line
            x1="28"
            y1="38"
            x2="132"
            y2="38"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          <line
            x1="28"
            y1="58"
            x2="132"
            y2="58"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          <line
            x1="28"
            y1="78"
            x2="132"
            y2="78"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          <line
            x1="54"
            y1="20"
            x2="54"
            y2="100"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          <circle
            cx="41"
            cy="29"
            r="3"
            stroke="var(--color-accent-text)"
            strokeWidth="1"
          />
          <rect
            x="38"
            y="45"
            width="6"
            height="6"
            stroke="var(--color-sanguine-text)"
            strokeWidth="1"
          />
          <circle
            cx="41"
            cy="68"
            r="3"
            stroke="var(--color-accent-text)"
            strokeWidth="1"
          />
          <line
            x1="64"
            y1="29"
            x2="116"
            y2="29"
            stroke="var(--color-accent-text)"
            strokeWidth="1.25"
          />
          <line
            x1="64"
            y1="48"
            x2="104"
            y2="48"
            stroke="var(--color-sanguine-text)"
            strokeWidth="1.25"
          />
          <line
            x1="64"
            y1="68"
            x2="120"
            y2="68"
            stroke="var(--color-divider)"
            strokeWidth="1.25"
          />
        </g>
      )}

      {variant === "topology" && (
        <g>
          {/* Distributed cluster triad & mesh links */}
          <line
            x1="80"
            y1="24"
            x2="38"
            y2="88"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          <line
            x1="80"
            y1="24"
            x2="122"
            y2="88"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          <line
            x1="38"
            y1="88"
            x2="122"
            y2="88"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          <line
            x1="80"
            y1="24"
            x2="80"
            y2="64"
            stroke="var(--color-accent-text)"
            strokeWidth="1.2"
          />
          <line
            x1="38"
            y1="88"
            x2="80"
            y2="64"
            stroke="var(--color-accent-text)"
            strokeWidth="1.2"
          />
          <line
            x1="122"
            y1="88"
            x2="80"
            y2="64"
            stroke="var(--color-sanguine-text)"
            strokeWidth="1.2"
            strokeDasharray="3 2"
          />
          {/* Control hub */}
          <rect
            x="72"
            y="56"
            width="16"
            height="16"
            fill="var(--color-surface)"
            stroke="var(--color-accent-text)"
            strokeWidth="1.5"
          />
          <circle cx="80" cy="64" r="4" stroke="var(--color-accent-text)" />
          {/* Perimeter nodes */}
          <rect
            x="73"
            y="17"
            width="14"
            height="14"
            fill="var(--color-surface)"
            stroke="var(--color-accent-text)"
            strokeWidth="1.25"
          />
          <rect
            x="31"
            y="81"
            width="14"
            height="14"
            fill="var(--color-surface)"
            stroke="var(--color-accent-text)"
            strokeWidth="1.25"
          />
          <rect
            x="115"
            y="81"
            width="14"
            height="14"
            fill="var(--color-surface)"
            stroke="var(--color-sanguine-text)"
            strokeWidth="1.25"
          />
        </g>
      )}

      {variant === "telemetry" && (
        <g>
          {/* Polar azimuth / orbital radar reticle */}
          <circle
            cx="80"
            cy="60"
            r="44"
            stroke="var(--color-accent-text)"
            strokeWidth="1.25"
          />
          <circle
            cx="80"
            cy="60"
            r="30"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          <circle
            cx="80"
            cy="60"
            r="15"
            stroke="var(--color-divider)"
            strokeWidth="1"
            strokeDasharray="2 2"
          />
          {/* Azimuth sweep vector */}
          <line
            x1="80"
            y1="60"
            x2="111"
            y2="29"
            stroke="var(--color-accent-text)"
            strokeWidth="1.5"
          />
          {/* Orbital track */}
          <ellipse
            cx="80"
            cy="60"
            rx="48"
            ry="18"
            transform="rotate(-22 80 60)"
            stroke="var(--color-sanguine-text)"
            strokeWidth="1"
          />
          <rect
            x="108"
            y="26"
            width="6"
            height="6"
            fill="var(--color-sanguine-text)"
          />
        </g>
      )}

      {variant === "security" && (
        <g>
          {/* Cryptographic seal & key bit */}
          <polygon
            points="80,16 118,38 118,82 80,104 42,82 42,38"
            stroke="var(--color-accent-text)"
            strokeWidth="1.25"
            fill="var(--color-surface)"
          />
          <rect
            x="62"
            y="42"
            width="36"
            height="36"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          <circle
            cx="80"
            cy="55"
            r="7"
            stroke="var(--color-accent-text)"
            strokeWidth="1.5"
          />
          <path
            d="M80 62v12M80 68h5M80 72h3"
            stroke="var(--color-sanguine-text)"
            strokeWidth="1.5"
          />
        </g>
      )}

      {variant === "harmonic" && (
        <g>
          {/* Acoustic standing-wave interferogram */}
          <rect
            x="20"
            y="24"
            width="120"
            height="72"
            stroke="var(--color-divider)"
            strokeWidth="1"
          />
          <path
            d="M 20 60 Q 50 18, 80 60 T 140 60"
            stroke="var(--color-accent-text)"
            strokeWidth="1.5"
            fill="none"
          />
          <path
            d="M 20 60 Q 50 102, 80 60 T 140 60"
            stroke="var(--color-divider)"
            strokeWidth="1"
            strokeDasharray="3 2"
            fill="none"
          />
          <path
            d="M 20 60 C 40 36, 60 84, 80 60 C 100 36, 120 84, 140 60"
            stroke="var(--color-sanguine-text)"
            strokeWidth="1.2"
            fill="none"
          />
          <circle cx="50" cy="39" r="2.5" fill="var(--color-accent-text)" />
          <circle cx="80" cy="60" r="2.5" fill="var(--color-sanguine-text)" />
          <circle cx="110" cy="81" r="2.5" fill="var(--color-accent-text)" />
        </g>
      )}
    </svg>
  );
});

export interface PlateFigureProps extends React.HTMLAttributes<HTMLElement> {
  /** Plate variant to render when no custom `children` are passed. */
  variant?: VitruvianPlateVariant;
  /** Left caption annotation (e.g. `"FIG. 04 // CLUSTER TOPOLOGY"`). */
  figureLabel?: React.ReactNode;
  /** Right caption annotation (e.g. `"SCALE 1:1"`). */
  meta?: React.ReactNode;
  /** Whether to render `.grid-field` graph-paper background inside the canvas. */
  grid?: boolean;
  /** Whether to render the four registration marks at the canvas corners. */
  corners?: boolean;
  /** Size of the default `VitruvianPlate` in px. */
  size?: number;
}

/**
 * Framed technical figure with registration corners, optional ruled graph-paper
 * ground, and a mono draughtsman caption bar.
 */
export const PlateFigure = React.forwardRef<HTMLElement, PlateFigureProps>(
  function PlateFigure(
    {
      variant = "proportion",
      figureLabel,
      meta,
      grid = true,
      corners = true,
      size = 180,
      className,
      children,
      ...rest
    },
    ref,
  ) {
    const cls = ["plate-figure", className].filter(Boolean).join(" ");
    const canvasCls = ["plate-canvas", corners && "plate", grid && "grid-field"]
      .filter(Boolean)
      .join(" ");

    return (
      <figure ref={ref} className={cls} {...rest}>
        <div className={canvasCls}>
          {corners && <RegistrationMarks />}
          {children ?? <VitruvianPlate variant={variant} size={size} />}
        </div>
        {(figureLabel != null || meta != null) && (
          <figcaption className="plate-caption">
            <span>{figureLabel}</span>
            {meta != null && <span>{meta}</span>}
          </figcaption>
        )}
      </figure>
    );
  },
);

/**
 * Self-contained SVG data-URI stock plates for `.duotone` screen-print
 * demonstrations, hero cards, and empty-state backgrounds — zero external
 * network dependencies.
 */
export const VitruvianStockImages = {
  /** Topographic elevation contour lines with survey datum grid. */
  TOPOGRAPHY:
    "data:image/svg+xml;utf8," +
    encodeURIComponent(
      `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360" viewBox="0 0 640 360">
        <rect width="640" height="360" fill="#182026"/>
        <g stroke="#d8e4ee" stroke-width="1.2" fill="none" opacity="0.55">
          <ellipse cx="320" cy="180" rx="280" ry="140"/>
          <ellipse cx="325" cy="176" rx="230" ry="112"/>
          <ellipse cx="332" cy="172" rx="180" ry="86"/>
          <ellipse cx="340" cy="168" rx="130" ry="60"/>
          <ellipse cx="348" cy="164" rx="82" ry="38"/>
          <ellipse cx="354" cy="160" rx="38" ry="18"/>
          <line x1="0" y1="180" x2="640" y2="180" stroke-dasharray="4 4" opacity="0.5"/>
          <line x1="320" y1="0" x2="320" y2="360" stroke-dasharray="4 4" opacity="0.5"/>
        </g>
      </svg>`,
    ),
  /** Armillary sphere / celestial mechanics study. */
  ARMILLARY:
    "data:image/svg+xml;utf8," +
    encodeURIComponent(
      `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360" viewBox="0 0 640 360">
        <rect width="640" height="360" fill="#141b20"/>
        <g stroke="#e7e4dd" stroke-width="1.25" fill="none" opacity="0.65">
          <circle cx="320" cy="180" r="135"/>
          <circle cx="320" cy="180" r="105"/>
          <ellipse cx="320" cy="180" rx="135" ry="48" transform="rotate(-23.5 320 180)"/>
          <ellipse cx="320" cy="180" rx="135" ry="48" transform="rotate(23.5 320 180)"/>
          <ellipse cx="320" cy="180" rx="48" ry="135"/>
          <line x1="150" y1="180" x2="490" y2="180"/>
          <line x1="320" y1="20" x2="320" y2="340"/>
        </g>
      </svg>`,
    ),
  /** Architectural perspective colonnade & proportional grid. */
  PERSPECTIVE:
    "data:image/svg+xml;utf8," +
    encodeURIComponent(
      `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360" viewBox="0 0 640 360">
        <rect width="640" height="360" fill="#161d22"/>
        <g stroke="#d8e4ee" stroke-width="1" fill="none" opacity="0.6">
          <rect x="220" y="110" width="200" height="140"/>
          <rect x="140" y="65" width="360" height="230"/>
          <line x1="0" y1="0" x2="320" y2="180"/>
          <line x1="640" y1="0" x2="320" y2="180"/>
          <line x1="0" y1="360" x2="320" y2="180"/>
          <line x1="640" y1="360" x2="320" y2="180"/>
          <line x1="0" y1="180" x2="640" y2="180"/>
          <circle cx="320" cy="180" r="56"/>
        </g>
      </svg>`,
    ),
} as const;

export interface DuotoneImageProps extends React.ImgHTMLAttributes<HTMLImageElement> {
  /** Optional caption rendered in a `<figcaption>` below the plate. */
  caption?: React.ReactNode;
  /** Whether to frame the image as a `.plate` with corner registration marks (default true). */
  plate?: boolean;
}

/**
 * Desaturated, high-contrast screen-print image washed into the brand steel
 * (`.duotone`). Pairs with `VitruvianStockImages` or any photographic source.
 */
export const DuotoneImage = React.forwardRef<
  HTMLImageElement,
  DuotoneImageProps
>(function DuotoneImage(
  { caption, plate = true, className, alt = "", ...rest },
  ref,
) {
  const wrapCls = ["duotone", plate && "plate", className]
    .filter(Boolean)
    .join(" ");

  return (
    <figure>
      <div className={wrapCls}>
        {plate && <RegistrationMarks />}
        <img ref={ref} alt={alt} {...rest} />
      </div>
      {caption != null && <figcaption>{caption}</figcaption>}
    </figure>
  );
});
