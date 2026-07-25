import * as React from "react";
import { cn } from "./cn";
import { RegistrationMarks } from "./Plate";

export interface DialogProps {
  open: boolean;
  title: React.ReactNode;
  kicker?: React.ReactNode;
  /** Sanguine kicker + danger confirm. Destructive actions only. */
  destructive?: boolean;
  actions?: React.ReactNode;
  onDismiss?: () => void;
  children?: React.ReactNode;
}

/** Glass at the top elevation over an ink-washed, blurred backdrop. */
export function Dialog({
  open,
  title,
  kicker,
  destructive,
  actions,
  onDismiss,
  children,
}: DialogProps) {
  if (!open) return null;
  return (
    <div
      className="dialog-backdrop"
      onClick={(e) => {
        if (e.target === e.currentTarget) onDismiss?.();
      }}
    >
      <div className="dialog plate" role="dialog" aria-modal="true">
        <RegistrationMarks />
        {kicker ? (
          <div
            className="label"
            style={
              destructive ? { color: "var(--color-sanguine-text)" } : undefined
            }
          >
            {kicker}
          </div>
        ) : null}
        <h3 className="dialog-title">{title}</h3>
        {children}
        {actions ? <div className="dialog-actions">{actions}</div> : null}
      </div>
    </div>
  );
}

export function Banner({
  tone = "info",
  icon,
  className,
  children,
  ...rest
}: {
  tone?: "info" | "warn" | "err";
  icon?: React.ReactNode;
} & React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={cn("banner", `is-${tone}`, className)} {...rest}>
      {icon}
      <div>{children}</div>
    </div>
  );
}
