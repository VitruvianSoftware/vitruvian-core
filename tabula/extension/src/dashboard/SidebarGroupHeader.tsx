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
import { Icon } from "../components/icons";
import { Tooltip } from "../components/Tooltip";
import type { SpaceGroup } from "../types";

// Color options for space groups
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

export interface SidebarGroupHeaderProps {
  group: SpaceGroup;
  isMenuOpen: boolean;
  colorPickerOpen: boolean;
  onToggleCollapse: () => void;
  onToggleMenu: () => void;
  onToggleColorPicker: () => void;
  onRename: () => void;
  onChangeColor: (color: string | null) => Promise<void>;
  onDelete: () => void;
}

export const SidebarGroupHeader: React.FC<SidebarGroupHeaderProps> = ({
  group,
  isMenuOpen,
  colorPickerOpen,
  onToggleCollapse,
  onToggleMenu,
  onToggleColorPicker,
  onRename,
  onChangeColor,
  onDelete,
}) => {
  const menuRef = useRef<HTMLDivElement>(null);

  return (
    <div
      className="nav-item"
      data-testid="sidebar-group-header"
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        color: "#9AA0A6",
        fontSize: "12px",
        fontWeight: "600",
        padding: "4px 12px",
        position: "relative",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          flex: 1,
          cursor: "pointer",
        }}
        onClick={onToggleCollapse}
      >
        {/* Color indicator bar */}
        {group.color && (
          <div
            style={{
              width: "3px",
              height: "16px",
              backgroundColor: group.color,
              borderRadius: "2px",
              marginRight: "6px",
            }}
            data-testid="group-color-indicator"
          />
        )}
        <Icon
          name={
            group.collapsed ? "keyboard_arrow_right" : "keyboard_arrow_down"
          }
          size="sm"
        />
        <span style={{ marginLeft: "4px", textTransform: "uppercase" }}>
          {group.title}
        </span>
      </div>

      <div style={{ position: "relative" }} ref={menuRef}>
        {isMenuOpen && <MenuOverlay onClose={onToggleMenu} />}
        {/* Menu button */}
        <Tooltip content="Section options" placement="right">
          <button
            className="btn-icon icon-actions"
            aria-label="Section options"
            style={{
              opacity: isMenuOpen ? 1 : undefined,
              padding: "2px",
              position: "relative",
              zIndex: 20,
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

        {/* Dropdown Menu */}
        {isMenuOpen && (
          <div
            className="dropdown-menu"
            style={{ right: 0, top: "100%", minWidth: "160px", zIndex: 20 }}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Share with team (placeholder) */}
            <div
              className="dropdown-item"
              style={{ opacity: 0.5, cursor: "not-allowed" }}
              title="Coming soon"
            >
              <Icon name="group" size="sm" />
              Share with team
            </div>
            <div className="dropdown-divider" />

            {/* Rename */}
            <div className="dropdown-item" onClick={onRename}>
              <Icon name="edit" size="sm" />
              Rename
            </div>

            {/* Change color */}
            <div
              className="dropdown-item"
              style={{ position: "relative" }}
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
              {/* Color picker submenu */}
              {colorPickerOpen && (
                <div
                  className="dropdown-menu"
                  style={{
                    position: "fixed",
                    left: "284px",
                    top: "auto",
                    minWidth: "120px",
                  }}
                  onClick={(e) => e.stopPropagation()}
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
                      onClick={() => onChangeColor(color.value)}
                    >
                      {color.value ? (
                        <div
                          style={{
                            width: "12px",
                            height: "12px",
                            borderRadius: "50%",
                            backgroundColor: color.value,
                          }}
                        />
                      ) : (
                        <Icon name="block" size="sm" />
                      )}
                      {color.name}
                    </div>
                  ))}
                </div>
              )}
            </div>
            <div className="dropdown-divider" />

            {/* Delete */}
            <div
              className="dropdown-item"
              style={{ color: "var(--color-accent-danger)" }}
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
