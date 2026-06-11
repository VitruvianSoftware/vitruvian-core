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

export const EmptyTabsIllustration: React.FC = () => (
  <svg
    width="120"
    height="100"
    viewBox="0 0 120 100"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
  >
    {/* Background Circle */}
    <circle cx="60" cy="50" r="48" fill="var(--color-bg-subtle, #F1F5F9)" />

    {/* Browser Window */}
    <rect
      x="30"
      y="35"
      width="60"
      height="40"
      rx="4"
      fill="white"
      stroke="var(--color-border)"
      strokeWidth="2"
    />

    {/* Browser Header details */}
    <line
      x1="30"
      y1="45"
      x2="90"
      y2="45"
      stroke="var(--color-border)"
      strokeWidth="2"
    />
    <circle
      cx="36"
      cy="40"
      r="2"
      fill="var(--color-text-muted)"
      fillOpacity="0.5"
    />
    <circle
      cx="42"
      cy="40"
      r="2"
      fill="var(--color-text-muted)"
      fillOpacity="0.5"
    />
    <circle
      cx="48"
      cy="40"
      r="2"
      fill="var(--color-text-muted)"
      fillOpacity="0.5"
    />

    {/* Abstract Tabs content */}
    <rect
      x="36"
      y="52"
      width="48"
      height="4"
      rx="2"
      fill="var(--color-bg-subtle)"
    />
    <rect
      x="36"
      y="60"
      width="32"
      height="4"
      rx="2"
      fill="var(--color-bg-subtle)"
    />

    {/* Floating Tab Badge */}
    <rect
      x="75"
      y="25"
      width="24"
      height="18"
      rx="3"
      fill="var(--color-primary)"
      transform="rotate(15 75 25)"
    />
    <path
      d="M79 34H95"
      stroke="white"
      strokeWidth="2"
      strokeLinecap="round"
      transform="rotate(15 79 34)"
    />
  </svg>
);
