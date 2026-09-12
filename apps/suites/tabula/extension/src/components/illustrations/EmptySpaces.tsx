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

import React from "react";

export const EmptySpacesIllustration: React.FC = () => (
  <svg
    width="120"
    height="100"
    viewBox="0 0 120 100"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
  >
    {/* Soft background */}
    <circle cx="60" cy="50" r="48" fill="var(--color-bg-subtle, #F1F5F9)" />

    {/* Sidebar panel of spaces */}
    <rect
      x="34"
      y="28"
      width="52"
      height="48"
      rx="6"
      fill="white"
      stroke="var(--color-border)"
      strokeWidth="2"
    />

    {/* Active space accent bar */}
    <rect
      x="34"
      y="36"
      width="3"
      height="10"
      rx="1.5"
      fill="var(--color-primary)"
    />

    {/* Space rows */}
    <rect
      x="44"
      y="38"
      width="34"
      height="6"
      rx="3"
      fill="var(--color-text-muted)"
      fillOpacity="0.35"
    />
    <rect
      x="44"
      y="50"
      width="26"
      height="6"
      rx="3"
      fill="var(--color-text-muted)"
      fillOpacity="0.25"
    />
    <rect
      x="44"
      y="62"
      width="20"
      height="6"
      rx="3"
      fill="var(--color-text-muted)"
      fillOpacity="0.25"
    />

    {/* Plus badge */}
    <circle cx="80" cy="68" r="12" fill="var(--color-primary)" />
    <path
      d="M80 62V74M74 68H86"
      stroke="white"
      strokeWidth="2"
      strokeLinecap="round"
    />
  </svg>
);
