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
import { EmptyState as VitruvianEmptyState } from "@vitruviansoftware/design-system";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";

interface EmptyStateProps {
  illustration: React.ReactNode;
  title: string;
  description: string;
  action?: React.ReactNode;
  className?: string; // Allow extending
  style?: React.CSSProperties;
}

/**
 * EmptyState
 * A standardized component for displaying empty states with illustrations.
 */
export const EmptyState: React.FC<EmptyStateProps> = ({
  illustration,
  title,
  description,
  action,
  className = "",
  style,
}) => {
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  if (useDesignSystem) {
    return (
      <div className={className} style={style}>
        <VitruvianEmptyState title={title} mark={illustration} actions={action}>
          {description}
        </VitruvianEmptyState>
      </div>
    );
  }

  return (
    <div
      className={`empty-state-container ${className}`}
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: "32px 16px",
        textAlign: "center",
        color: "var(--color-text-primary)",
        width: "100%",
        ...style,
      }}
    >
      <div
        className="empty-state-illustration"
        style={{
          marginBottom: "16px",
          color: "var(--color-text-muted)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {illustration}
      </div>
      <h3
        style={{
          margin: "0 0 8px",
          fontSize: "15px",
          fontWeight: 600,
          color: "var(--color-text-primary)",
        }}
      >
        {title}
      </h3>
      <p
        style={{
          margin: "0 0 24px",
          fontSize: "13px",
          color: "var(--color-text-secondary)",
          maxWidth: "300px",
          lineHeight: "1.5",
        }}
      >
        {description}
      </p>
      {action && <div className="empty-state-action">{action}</div>}
    </div>
  );
};
