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
import { RegistrationMarks } from "./Plate.js";

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
