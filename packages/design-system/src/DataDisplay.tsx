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

export type Signal = "ok" | "warn" | "crit" | "run" | "idle";

/** State is never carried by colour alone — the word is required. */
export function Status({
  signal = "idle",
  children,
}: {
  signal?: Signal;
  children: React.ReactNode;
}) {
  return (
    <span className={cn("status", signal !== "idle" && `is-${signal}`)}>
      {children}
    </span>
  );
}

export function Metric({
  label,
  value,
  delta,
  down,
}: {
  label: React.ReactNode;
  value: React.ReactNode;
  delta?: React.ReactNode;
  down?: boolean;
}) {
  return (
    <div className="metric">
      <div className="label">{label}</div>
      <div className="metric-value">{value}</div>
      {delta ? (
        <div className={cn("metric-delta", down && "is-down")}>{delta}</div>
      ) : null}
    </div>
  );
}

/** 0–1. Tone escalates on the value, so a full bar is always read as trouble. */
export function Meter({
  value,
  tone,
}: {
  value: number;
  tone?: "warn" | "crit";
}) {
  const pct = Math.max(0, Math.min(1, value)) * 100;
  return (
    <div
      className={cn("meter", tone && `is-${tone}`)}
      role="meter"
      aria-valuenow={pct}
      aria-valuemin={0}
      aria-valuemax={100}
    >
      <span style={{ width: `${pct}%` }} />
    </div>
  );
}

export function SegBar({
  total,
  filled,
  warn = 0,
}: {
  total: number;
  filled: number;
  warn?: number;
}) {
  return (
    <div className="segbar">
      {Array.from({ length: total }, (_, i) => (
        <i
          key={i}
          className={i < filled ? "on" : i < filled + warn ? "warn" : ""}
        />
      ))}
    </div>
  );
}

export function Spark({ points }: { points: number[] }) {
  const max = Math.max(...points, 1);
  return (
    <div className="spark">
      {points.map((p, i) => (
        <i key={i} style={{ height: `${(p / max) * 100}%` }} />
      ))}
    </div>
  );
}

export type LogLevel = "info" | "ok" | "warn" | "err";

export function LogStream({
  rows,
}: {
  rows: Array<{
    ts: string;
    level: LogLevel;
    message: React.ReactNode;
    isNew?: boolean;
  }>;
}) {
  return (
    <div className="log">
      {rows.map((r, i) => (
        <div className={cn("log-row", r.isNew && "is-new")} key={i}>
          <span className="log-ts">{r.ts}</span>
          <span className={cn("log-lvl", r.level)}>{r.level}</span>
          <span>{r.message}</span>
        </div>
      ))}
    </div>
  );
}

export function Table({
  className,
  ...rest
}: React.TableHTMLAttributes<HTMLTableElement>) {
  return <table className={cn("table", className)} {...rest} />;
}
