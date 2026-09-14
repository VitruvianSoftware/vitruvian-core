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

export const EmptyResourcesIllustration: React.FC = () => (
  <svg
    width="120"
    height="100"
    viewBox="0 0 120 100"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
  >
    {/* Abstract Folder/Files Grouping */}
    <circle cx="60" cy="50" r="48" fill="var(--color-bg-subtle, #F1F5F9)" />

    {/* Back File */}
    <rect
      x="45"
      y="35"
      width="40"
      height="50"
      rx="4"
      fill="var(--color-text-muted)"
      fillOpacity="0.2"
      transform="rotate(-10 45 35)"
    />

    {/* Front Folder */}
    <path
      d="M35 40H85C87.2091 40 89 41.7909 89 44V76C89 78.2091 87.2091 80 85 80H35C32.7909 80 31 78.2091 31 76V44C31 41.7909 32.7909 40 35 40Z"
      fill="white"
      stroke="var(--color-border)"
      strokeWidth="2"
    />
    {/* Folder Tab */}
    <path
      d="M35 40H55L60 45H85"
      stroke="var(--color-border)"
      strokeWidth="2"
      strokeLinecap="round"
    />

    {/* Plus Icon Badge */}
    <circle cx="78" cy="70" r="12" fill="var(--color-primary)" />
    <path
      d="M78 64V76M72 70H84"
      stroke="white"
      strokeWidth="2"
      strokeLinecap="round"
    />
  </svg>
);
