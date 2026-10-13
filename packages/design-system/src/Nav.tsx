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

export interface HostChipProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  host: React.ReactNode;
  signal?: "ok" | "warn" | "crit" | "run" | "idle";
}

/**
 * Compact host/environment selector chip for top bars (`TopBar`, `Nav`).
 * Mirrors Android's `HostChip`.
 */
export function HostChip({
  host,
  signal = "ok",
  className,
  ...rest
}: HostChipProps) {
  const dotColor =
    signal === "ok"
      ? "var(--color-ok)"
      : signal === "warn"
        ? "var(--color-warn)"
        : signal === "crit"
          ? "var(--color-crit)"
          : signal === "run"
            ? "var(--color-accent-text)"
            : "var(--color-neutral-500)";

  return (
    <button type="button" className={cn("host-chip", className)} {...rest}>
      <span
        aria-hidden="true"
        style={{ width: 6, height: 6, background: dotColor, flex: "none" }}
      />
      <span>{host}</span>
      <span aria-hidden="true" className="dim">
        &#9662;
      </span>
    </button>
  );
}

export interface TopBarProps {
  title: React.ReactNode;
  leading?: React.ReactNode;
  trailing?: React.ReactNode;
  glass?: boolean;
  className?: string;
}

/**
 * Top bar (`.m-bar`, `--hit-2` = 55px tall) with optional `VMark` leading slot
 * and trailing actions. Mirrors Android's `TopBar`.
 */
export function TopBar({
  title,
  leading,
  trailing,
  glass = true,
  className,
}: TopBarProps) {
  return (
    <header className={cn("m-bar", glass && "glass", className)}>
      {leading ?? <VMark size={16} className="text-steel-text" />}
      <h1 className="m-bar-title">{title}</h1>
      {trailing}
    </header>
  );
}

export interface NavDestination {
  id: string;
  label: React.ReactNode;
  icon?: React.ReactNode;
}

export interface TabBarProps {
  tabs: readonly NavDestination[];
  active: string;
  onChange: (id: string) => void;
  className?: string;
}

/**
 * Bottom glass tab bar (`.m-tabbar`) with a 2px top steel active indicator.
 * Mirrors Android's `TabBar`.
 */
export function TabBar({ tabs, active, onChange, className }: TabBarProps) {
  return (
    <nav className={cn("m-tabbar", className)} role="tablist">
      {tabs.map((t) => {
        const isCurrent = t.id === active;
        return (
          <button
            key={t.id}
            type="button"
            role="tab"
            aria-selected={isCurrent}
            aria-current={isCurrent ? "page" : undefined}
            className="m-tab"
            onClick={() => onChange(t.id)}
          >
            {t.icon}
            <span>{t.label}</span>
          </button>
        );
      })}
    </nav>
  );
}

export interface RailProps {
  items: readonly NavDestination[];
  active: string;
  onChange: (id: string) => void;
  header?: React.ReactNode;
  footer?: React.ReactNode;
  className?: string;
}

/**
 * Vertical 72px navigation rail (`.rail`) for tablet, desktop-compact, and
 * side-docked toolbars. Mirrors Android's `Rail`.
 */
export function Rail({
  items,
  active,
  onChange,
  header,
  footer,
  className,
}: RailProps) {
  return (
    <nav className={cn("rail", className)}>
      {header ? (
        <div style={{ marginBottom: "var(--space-3)" }}>{header}</div>
      ) : null}
      <div style={{ flex: 1, width: "100%" }}>
        {items.map((item) => {
          const isCurrent = item.id === active;
          return (
            <button
              key={item.id}
              type="button"
              aria-current={isCurrent ? "page" : undefined}
              className="rail-item"
              onClick={() => onChange(item.id)}
            >
              {item.icon}
              <span>{item.label}</span>
            </button>
          );
        })}
      </div>
      {footer}
    </nav>
  );
}

export function SectionHeader({
  label,
  trailing,
  className,
}: {
  label: React.ReactNode;
  trailing?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("m-section-head", className)}>
      <span className="label">{label}</span>
      {trailing}
    </div>
  );
}

export function Section({
  label,
  trailing,
  className,
  children,
}: {
  label?: React.ReactNode;
  trailing?: React.ReactNode;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <section className={className}>
      {label != null ? (
        <SectionHeader label={label} trailing={trailing} />
      ) : null}
      <div>{children}</div>
    </section>
  );
}

export function MobileShell({
  topBar,
  bottomBar,
  className,
  children,
}: {
  topBar?: React.ReactNode;
  bottomBar?: React.ReactNode;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <div className={cn("m-shell", className)}>
      {topBar ?? <div />}
      <main className="m-body">{children}</main>
      {bottomBar ?? <div />}
    </div>
  );
}

export interface PaginationProps {
  page: number;
  totalPages: number;
  onPageChange: (page: number) => void;
  className?: string;
}

/**
 * Tabular-numeral pagination strip (`.pagination`) with mechanical active bar.
 */
export function Pagination({
  page,
  totalPages,
  onPageChange,
  className,
}: PaginationProps) {
  const pages = Array.from(
    { length: Math.max(1, totalPages) },
    (_, i) => i + 1,
  );
  return (
    <nav
      className={cn("pagination", className)}
      aria-label="Pagination"
      role="navigation"
    >
      <button
        type="button"
        className="page-btn"
        disabled={page <= 1}
        onClick={() => onPageChange(page - 1)}
        aria-label="Previous page"
      >
        &larr;
      </button>
      {pages.map((p) => (
        <button
          key={p}
          type="button"
          className="page-btn"
          aria-current={p === page ? "page" : undefined}
          onClick={() => onPageChange(p)}
        >
          {String(p).padStart(2, "0")}
        </button>
      ))}
      <button
        type="button"
        className="page-btn"
        disabled={page >= totalPages}
        onClick={() => onPageChange(page + 1)}
        aria-label="Next page"
      >
        &rarr;
      </button>
    </nav>
  );
}

export interface AvatarProps extends React.HTMLAttributes<HTMLSpanElement> {
  /** Two-character monogram fallback when no `src` is provided. */
  monogram?: string;
  /** Optional image URL (rendered with Vitruvian grayscale screen-print filter). */
  src?: string;
  alt?: string;
  size?: "sm" | "md" | "lg";
  status?: "ok" | "warn" | "crit" | "run" | "idle";
}

/**
 * Square framed identity badge (`.avatar`) with monogram or desaturated
 * portrait and optional corner status dot.
 */
export function Avatar({
  monogram,
  src,
  alt = "",
  size = "md",
  status,
  className,
  ...rest
}: AvatarProps) {
  return (
    <span
      className={cn("avatar", size !== "md" && `avatar-${size}`, className)}
      {...rest}
    >
      {src ? <img src={src} alt={alt} /> : <span>{monogram ?? "VT"}</span>}
      {status ? (
        <span
          aria-hidden="true"
          className={cn("avatar-dot", status !== "idle" && `is-${status}`)}
        />
      ) : null}
    </span>
  );
}
