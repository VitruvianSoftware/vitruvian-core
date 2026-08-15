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

/**
 * Cross-device "Changes from your other device" prompt.
 *
 * Tabula keeps one PRIMARY tab session per space (see the server's sticky
 * active-device lease). When a space is live on another device and its tab
 * session differs from what's open here, this non-primary device surfaces the
 * primary's tabs and lets the user resolve the divergence — exactly Workona's
 * "Changes from your other computer → Apply changes (uncheck any) / Ignore".
 *
 * Selective by design: every incoming tab has a checkbox (all checked by
 * default); "Apply" adopts only the checked ones, "Keep my tabs" discards the
 * incoming session and keeps what's open here. Either choice makes THIS device
 * the primary going forward (handled by the caller). The component is purely
 * presentational — it owns selection state only; the caller supplies the tabs
 * and the resolve actions.
 */
import React, { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { getFaviconSrc } from "../utils/favicon";
import { Button } from "@vitruviansoftware/design-system";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";

/** Minimal tab shape this prompt needs (a subset of the shared Tab). */
export interface CrossDeviceTab {
  url: string;
  title?: string;
  favIconUrl?: string;
}

interface TabRowProps {
  tab: CrossDeviceTab;
  selected: boolean;
  onToggle: () => void;
  useDesignSystem?: boolean;
}

function TabRow({ tab, selected, onToggle, useDesignSystem }: TabRowProps) {
  return (
    <motion.div
      onClick={onToggle}
      whileHover={{
        backgroundColor: useDesignSystem
          ? "var(--paper-hover, rgba(0, 0, 0, 0.04))"
          : "rgba(255, 255, 255, 0.05)",
      }}
      whileTap={{ scale: 0.99 }}
      style={
        useDesignSystem
          ? {
              display: "flex",
              alignItems: "center",
              gap: "12px",
              padding: "8px 12px",
              cursor: "pointer",
              backgroundColor: selected
                ? "var(--paper-hover, rgba(0, 0, 0, 0.06))"
                : "transparent",
              border: "1px solid var(--border-hairline, rgba(0,0,0,0.08))",
              borderRadius: "0",
              margin: "4px 8px",
            }
          : {
              display: "flex",
              alignItems: "center",
              gap: "12px",
              padding: "10px 16px",
              cursor: "pointer",
              backgroundColor: selected
                ? "rgba(51, 112, 255, 0.15)"
                : "transparent",
              borderRadius: "12px",
              margin: "2px 8px",
              transition: "background-color 0.2s ease",
            }
      }
      role="checkbox"
      aria-checked={selected}
      tabIndex={0}
      onKeyDown={(e: React.KeyboardEvent) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onToggle();
        }
      }}
    >
      {/* Checkbox */}
      <div
        style={
          useDesignSystem
            ? {
                width: "16px",
                height: "16px",
                border: "1px solid var(--ink, #1f1d1a)",
                borderRadius: "0",
                backgroundColor: selected
                  ? "var(--ink, #1f1d1a)"
                  : "transparent",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                flexShrink: 0,
              }
            : {
                width: "20px",
                height: "20px",
                border: `2px solid ${selected ? "var(--color-primary)" : "rgba(255, 255, 255, 0.2)"}`,
                borderRadius: "6px",
                backgroundColor: selected
                  ? "var(--color-primary)"
                  : "transparent",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                transition: "all 0.2s ease",
                flexShrink: 0,
              }
        }
      >
        {selected && (
          <svg
            width={useDesignSystem ? "10" : "12"}
            height={useDesignSystem ? "10" : "12"}
            viewBox="0 0 12 12"
            fill={useDesignSystem ? "var(--paper, #fbf7ee)" : "white"}
          >
            <path
              d="M10 3L4.5 8.5L2 6"
              stroke={useDesignSystem ? "var(--paper, #fbf7ee)" : "white"}
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          </svg>
        )}
      </div>

      {/* Favicon */}
      <img
        src={getFaviconSrc({
          favIconUrl: tab.favIconUrl ?? null,
          url: tab.url,
        })}
        alt=""
        style={{
          width: "18px",
          height: "18px",
          borderRadius: useDesignSystem ? "0" : "4px",
          flexShrink: 0,
        }}
        onError={(e) => {
          const img = e.currentTarget;
          img.onerror = null;
          img.src = getFaviconSrc({ favIconUrl: null, url: tab.url });
        }}
      />

      {/* Title */}
      <span
        style={
          useDesignSystem
            ? {
                flex: 1,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
                fontSize: "13px",
                fontWeight: 500,
                color: "var(--ink, #1f1d1a)",
              }
            : {
                flex: 1,
                overflow: "hidden",
                textOverflow: "ellipsis",
                whiteSpace: "nowrap",
                fontSize: "14px",
                fontWeight: 400,
                color: selected ? "white" : "rgba(255, 255, 255, 0.8)",
              }
        }
      >
        {tab.title || tab.url || "Untitled"}
      </span>
    </motion.div>
  );
}

export interface CrossDeviceSessionPopoverProps {
  /** The primary device's tab session (from the synced workspace). */
  serverTabs: CrossDeviceTab[];
  /** Optional friendly label for the other device (falls back to generic copy). */
  otherDeviceLabel?: string;
  /** Keep this device's current tabs; discard the incoming session and dismiss. */
  onKeepMine: () => void;
  /** Adopt only the checked subset of the primary's tabs. */
  onApply: (selectedTabs: CrossDeviceTab[]) => void;
}

export function CrossDeviceSessionPopover({
  serverTabs,
  otherDeviceLabel,
  onKeepMine,
  onApply,
}: CrossDeviceSessionPopoverProps) {
  const [selected, setSelected] = useState<Set<number>>(
    () => new Set(serverTabs.map((_, i) => i)),
  );
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  const toggle = (index: number) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(index)) next.delete(index);
      else next.add(index);
      return next;
    });
  };

  const handleApply = () => {
    onApply(serverTabs.filter((_, i) => selected.has(i)));
  };

  const count = selected.size;

  return (
    <AnimatePresence>
      <motion.div
        className="tab-conflict-backdrop"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        style={{
          position: "fixed",
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          backgroundColor: useDesignSystem
            ? "rgba(0, 0, 0, 0.4)"
            : "rgba(10, 14, 30, 0.32)",
          backdropFilter: "blur(4px)",
          zIndex: 9999,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
        onClick={onKeepMine}
      >
        <motion.div
          className={
            useDesignSystem ? undefined : "tab-conflict-popover glass-menu"
          }
          initial={{ opacity: 0, y: 20, scale: 0.95 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, scale: 0.95 }}
          transition={{ duration: 0.2, ease: "easeOut" }}
          onClick={(e: React.MouseEvent) => e.stopPropagation()}
          style={
            useDesignSystem
              ? {
                  width: "420px",
                  backgroundColor: "var(--paper, #fbf7ee)",
                  border: "2px solid var(--ink, #1f1d1a)",
                  boxShadow: "6px 6px 0 0 var(--ink, #1f1d1a)",
                  borderRadius: "0",
                  overflow: "hidden",
                  color: "var(--ink, #1f1d1a)",
                }
              : {
                  width: "400px",
                  backgroundColor: "rgba(20, 23, 30, 0.62)",
                  borderRadius: "18px",
                  overflow: "hidden",
                }
          }
          role="dialog"
          aria-label="Changes from your other device"
        >
          {/* Header */}
          <div
            style={
              useDesignSystem
                ? {
                    display: "flex",
                    flexDirection: "column",
                    gap: "4px",
                    padding: "16px 20px",
                    borderBottom: "1px solid var(--ink, #1f1d1a)",
                  }
                : {
                    display: "flex",
                    flexDirection: "column",
                    gap: "4px",
                    padding: "20px 24px",
                    borderBottom: "1px solid rgba(255, 255, 255, 0.1)",
                  }
            }
          >
            <span
              style={
                useDesignSystem
                  ? {
                      fontWeight: 700,
                      fontSize: "15px",
                      fontFamily: "var(--font-mono, monospace)",
                      color: "var(--ink, #1f1d1a)",
                    }
                  : { fontWeight: 600, fontSize: "16px", color: "white" }
              }
            >
              Changes from your other device
            </span>
            <span
              style={
                useDesignSystem
                  ? {
                      fontSize: "11px",
                      fontFamily: "var(--font-mono, monospace)",
                      color: "var(--paper-dim, #736d64)",
                    }
                  : {
                      fontSize: "12px",
                      color: "rgba(255, 255, 255, 0.5)",
                    }
              }
            >
              This space is active on{" "}
              {otherDeviceLabel ? otherDeviceLabel : "another device"}. Choose
              which of its tabs to open here.
            </span>
          </div>

          {/* Tab list */}
          <div
            style={{
              maxHeight: "280px",
              overflowY: "auto",
              padding: "12px 8px",
            }}
          >
            {serverTabs.length === 0 ? (
              <div
                style={{
                  padding: "32px",
                  textAlign: "center",
                  color: useDesignSystem
                    ? "var(--paper-dim, #736d64)"
                    : "rgba(255, 255, 255, 0.5)",
                  fontFamily: useDesignSystem
                    ? "var(--font-mono, monospace)"
                    : undefined,
                }}
              >
                No tabs on the other device
              </div>
            ) : (
              serverTabs.map((tab, index) => (
                <TabRow
                  key={`${index}-${tab.url}`}
                  tab={tab}
                  selected={selected.has(index)}
                  onToggle={() => toggle(index)}
                  useDesignSystem={useDesignSystem}
                />
              ))
            )}
          </div>

          {/* Footer */}
          <div
            style={
              useDesignSystem
                ? {
                    display: "flex",
                    justifyContent: "flex-end",
                    gap: "8px",
                    padding: "12px 20px",
                    borderTop: "1px solid var(--ink, #1f1d1a)",
                    backgroundColor: "var(--paper-hover, rgba(0,0,0,0.02))",
                  }
                : {
                    display: "flex",
                    justifyContent: "flex-end",
                    gap: "12px",
                    padding: "16px 24px",
                    borderTop: "1px solid rgba(255, 255, 255, 0.1)",
                    backgroundColor: "rgba(0, 0, 0, 0.2)",
                  }
            }
          >
            {useDesignSystem ? (
              <>
                <Button variant="ghost" size="sm" onClick={onKeepMine}>
                  Keep my tabs
                </Button>
                <Button
                  variant="primary"
                  size="sm"
                  onClick={handleApply}
                  disabled={count === 0}
                >
                  Apply {count} tab{count !== 1 ? "s" : ""}
                </Button>
              </>
            ) : (
              <>
                <button
                  onClick={onKeepMine}
                  style={{
                    padding: "10px 20px",
                    background: "transparent",
                    border: "none",
                    color: "rgba(255, 255, 255, 0.7)",
                    cursor: "pointer",
                    fontSize: "14px",
                    fontWeight: 500,
                  }}
                >
                  Keep my tabs
                </button>
                <motion.button
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.98 }}
                  onClick={handleApply}
                  disabled={count === 0}
                  style={{
                    padding: "10px 24px",
                    border: "none",
                    borderRadius: "18px",
                    background: "var(--color-primary)",
                    color: "white",
                    cursor: count === 0 ? "not-allowed" : "pointer",
                    fontSize: "14px",
                    fontWeight: 600,
                    opacity: count === 0 ? 0.5 : 1,
                    boxShadow: "0 4px 12px rgba(51, 112, 255, 0.3)",
                  }}
                >
                  Apply {count} tab{count !== 1 ? "s" : ""}
                </motion.button>
              </>
            )}
          </div>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}

export default CrossDeviceSessionPopover;
