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
import { MenuOverlay } from "./MenuOverlay";
import { Icon } from "../components/icons";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";

export interface SpacesHeaderProps {
  spacesMenuOpen: boolean;
  onToggleSpacesMenu: () => void;
  onNewSpace: () => void;
  onNewSection: () => void;
}

export const SpacesHeader: React.FC<SpacesHeaderProps> = ({
  spacesMenuOpen,
  onToggleSpacesMenu,
  onNewSpace,
  onNewSection,
}) => {
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  return (
    <div className="spaces-header">
      <span
        style={{
          textTransform: "uppercase",
          fontFamily: useDesignSystem
            ? "var(--font-mono, monospace)"
            : undefined,
          fontSize: "11px",
          fontWeight: 600,
          color: useDesignSystem
            ? "var(--paper-dim, #736d64)"
            : "var(--color-text-muted)",
          letterSpacing: "0.05em",
        }}
      >
        Spaces
      </span>
      <div style={{ position: "relative" }}>
        {spacesMenuOpen && <MenuOverlay onClose={onToggleSpacesMenu} />}
        <button
          className="btn-icon"
          title="Add"
          onClick={(e) => {
            e.stopPropagation();
            onToggleSpacesMenu();
          }}
          style={{
            position: "relative",
            zIndex: 20,
            color: useDesignSystem ? "var(--ink, #1f1d1a)" : "#9AA0A6",
            padding: "2px",
          }}
        >
          <Icon name="add" size="sm" />
        </button>
        {spacesMenuOpen && (
          <div
            className={useDesignSystem ? undefined : "dropdown-menu"}
            style={{
              zIndex: 20,
              right: 0,
              top: "100%",
              minWidth: "150px",
              position: "absolute",
              backgroundColor: useDesignSystem
                ? "var(--paper, #fbf7ee)"
                : undefined,
              border: useDesignSystem
                ? "1px solid var(--ink, #1f1d1a)"
                : undefined,
              boxShadow: useDesignSystem
                ? "3px 3px 0 0 var(--ink, #1f1d1a)"
                : undefined,
            }}
          >
            <div
              className={useDesignSystem ? undefined : "dropdown-item"}
              style={
                useDesignSystem
                  ? {
                      display: "flex",
                      alignItems: "center",
                      gap: "8px",
                      padding: "8px 12px",
                      fontSize: "12px",
                      cursor: "pointer",
                      color: "var(--ink, #1f1d1a)",
                    }
                  : undefined
              }
              onClick={onNewSpace}
            >
              <Icon name="folder" size="sm" />
              New space
            </div>
            <div
              className={useDesignSystem ? undefined : "dropdown-divider"}
              style={
                useDesignSystem
                  ? {
                      borderBottom:
                        "1px solid var(--border-hairline, rgba(0,0,0,0.1))",
                      margin: "4px 0",
                    }
                  : undefined
              }
            />
            <div
              className={useDesignSystem ? undefined : "dropdown-item"}
              style={
                useDesignSystem
                  ? {
                      display: "flex",
                      alignItems: "center",
                      gap: "8px",
                      padding: "8px 12px",
                      fontSize: "12px",
                      cursor: "pointer",
                      color: "var(--ink, #1f1d1a)",
                    }
                  : undefined
              }
              onClick={onNewSection}
            >
              <Icon name="folder_open" size="sm" />
              New section
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
