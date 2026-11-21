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

export function Menu({
  children,
  className,
  style,
  ...rest
}: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn("dropdown-menu glass-menu", className)}
      style={{
        borderRadius: "0",
        border: "1px solid var(--glass-border)",
        fontFamily: "var(--font-mono, monospace)",
        ...style,
      }}
      {...rest}
    >
      {children}
    </div>
  );
}

export function MenuItem({
  children,
  className,
  destructive,
  style,
  ...rest
}: React.HTMLAttributes<HTMLDivElement> & { destructive?: boolean }) {
  return (
    <div
      className={cn("dropdown-item", className)}
      style={{
        ...(destructive ? { color: "var(--color-accent-danger)" } : {}),
        ...style,
      }}
      {...rest}
    >
      {children}
    </div>
  );
}

export function MenuDivider({
  className,
  ...rest
}: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("dropdown-divider", className)} {...rest} />;
}

export interface BottomSheetProps {
  open: boolean;
  title?: React.ReactNode;
  kicker?: React.ReactNode;
  onDismiss?: () => void;
  children?: React.ReactNode;
}

/**
 * Bottom-anchored glass sheet (`.m-sheet`) with top registration corners and a
 * 34x2px mechanical drag rule. Mirrors Android's `BottomSheet`.
 */
export function BottomSheet({
  open,
  title,
  kicker,
  onDismiss,
  children,
}: BottomSheetProps) {
  if (!open) return null;
  return (
    <div
      className="m-sheet-backdrop"
      onClick={(e) => {
        if (e.target === e.currentTarget) onDismiss?.();
      }}
    >
      <div className="m-sheet plate" role="dialog" aria-modal="true">
        <RegistrationMarks />
        <div className="m-sheet-handle" aria-hidden="true" />
        {kicker ? <div className="label">{kicker}</div> : null}
        {title ? <h3 className="dialog-title">{title}</h3> : null}
        {children}
      </div>
    </div>
  );
}

export interface TooltipProps {
  content: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}

/**
 * Hover/focus glass micro-label tooltip (`.tooltip`).
 */
export function Tooltip({ content, children, className }: TooltipProps) {
  const [open, setOpen] = React.useState(false);
  return (
    <span
      className={cn("tooltip-wrap", className)}
      onMouseEnter={() => setOpen(true)}
      onMouseLeave={() => setOpen(false)}
      onFocus={() => setOpen(true)}
      onBlur={() => setOpen(false)}
    >
      {children}
      {open ? (
        <span role="tooltip" className="tooltip">
          {content}
        </span>
      ) : null}
    </span>
  );
}

export interface PopoverProps {
  open: boolean;
  trigger: React.ReactNode;
  align?: "left" | "right";
  children: React.ReactNode;
  className?: string;
}

/**
 * Floating glass surface anchored below a trigger element (`.popover`).
 */
export function Popover({
  open,
  trigger,
  align = "left",
  children,
  className,
}: PopoverProps) {
  return (
    <div className="popover-wrap">
      {trigger}
      {open ? (
        <div
          className={cn(
            "popover plate",
            align === "right" && "popover-right",
            className,
          )}
        >
          <RegistrationMarks />
          {children}
        </div>
      ) : null}
    </div>
  );
}

export interface ToastProps extends Omit<
  React.HTMLAttributes<HTMLDivElement>,
  "title"
> {
  title: React.ReactNode;
  message?: React.ReactNode;
  tone?: "accent" | "ok" | "warn" | "crit";
  action?: React.ReactNode;
}

/**
 * Non-blocking glass notification strip (`.toast`) with a 2px left signal bar.
 */
export function Toast({
  title,
  message,
  tone = "accent",
  action,
  className,
  ...rest
}: ToastProps) {
  return (
    <div
      role="status"
      className={cn("toast", tone !== "accent" && `is-${tone}`, className)}
      {...rest}
    >
      <div className="toast-body">
        <p className="toast-title">{title}</p>
        {message != null ? <p className="toast-msg">{message}</p> : null}
      </div>
      {action}
    </div>
  );
}

export interface DrawerProps {
  open: boolean;
  title: React.ReactNode;
  kicker?: React.ReactNode;
  side?: "left" | "right";
  footer?: React.ReactNode;
  onDismiss?: () => void;
  children?: React.ReactNode;
}

/**
 * Side-anchored glass inspection drawer (`.drawer`) for entity details, trace
 * spans, and agent session transcripts.
 */
export function Drawer({
  open,
  title,
  kicker,
  side = "right",
  footer,
  onDismiss,
  children,
}: DrawerProps) {
  if (!open) return null;
  return (
    <div
      className={cn("drawer-backdrop", side === "left" && "is-left")}
      onClick={(e) => {
        if (e.target === e.currentTarget) onDismiss?.();
      }}
    >
      <aside className="drawer" role="dialog" aria-modal="true">
        <header className="drawer-head">
          <div>
            {kicker ? <div className="label">{kicker}</div> : null}
            <h3 className="dialog-title">{title}</h3>
          </div>
          {onDismiss ? (
            <button
              type="button"
              className="btn btn-ghost btn-sm"
              onClick={onDismiss}
              aria-label="Close drawer"
            >
              ESC
            </button>
          ) : null}
        </header>
        <div className="drawer-body">{children}</div>
        {footer ? <footer className="drawer-foot">{footer}</footer> : null}
      </aside>
    </div>
  );
}

export interface CommandPaletteItem {
  id: string;
  label: React.ReactNode;
  group?: string;
  shortcut?: string;
  icon?: React.ReactNode;
  onSelect?: () => void;
}

export interface CommandPaletteProps {
  open: boolean;
  query: string;
  onQueryChange: (q: string) => void;
  items: readonly CommandPaletteItem[];
  placeholder?: string;
  onDismiss?: () => void;
}

/**
 * Keyboard-driven command palette (`.cmd-palette`) with mono search input,
 * grouped items, and `.kbd` shortcut badges.
 */
export function CommandPalette({
  open,
  query,
  onQueryChange,
  items,
  placeholder = "Type a command or search...",
  onDismiss,
}: CommandPaletteProps) {
  if (!open) return null;

  const groups = new Map<string, CommandPaletteItem[]>();
  for (const item of items) {
    const g = item.group ?? "COMMANDS";
    const list = groups.get(g) ?? [];
    list.push(item);
    groups.set(g, list);
  }

  return (
    <div
      className="dialog-backdrop"
      onClick={(e) => {
        if (e.target === e.currentTarget) onDismiss?.();
      }}
    >
      <div className="cmd-palette plate" role="dialog" aria-modal="true">
        <RegistrationMarks />
        <div className="cmd-input-row">
          <span className="label-accent mono">&gt;_</span>
          <input
            type="text"
            className="cmd-input"
            value={query}
            onChange={(e) => onQueryChange(e.target.value)}
            placeholder={placeholder}
            autoFocus
          />
          <kbd className="kbd">ESC</kbd>
        </div>
        <div className="cmd-list" role="listbox">
          {Array.from(groups.entries()).map(([groupName, groupItems]) => (
            <div key={groupName}>
              <div className="cmd-group-label">{groupName}</div>
              {groupItems.map((item) => (
                <div
                  key={item.id}
                  role="option"
                  aria-selected={false}
                  className="dropdown-item"
                  onClick={() => item.onSelect?.()}
                >
                  {item.icon}
                  <span>{item.label}</span>
                  {item.shortcut ? (
                    <kbd className="kbd">{item.shortcut}</kbd>
                  ) : null}
                </div>
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
