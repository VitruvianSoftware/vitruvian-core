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
import type { StatusKind } from "./DataDisplay.js";

const STATUS_DOT_COLOR: Record<StatusKind, string> = {
  idle: "var(--color-neutral-500)",
  ok: "var(--color-ok)",
  warn: "var(--color-warn)",
  crit: "var(--color-crit)",
  run: "var(--color-accent-text)",
};

export interface ListItemProps extends Omit<
  React.HTMLAttributes<HTMLDivElement>,
  "title"
> {
  /** Primary row label. */
  title: React.ReactNode;
  /** Secondary mono subtitle (e.g. host address, path, timestamp). */
  subtitle?: React.ReactNode;
  /** Optional status square indicator on the left (`ok`, `warn`, `crit`, `run`, `idle`). */
  status?: StatusKind;
  /** Custom leading element (rendered instead of or next to the status square). */
  leading?: React.ReactNode;
  /** Right-aligned slot (tag, mono metric, chevron, button). */
  trailing?: React.ReactNode;
  /** Selected state (draws the 2px left steel rule and `--color-accent-quiet` fill). */
  selected?: boolean;
}

/**
 * Full-bleed list row (at least `--hit-2` = 55px tall) with optional status
 * square, title + mono subtitle stack, and trailing slot. Mirrors Android's
 * `ListItem` in `packages/design-system-android`.
 */
export const ListItem = React.forwardRef<HTMLDivElement, ListItemProps>(
  function ListItem(
    {
      title,
      subtitle,
      status,
      leading,
      trailing,
      selected = false,
      className,
      onClick,
      ...rest
    },
    ref,
  ) {
    const cls = ["list-item", selected && "is-selected", className]
      .filter(Boolean)
      .join(" ");

    return (
      <div
        ref={ref}
        role={onClick ? "button" : undefined}
        tabIndex={onClick ? 0 : undefined}
        aria-selected={selected || undefined}
        className={cls}
        onClick={onClick}
        onKeyDown={
          onClick
            ? (e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault();
                  onClick(e as unknown as React.MouseEvent<HTMLDivElement>);
                }
              }
            : undefined
        }
        {...rest}
      >
        {status != null && (
          <span
            aria-hidden="true"
            style={{
              width: 7,
              height: 7,
              flex: "none",
              background: STATUS_DOT_COLOR[status],
            }}
          />
        )}
        {leading}
        <div className="grow">
          <p className="list-title">{title}</p>
          {subtitle != null && <p className="list-sub">{subtitle}</p>}
        </div>
        {trailing}
      </div>
    );
  },
);

export interface AutoGridProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Minimum column width in px before wrapping (default 240). */
  minWidth?: number;
}

/**
 * Responsive auto-fill grid (`repeat(auto-fill, minmax(minWidth, 1fr))` with
 * `--space-5` = 21px Fibonacci gap). Mirrors Android's `AutoGrid`.
 */
export const AutoGrid = React.forwardRef<HTMLDivElement, AutoGridProps>(
  function AutoGrid(
    { minWidth = 240, className, style, children, ...rest },
    ref,
  ) {
    const cls = ["grid-auto", className].filter(Boolean).join(" ");
    return (
      <div
        ref={ref}
        className={cls}
        style={
          {
            "--grid-min": `${minWidth}px`,
            ...style,
          } as React.CSSProperties
        }
        {...rest}
      >
        {children}
      </div>
    );
  },
);

export interface KeyValueEntry {
  key: React.ReactNode;
  value: React.ReactNode;
  action?: React.ReactNode;
}

export interface KeyValueProps extends React.HTMLAttributes<HTMLDListElement> {
  /** Array of `{ key, value, action? }` entries rendered in a two-column ledger. */
  items: readonly KeyValueEntry[];
}

/**
 * Structured two-column technical readout (`<dl className="kv">`) for OAuth
 * claims, node metadata, and telemetry inspection panels.
 */
export const KeyValue = React.forwardRef<HTMLDListElement, KeyValueProps>(
  function KeyValue({ items, className, ...rest }, ref) {
    const cls = ["kv", className].filter(Boolean).join(" ");
    return (
      <dl ref={ref} className={cls} {...rest}>
        {items.map((item, i) => (
          <div key={i} className="kv-row">
            <dt className="kv-key">{item.key}</dt>
            <dd className="kv-val">
              <span>{item.value}</span>
              {item.action}
            </dd>
          </div>
        ))}
      </dl>
    );
  },
);

export interface AccordionItemData {
  id: string;
  title: React.ReactNode;
  meta?: React.ReactNode;
  content: React.ReactNode;
}

export interface AccordionProps extends React.HTMLAttributes<HTMLDivElement> {
  items: readonly AccordionItemData[];
  /** Initially expanded item IDs (uncontrolled mode). */
  defaultOpenIds?: readonly string[];
  /** Allow multiple sections open simultaneously (default true). */
  multiple?: boolean;
}

/**
 * Collapsible technical disclosure list with hairline rules and a 90-degree
 * mechanical chevron indicator.
 */
export const Accordion = React.forwardRef<HTMLDivElement, AccordionProps>(
  function Accordion(
    { items, defaultOpenIds = [], multiple = true, className, ...rest },
    ref,
  ) {
    const [openIds, setOpenIds] = React.useState<Set<string>>(
      () => new Set(defaultOpenIds),
    );

    const toggle = (id: string) => {
      setOpenIds((prev) => {
        const next = new Set(multiple ? prev : []);
        if (prev.has(id)) {
          next.delete(id);
        } else {
          next.add(id);
        }
        return next;
      });
    };

    const cls = ["accordion", className].filter(Boolean).join(" ");
    return (
      <div ref={ref} className={cls} {...rest}>
        {items.map((item) => {
          const isOpen = openIds.has(item.id);
          return (
            <div
              key={item.id}
              className="accordion-item"
              data-open={isOpen ? "true" : "false"}
            >
              <button
                type="button"
                className="accordion-trigger"
                aria-expanded={isOpen}
                onClick={() => toggle(item.id)}
              >
                <span>{item.title}</span>
                <span
                  style={{
                    display: "inline-flex",
                    alignItems: "center",
                    gap: "var(--space-3)",
                  }}
                >
                  {item.meta != null && (
                    <span className="label">{item.meta}</span>
                  )}
                  <span className="acc-icon" aria-hidden="true">
                    &#9656;
                  </span>
                </span>
              </button>
              {isOpen && <div className="accordion-body">{item.content}</div>}
            </div>
          );
        })}
      </div>
    );
  },
);
