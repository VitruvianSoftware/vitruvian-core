import * as React from "react";
import { cn } from "./cn";
import { VMark } from "./Plate";

/**
 * Says what happened, what it means, what to do next — in that order.
 * No apologies, no jokes.
 */
export function EmptyState({
  title,
  children,
  actions,
  mark,
  framed,
}: {
  title: React.ReactNode;
  children?: React.ReactNode;
  actions?: React.ReactNode;
  mark?: React.ReactNode;
  framed?: boolean;
}) {
  return (
    <div
      className={cn("state", framed && "plate")}
      style={framed ? { borderStyle: "solid" } : undefined}
    >
      {mark ?? <VMark size={34} className="state-mark" />}
      <h4 className="state-title">{title}</h4>
      {children ? <p className="state-body">{children}</p> : null}
      {actions}
    </div>
  );
}

export function Skeleton({
  width = "100%",
  height = 13,
  className,
}: {
  width?: number | string;
  height?: number;
  className?: string;
}) {
  return (
    <span
      className={cn("skeleton", className)}
      style={{ display: "block", width, height }}
    />
  );
}

export function Spinner({ className }: { className?: string }) {
  return (
    <span
      className={cn("spinner", className)}
      role="status"
      aria-label="Loading"
    />
  );
}
