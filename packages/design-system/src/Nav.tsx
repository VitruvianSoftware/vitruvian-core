import * as React from "react";
import { cn } from "./cn";
import { VMark } from "./Plate";

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
