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

import React, { useRef } from "react";
import { MenuOverlay } from "./MenuOverlay";
import { SubmenuFlyout } from "./SubmenuFlyout";
import { Icon } from "../components/icons";
import { Tooltip } from "../components/Tooltip";
import { useFeatureFlag } from "../lib/flags/use-feature-flag";
import { FEATURE_FLAGS } from "../constants/features";
import type { Workspace, SpaceGroup } from "../types";

// Color options for workspace
const SPACE_GROUP_COLORS = [
  { name: "None", value: null },
  { name: "Red", value: "#EF4444" },
  { name: "Orange", value: "#F97316" },
  { name: "Yellow", value: "#EAB308" },
  { name: "Green", value: "#22C55E" },
  { name: "Teal", value: "#14B8A6" },
  { name: "Blue", value: "#3B82F6" },
  { name: "Purple", value: "#8B5CF6" },
  { name: "Pink", value: "#EC4899" },
];

export interface WorkspaceMenuItemProps {
  workspace: Workspace;
  isActive: boolean;
  isMenuOpen: boolean;
  colorPickerOpen: boolean;
  sectionPickerOpen: boolean;
  spaceGroups: SpaceGroup[];
  style?: React.CSSProperties;
  onSwitch: () => void;
  onToggleMenu: () => void;
  onRename: () => void;
  onDelete: () => void;
  onToggleColorPicker: () => void;
  onToggleSectionPicker: () => void;
  onChangeColor: (color: string | null) => Promise<void>;
  onMoveToSection: (groupId: string | null) => Promise<void>;
}

export const WorkspaceMenuItem: React.FC<WorkspaceMenuItemProps> = ({
  workspace,
  isActive,
  isMenuOpen,
  colorPickerOpen,
  sectionPickerOpen,
  spaceGroups,
  style,
  onSwitch,
  onToggleMenu,
  onRename,
  onDelete,
  onToggleColorPicker,
  onToggleSectionPicker,
  onChangeColor,
  onMoveToSection,
}) => {
  const menuRef = useRef<HTMLDivElement>(null);
  const colorItemRef = useRef<HTMLDivElement>(null);
  const sectionItemRef = useRef<HTMLDivElement>(null);
  const useDesignSystem = useFeatureFlag(
    FEATURE_FLAGS.USE_DESIGN_SYSTEM,
    false,
  );

  // Compute effective accent color: workspace color > group color > default
  const groupColor = spaceGroups.find((g) => g.id === workspace.groupId)?.color;
  const effectiveColor = workspace.color ?? groupColor ?? undefined;

  return (
    <div
      className={`nav-item ${isActive ? "active" : ""}`}
      style={
        {
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          position: "relative",
          ...(useDesignSystem
            ? {
                borderLeft: isActive
                  ? "3px solid var(--color-accent-primary)"
                  : "3px solid transparent",
                backgroundColor: isActive
                  ? "rgba(255, 255, 255, 0.08)"
                  : "transparent",
                color: isActive
                  ? "var(--color-text-sidebar)"
                  : "var(--color-text-sidebar-muted)",
                fontWeight: isActive ? 600 : 400,
                borderRadius: "0",
              }
            : {
                "--workspace-accent-color":
                  effectiveColor || "var(--color-accent-primary)",
              }),
          ...style,
        } as React.CSSProperties
      }
    >
      <div
        style={{ flex: 1, display: "flex", alignItems: "center" }}
        onClick={onSwitch}
      >
        <span style={{ marginRight: "8px" }}>{workspace.icon || "📁"}</span>
        <span>{workspace.name}</span>
      </div>

      <div style={{ position: "relative" }} ref={menuRef}>
        {isMenuOpen && <MenuOverlay onClose={onToggleMenu} />}
        {/* Menu button */}
        <Tooltip content="Space options" placement="right">
          <button
            className="btn-icon icon-actions"
            aria-label="Space options"
            style={{
              opacity: isMenuOpen ? 1 : undefined,
              position: "relative",
              zIndex: 20,
              padding: "2px",
            }}
            onPointerDown={(e) => e.stopPropagation()}
            onClick={(e) => {
              e.stopPropagation();
              onToggleMenu();
            }}
          >
            <Icon name="more_vert" size="sm" />
          </button>
        </Tooltip>

        {/* Workspace Menu */}
        {isMenuOpen && (
          <div
            className="dropdown-menu glass-menu"
            style={{
              right: 0,
              top: "100%",
              minWidth: "180px",
              zIndex: 20,
              position: "absolute",
              borderRadius: useDesignSystem ? "0" : undefined,
              border: useDesignSystem
                ? "1px solid var(--glass-border)"
                : undefined,
              fontFamily: useDesignSystem
                ? "var(--font-mono, monospace)"
                : undefined,
            }}
          >
            {/* Share — hidden until sharing ships */}
            {FEATURE_FLAGS.SHARING_ENABLED && (
              <div
                className="dropdown-item"
                style={{
                  opacity: 0.5,
                  cursor: "not-allowed",
                }}
                title="Coming soon"
              >
                <Icon name="share" size="sm" />
                Share
              </div>
            )}

            {/* Add a description (placeholder) */}
            <div
              className="dropdown-item"
              style={{
                opacity: 0.5,
                cursor: "not-allowed",
              }}
              title="Coming soon"
            >
              <Icon name="description" size="sm" />
              Add a description
            </div>
            <div className="dropdown-divider" />

            {/* Duplicate (placeholder) */}
            <div
              className="dropdown-item"
              style={{
                opacity: 0.5,
                cursor: "not-allowed",
              }}
              title="Coming soon"
            >
              <Icon name="content_copy" size="sm" />
              Duplicate
            </div>

            {/* Rename */}
            <div className="dropdown-item" onClick={onRename}>
              <Icon name="edit" size="sm" />
              Rename
            </div>

            {/* Change color */}
            <div
              className="dropdown-item"
              ref={colorItemRef}
              style={{
                position: "relative",
              }}
              onClick={(e) => {
                e.stopPropagation();
                onToggleColorPicker();
              }}
            >
              <Icon name="palette" size="sm" />
              Change color
              <Icon
                name="keyboard_arrow_right"
                size="sm"
                style={{ marginLeft: "auto" }}
              />
              {/* Color picker submenu (portaled beside this item) */}
              <SubmenuFlyout
                anchorRef={colorItemRef}
                open={colorPickerOpen}
                minWidth={120}
              >
                {SPACE_GROUP_COLORS.map((color) => (
                  <div
                    key={color.name}
                    className="dropdown-item"
                    style={{
                      display: "flex",
                      alignItems: "center",
                      gap: "8px",
                    }}
                    onClick={async (e) => {
                      e.stopPropagation();
                      await onChangeColor(color.value);
                    }}
                  >
                    {color.value ? (
                      <div
                        style={{
                          width: "12px",
                          height: "12px",
                          borderRadius: useDesignSystem ? "0" : "50%",
                          border: useDesignSystem
                            ? "1px solid var(--color-border)"
                            : undefined,
                          backgroundColor: color.value,
                        }}
                      />
                    ) : (
                      <Icon name="block" size="sm" />
                    )}
                    {color.name}
                  </div>
                ))}
              </SubmenuFlyout>
            </div>

            {/* Move to section */}
            <div
              className="dropdown-item"
              ref={sectionItemRef}
              style={{
                position: "relative",
              }}
              onClick={(e) => {
                e.stopPropagation();
                onToggleSectionPicker();
              }}
            >
              <Icon name="drive_file_move" size="sm" />
              Move to section
              <Icon
                name="keyboard_arrow_right"
                size="sm"
                style={{ marginLeft: "auto" }}
              />
              {/* Section picker submenu (portaled beside this item) */}
              <SubmenuFlyout
                anchorRef={sectionItemRef}
                open={sectionPickerOpen}
                minWidth={140}
              >
                {/* No section option */}
                <div
                  className="dropdown-item"
                  onClick={async (e) => {
                    e.stopPropagation();
                    await onMoveToSection(null);
                  }}
                >
                  <Icon name="block" size="sm" />
                  No section
                </div>
                <div className="dropdown-divider" />

                {/* List all sections */}
                {spaceGroups.map((group) => (
                  <div
                    key={group.id}
                    className="dropdown-item"
                    style={{
                      display: "flex",
                      alignItems: "center",
                      gap: "8px",
                    }}
                    onClick={async (e) => {
                      e.stopPropagation();
                      await onMoveToSection(group.id);
                    }}
                  >
                    {group.color && (
                      <div
                        style={{
                          width: "8px",
                          height: "8px",
                          borderRadius: useDesignSystem ? "0" : "50%",
                          border: useDesignSystem
                            ? "1px solid var(--color-border)"
                            : undefined,
                          backgroundColor: group.color,
                        }}
                      />
                    )}
                    {group.title}
                  </div>
                ))}
              </SubmenuFlyout>
            </div>
            <div className="dropdown-divider" />

            {/* Archive (placeholder) */}
            <div
              className="dropdown-item"
              style={{
                opacity: 0.5,
                cursor: "not-allowed",
              }}
              title="Coming soon"
            >
              <Icon name="archive" size="sm" />
              Archive
            </div>

            {/* Delete */}
            <div
              className="dropdown-item"
              style={{
                color: "var(--color-accent-danger)",
              }}
              onClick={onDelete}
            >
              <Icon name="delete" size="sm" />
              Delete
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
