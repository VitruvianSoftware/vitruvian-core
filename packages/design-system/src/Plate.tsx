import * as React from "react";
import { cn } from "./cn";

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
export function Rule({ marked = false }: { marked?: boolean }) {
  return <hr className={marked ? "rule-marked" : "rule"} />;
}

/** Frosted glass. Elevation only — sticky bars, dialogs, popovers. */
export function Glass({
  className,
  ...rest
}: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("glass", className)} {...rest} />;
}
