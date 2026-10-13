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

/**
 * Stroke-based SVG paths on a 24x24 grid (1.5px stroke, butt/miter or square geometry).
 * Mirrors `packages/design-system-android/src/main/kotlin/dev/vitruvian/design/Icons.kt`.
 */
export const VitruvianIcons = {
  /** Home / Overview — house outline with door. */
  HOME: ["M3 10.5L12 3l9 7.5", "M5 9v11h14V9", "M9.5 20v-6h5v6"],
  /** Mouse-pointer / Remote — cursor arrow. */
  MOUSE_POINTER: ["M4 4l7.07 17 2.51-7.39L21 11.07 4 4z", "M13.5 13.5L19 19"],
  /** Activity / Now — pulse trace. */
  ACTIVITY: ["M22 12h-4l-3 9L9 3l-3 9H2"],
  /** Grid-2x2 / Keypad — four-quadrant grid. */
  GRID_2X2: ["M3 3h18v18H3z", "M3 12h18", "M12 3v18"],
  /** Terminal / Shell — `>_` prompt. */
  TERMINAL: ["M4 17l6-6-6-6", "M12 19h8"],
  /** Settings / Sliders — three horizontal tracks with ticks. */
  SETTINGS: [
    "M4 6h16",
    "M9 3v6",
    "M4 12h16",
    "M15 9v6",
    "M4 18h16",
    "M11 15v6",
  ],
  /** Panel-right / Drawer — frame with right column rule. */
  PANEL_RIGHT: ["M3 3h18v18H3z", "M15 3v18"],
  /** Search — lens circle with angled handle. */
  SEARCH: ["M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14z", "M20 20l-4.35-4.35"],
  /** Copy — overlapping drafting sheets. */
  COPY: ["M8 8h12v12H8z", "M16 8V4H4v12h4"],
  /** Check — crisp mechanical tick. */
  CHECK: ["M20 6L9 17l-5-5"],
  /** Chevron-right — 90deg right angle bracket. */
  CHEVRON_RIGHT: ["M9 18l6-6-6-6"],
  /** Chevron-down — 90deg down angle bracket. */
  CHEVRON_DOWN: ["M6 9l6 6 6-6"],
  /** Close / X — registration cross rotated 45deg. */
  CLOSE: ["M18 6L6 18", "M6 6l12 12"],
  /** Plus — crosshair addition mark. */
  PLUS: ["M12 5v14", "M5 12h14"],
  /** Trash — rectangular bin with lid and two vertical ribs. */
  TRASH: ["M3 6h18", "M8 6V4h8v2", "M5 6v14h14V6", "M10 10v6", "M14 10v6"],
  /** External-link — square frame with NE vector arrow. */
  EXTERNAL_LINK: ["M18 13v6H5V6h6", "M15 3h6v6", "M10 14L21 3"],
  /** Key — security/token bit key. */
  KEY: [
    "M7.5 15.5a4.5 4.5 0 1 1 0-9 4.5 4.5 0 0 1 0 9z",
    "M12 11h9v3",
    "M17 11v3",
  ],
  /** Shield — perimeter guard outline. */
  SHIELD: ["M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"],
  /** CPU / Compute — die package with 8 pins. */
  CPU: [
    "M5 5h14v14H5z",
    "M9 9h6v6H9z",
    "M9 2v3",
    "M15 2v3",
    "M9 19v3",
    "M15 19v3",
    "M2 9h3",
    "M2 15h3",
    "M19 9h3",
    "M19 15h3",
  ],
  /** Database / Storage — three stacked cylinders. */
  DATABASE: [
    "M4 6c0-1.66 3.58-3 8-3s8 1.34 8 3-3.58 3-8 3-8-1.34-8-3z",
    "M4 6v12c0 1.66 3.58 3 8 3s8-1.34 8-3V6",
    "M4 12c0 1.66 3.58 3 8 3s8-1.34 8-3",
  ],
  /** Git-branch — commit graph fork. */
  GIT_BRANCH: [
    "M6 3v12",
    "M18 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6z",
    "M6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6z",
    "M18 9c0 4.5-3 6-12 6",
  ],
  /** Speaker / Broadcast — acoustic cone with two wave arcs. */
  SPEAKER: [
    "M11 5L6 9H2v6h4l5 4V5z",
    "M15.54 8.46a5 5 0 0 1 0 7.07",
    "M19.07 4.93a10 10 0 0 1 0 14.14",
  ],
  /** Globe / Network — meridian sphere. */
  GLOBE: [
    "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20z",
    "M2 12h20",
    "M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z",
  ],
  /** Sparkles / Agent — 4-point star and satellite cross. */
  SPARKLES: [
    "M12 3l2.2 6.8L21 12l-6.8 2.2L12 21l-2.2-6.8L3 12l6.8-2.2L12 3z",
    "M19 3v4",
    "M17 5h4",
  ],
  /** Layers / Stack — three isometric plates. */
  LAYERS: ["M12 2L2 7l10 5 10-5-10-5z", "M2 17l10 5 10-5", "M2 12l10 5 10-5"],
  /** Lock — square padlock with shackle. */
  LOCK: ["M4 11h16v10H4z", "M7 11V7a5 5 0 0 1 10 0v4"],
  /** Refresh — two clockwise/counter-clockwise sync arcs. */
  REFRESH: [
    "M21 4v6h-6",
    "M3 20v-6h6",
    "M3.51 9a9 9 0 0 1 14.85-3.36L21 10",
    "M20.49 15a9 9 0 0 1-14.85 3.36L3 14",
  ],
  /** Alert-triangle — warning delta with bang. */
  ALERT_TRIANGLE: [
    "M10.29 3.86L1.82 18h20.36L13.71 3.86a2 2 0 0 0-3.42 0z",
    "M12 9v4",
    "M12 16.5h.01",
  ],
} as const;

export type VitruvianIconName = keyof typeof VitruvianIcons;

export interface VIconProps extends React.SVGProps<SVGSVGElement> {
  /** Either a named icon from `VitruvianIcons` or an array of SVG `d` path strings. */
  icon: VitruvianIconName | readonly string[] | string;
  /** Icon box size in px (default 18). */
  size?: number;
  /** Stroke width on the 24x24 grid (default 1.5). */
  strokeWidth?: number;
}

/**
 * 24x24 technical stroke icon (`1.5px` stroke, miter joins, butt caps).
 * Pairs with Android's `VIcon` composable in `packages/design-system-android`.
 */
export const VIcon = React.forwardRef<SVGSVGElement, VIconProps>(function VIcon(
  { icon, size = 18, strokeWidth = 1.5, style, ...rest },
  ref,
) {
  const paths: readonly string[] =
    typeof icon === "string"
      ? icon in VitruvianIcons
        ? VitruvianIcons[icon as VitruvianIconName]
        : [icon]
      : icon;

  return (
    <svg
      ref={ref}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="butt"
      strokeLinejoin="miter"
      aria-hidden={rest["aria-label"] ? undefined : "true"}
      style={{ flexShrink: 0, ...style }}
      {...rest}
    >
      {paths.map((d, i) => (
        <path key={i} d={d} />
      ))}
    </svg>
  );
});
