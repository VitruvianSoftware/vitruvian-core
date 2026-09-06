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
/* Preview ground for design-sync.
 *
 * Vitruvian is a DARK-FIRST system: `:root` carries the board tokens and
 * `[data-theme="light"]` is the alternate. The storybook decorator in
 * .storybook/preview.tsx establishes that ground on a wrapper div, but it
 * cannot be bundled for previews (it side-effect-imports vitruvian.css, whose
 * `@import "tailwindcss"` esbuild can't resolve), and the generated card page
 * hardcodes `body{background:#fff}`. Without this wrapper every preview
 * renders the design system on white, where the secondary and ghost variants
 * are invisible.
 *
 * This mirrors the decorator exactly: the data-theme attribute, the board
 * background and text colour, and its 21px (Fibonacci) gutter. */
import * as React from "react";

export function VitruvianGround({ theme = "dark", children }) {
  React.useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);
  return React.createElement(
    "div",
    {
      "data-theme": theme,
      style: {
        background: "var(--color-bg)",
        color: "var(--color-text)",
        padding: 21,
      },
    },
    children,
  );
}
