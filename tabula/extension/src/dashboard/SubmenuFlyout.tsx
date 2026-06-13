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

import React, { useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";

export interface SubmenuFlyoutProps {
  /** The menu item the flyout opens beside (anchored to its right edge). */
  anchorRef: React.RefObject<HTMLElement | null>;
  open: boolean;
  /** Minimum width; also the assumed width before the flyout is measured. */
  minWidth?: number;
  children: React.ReactNode;
}

/** Gap between the parent item and the flyout, in px. */
const GAP = 4;

/**
 * A nested-menu flyout rendered in a portal at document.body.
 *
 * Submenus used to render as a `position: fixed` element INSIDE the parent
 * `.dropdown-menu`. That broke after the frosted-glass redesign for two
 * compounding reasons:
 *   1. `.dropdown-menu` has `backdrop-filter`, which makes it the containing
 *      block for `position: fixed` descendants — so the old hardcoded
 *      `left: 284px` (a viewport offset) resolved against the menu box, not the
 *      viewport, throwing the flyout off to the side / off-screen.
 *   2. `.sidebar-nav` has `overflow-y: auto`, which computes `overflow-x` to
 *      `auto` as well, clipping anything that flies out horizontally.
 *
 * Portaling to <body> and positioning from the anchor's bounding rect escapes
 * both, so the submenu reliably appears next to the item that opened it. The
 * flyout opens to the right and flips left near the viewport edge.
 */
export const SubmenuFlyout: React.FC<SubmenuFlyoutProps> = ({
  anchorRef,
  open,
  minWidth = 140,
  children,
}) => {
  const flyoutRef = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ top: number; left: number } | null>(null);

  useLayoutEffect(() => {
    if (!open) {
      setPos(null);
      return;
    }
    const anchor = anchorRef.current;
    if (!anchor) return;
    const rect = anchor.getBoundingClientRect();
    // Measured once mounted (hidden); falls back to minWidth before first paint.
    const width = flyoutRef.current?.offsetWidth || minWidth;
    const height = flyoutRef.current?.offsetHeight || 0;

    // Open to the right of the item; flip to the left if it would overflow.
    let left = rect.right + GAP;
    if (left + width > window.innerWidth) {
      left = Math.max(GAP, rect.left - width - GAP);
    }
    // Align the flyout's top with the item; clamp to keep it on screen.
    let top = rect.top;
    if (height > 0 && top + height > window.innerHeight) {
      top = Math.max(GAP, window.innerHeight - height - GAP);
    }
    setPos({ top, left });
  }, [open, anchorRef, minWidth]);

  if (!open) return null;

  return createPortal(
    <div
      ref={flyoutRef}
      className="dropdown-menu"
      style={{
        position: "fixed",
        top: pos?.top ?? 0,
        left: pos?.left ?? 0,
        minWidth,
        // Stack above the parent menu (z-index 20) and the menu overlay (10).
        zIndex: 1001,
        // Hide for the measuring pass so it never flashes at the wrong spot.
        visibility: pos ? "visible" : "hidden",
      }}
      onClick={(e) => e.stopPropagation()}
    >
      {children}
    </div>,
    document.body,
  );
};
