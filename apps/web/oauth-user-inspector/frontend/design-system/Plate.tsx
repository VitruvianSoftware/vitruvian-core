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

/** Circle inscribed in a square — the Vitruvian figure's geometry. */
export function VMark({
  size = 16,
  className,
  ...rest
}: { size?: number } & React.HTMLAttributes<HTMLSpanElement>) {
  return (
    <span
      className={cn("vm", className)}
      style={{ fontSize: size }}
      aria-hidden
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
