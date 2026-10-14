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
import { cn } from "./cn.js";

/** The four crosshair registration marks. Never used without a .plate parent. */
export function RegistrationMarks() {
  return (
    <>
      <i className="corner tl" />
      <i className="corner tr" />
      <i className="corner bl" />
      <i className="corner br" />
    </>
  );
}

export interface PlateProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Draw the crosshair marks. Off only for containers that are not objects. */
  marks?: boolean;
  /** Rule the ground like graph paper. */
  field?: false | "sm" | "lg";
  /** Marks sit dim until hover or focus-within, then snap sharp. */
  live?: boolean;
  /** Marks draw themselves in clockwise on mount. Once per view. */
  enter?: boolean;
  as?: "div" | "section" | "article" | "aside";
  className?: string;
  children?: React.ReactNode;
}

/**
 * A plate is the system's frame: square corners, one hairline, transparent
 * ground, four registration marks. Every card, figure and panel is one.
 */
export function Plate({
  marks = true,
  field = false,
  live,
  enter,
  as = "div",
  className,
  children,
  ...rest
}: PlateProps) {
  const Tag = as;
  return (
    <Tag
      className={cn(
        "plate",
        live && "plate-live",
        enter && "plate-enter",
        field === "sm" && "grid-field",
        field === "lg" && "grid-field-lg",
        className,
      )}
      {...rest}
    >
      {marks ? <RegistrationMarks /> : null}
      {children}
    </Tag>
  );
}

export interface VMarkProps extends React.HTMLAttributes<HTMLSpanElement> {
  size?: number;
  /** Render outer corner registration brackets (default: auto when size >= 28). */
  brackets?: boolean;
  /** Render the sanguine navel pivot dot (default: auto when size >= 20). */
  pivot?: boolean;
}

/**
 * Circle inscribed in a square with the Golden-Datum "V" — the Vitruvian
 * figure's raised-arm and grounded-foot geometry (Option A official brand mark).
 */
export function VMark({
  size = 16,
  brackets,
  pivot,
  className,
  style,
  ...rest
}: VMarkProps) {
  const showBrackets = brackets ?? size >= 28;
  const showPivot = pivot ?? size >= 20;
  return (
    <span
      className={cn(
        "inline-flex items-center justify-center shrink-0",
        className,
      )}
      style={{ width: size, height: size, ...style }}
      aria-hidden
      {...rest}
    >
      <svg
        width={size}
        height={size}
        viewBox="0 0 32 32"
        fill="none"
        style={{ display: "block", width: "100%", height: "100%" }}
      >
        {showBrackets && (
          <path
            d="M2 7V2h5M25 2h5v5M30 25v5h-5M7 30H2v-5"
            stroke="currentColor"
            strokeWidth="1.25"
            strokeOpacity="0.55"
          />
        )}
        <rect
          x="6.5"
          y="6.5"
          width="19"
          height="19"
          stroke="currentColor"
          strokeWidth={size < 20 ? "1.6" : "1.25"}
          strokeOpacity="0.55"
        />
        <circle
          cx="16"
          cy="16"
          r="12.5"
          stroke="currentColor"
          strokeWidth={size < 20 ? "1.8" : "1.5"}
        />
        <line
          x1="6.5"
          y1="12.5"
          x2="25.5"
          y2="12.5"
          stroke="currentColor"
          strokeWidth="1.1"
          strokeOpacity="0.55"
        />
        <path
          d="M8 8L16 26.5L24 8"
          stroke="currentColor"
          strokeWidth={size < 20 ? "2.4" : "2"}
          strokeLinecap="square"
          strokeLinejoin="miter"
        />
        {showPivot && (
          <circle cx="16" cy="16" r="1.6" fill="var(--color-sanguine-text)" />
        )}
      </svg>
    </span>
  );
}

/** Standalone official vector brand mark (Option A Golden-Datum V). */
export function BrandMark({ size = 32, className, ...rest }: VMarkProps) {
  return (
    <VMark size={size} className={cn("text-steel-text", className)} {...rest} />
  );
}

export interface BrandLogoProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Primary wordmark title (default: "VITRUVIAN"). */
  title?: string;
  /** Monospace subtitle below the title (default: "SOFTWARE", pass null to hide). */
  subtitle?: string | null;
  /** Size of the leading Golden-Datum V mark in pixels (default: 32). */
  markSize?: number;
}

/**
 * Official horizontal brand lockup pairing the Golden-Datum V mark with
 * tracked `IBM Plex Sans` display type and `JetBrains Mono` subtitle.
 */
export function BrandLogo({
  title = "VITRUVIAN",
  subtitle = "SOFTWARE",
  markSize = 32,
  className,
  ...rest
}: BrandLogoProps) {
  return (
    <div
      className={cn("inline-flex items-center gap-3 select-none", className)}
      {...rest}
    >
      <BrandMark size={markSize} />
      <div className="flex flex-col leading-none">
        <span
          style={{
            fontFamily: "var(--font-display)",
            fontSize: Math.max(13, Math.round(markSize * 0.46)),
            fontWeight: 600,
            letterSpacing: "0.14em",
            color: "var(--color-text)",
          }}
        >
          {title}
        </span>
        {subtitle ? (
          <span
            style={{
              fontFamily: "var(--font-mono)",
              fontSize: Math.max(9, Math.round(markSize * 0.26)),
              fontWeight: 500,
              letterSpacing: "0.24em",
              color: "var(--color-accent-text)",
              marginTop: 3,
            }}
          >
            {subtitle}
          </span>
        ) : null}
      </div>
    </div>
  );
}

export interface BrandMedallionProps extends React.HTMLAttributes<HTMLSpanElement> {
  /** Diameter in pixels (default: 96). */
  size?: number;
  /** Accessible label for the medallion. */
  alt?: string;
}

/**
 * Official circular gunmetal Vitruvian medallion (without outer button frame),
 * backed by `src/brand/vitruvian-medallion.png` with transparent alpha.
 */
export function BrandMedallion({
  size = 96,
  alt = "Vitruvian Software Medallion",
  className,
  style,
  ...rest
}: BrandMedallionProps) {
  return (
    <span
      role="img"
      aria-label={alt}
      className={cn("brand-medallion", className)}
      style={{ width: size, height: size, ...style }}
      {...rest}
    />
  );
}

/** A hairline rule, optionally carrying a registration cross. */
export function Rule({
  marked = false,
  className,
}: {
  marked?: boolean;
  className?: string;
}) {
  return <hr className={cn(marked ? "rule-marked" : "rule", className)} />;
}

/** Frosted glass. Elevation only — sticky bars, dialogs, popovers. */
export function Glass({
  className,
  ...rest
}: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("glass", className)} {...rest} />;
}
