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
import { VMark } from "./Plate.js";

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
