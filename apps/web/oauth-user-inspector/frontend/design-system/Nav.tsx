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

/** The one piece of glass on a scrolling page. */
export function Nav({
  brand,
  children,
  actions,
  className,
}: {
  brand?: React.ReactNode;
  children?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
}) {
  return (
    <nav className={cn("nav glass", className)}>
      <a className="nav-brand" href="/">
        <VMark size={17} className="text-steel-text" /> {brand ?? "VITRUVIAN"}
      </a>
      {children ? <div className="nav-links">{children}</div> : null}
      {actions}
    </nav>
  );
}

export interface TabsProps {
  tabs: Array<{ id: string; label: React.ReactNode }>;
  active: string;
  onChange: (id: string) => void;
}

export function Tabs({ tabs, active, onChange }: TabsProps) {
  return (
    <div className="tabs" role="tablist">
      {tabs.map((t) => (
        <button
          key={t.id}
          role="tab"
          className="tab"
          aria-selected={t.id === active}
          onClick={() => onChange(t.id)}
        >
          {t.label}
        </button>
      ))}
    </div>
  );
}

export function Shell({
  side,
  children,
}: {
  side: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div className="shell">
      <aside className="shell-side">{side}</aside>
      <section className="shell-main">{children}</section>
    </div>
  );
}

export function SideGroup({ children }: { children: React.ReactNode }) {
  return <div className="side-group">{children}</div>;
}

export function SideItem({
  current,
  className,
  ...rest
}: { current?: boolean } & React.AnchorHTMLAttributes<HTMLAnchorElement>) {
  return (
    <a
      className={cn("side-item", className)}
      aria-current={current ? "page" : undefined}
      {...rest}
    />
  );
}

export function Crumbs({ children }: { children: React.ReactNode }) {
  return <div className="crumbs">{children}</div>;
}
