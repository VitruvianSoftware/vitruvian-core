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

/**
 * WorkspaceForm component for creating/editing workspaces
 */

import React, { useState } from "react";
import type { WorkspaceCreateInput, Workspace } from "../types";

interface WorkspaceFormProps {
  workspace?: Workspace;
  onSubmit: (input: WorkspaceCreateInput) => void;
  onCancel: () => void;
}

const COMMON_ICONS = ["📁", "💼", "🎨", "🔬", "📚", "🎯", "💡", "🔧"];
const COMMON_COLORS = [
  "#4F46E5",
  "#DC2626",
  "#059669",
  "#D97706",
  "#7C3AED",
  "#0891B2",
];

export const WorkspaceForm: React.FC<WorkspaceFormProps> = ({
  workspace,
  onSubmit,
  onCancel,
}) => {
  const [name, setName] = useState(workspace?.name || "");
  const [description, setDescription] = useState(workspace?.description || "");
  const [icon, setIcon] = useState(workspace?.icon || "📁");
  const [color, setColor] = useState(workspace?.color || "#4F46E5");

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (name.trim()) {
      onSubmit({ name: name.trim(), description, icon, color });
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      <div style={{ marginBottom: "12px" }}>
        <label
          htmlFor="name"
          style={{
            display: "block",
            fontSize: "12px",
            fontWeight: "bold",
            marginBottom: "4px",
          }}
        >
          Name *
        </label>
        <input
          id="name"
          type="text"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="e.g., Work, Personal, Research"
          maxLength={255}
          style={{
            width: "100%",
            padding: "6px 8px",
            border: "1px solid var(--color-border)",
            borderRadius: "4px",
            fontSize: "13px",
            backgroundColor: "var(--color-bg-card)",
            color: "var(--color-text-primary)",
          }}
          required
        />
      </div>

      <div style={{ marginBottom: "12px" }}>
        <label
          htmlFor="description"
          style={{
            display: "block",
            fontSize: "12px",
            fontWeight: "bold",
            marginBottom: "4px",
          }}
        >
          Description
        </label>
        <textarea
          id="description"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder="Optional description..."
          maxLength={1000}
          rows={2}
          style={{
            width: "100%",
            padding: "6px 8px",
            border: "1px solid var(--color-border)",
            borderRadius: "4px",
            fontSize: "13px",
            resize: "vertical",
            backgroundColor: "var(--color-bg-card)",
            color: "var(--color-text-primary)",
          }}
        />
      </div>

      <div style={{ marginBottom: "12px" }}>
        <label
          style={{
            display: "block",
            fontSize: "12px",
            fontWeight: "bold",
            marginBottom: "4px",
          }}
        >
          Icon
        </label>
        <div style={{ display: "flex", gap: "4px", flexWrap: "wrap" }}>
          {COMMON_ICONS.map((iconOption) => (
            <button
              key={iconOption}
              type="button"
              onClick={() => setIcon(iconOption)}
              style={{
                fontSize: "20px",
                padding: "4px 8px",
                border:
                  icon === iconOption
                    ? "2px solid var(--color-primary)"
                    : "1px solid var(--color-border)",
                borderRadius: "4px",
                backgroundColor: "var(--color-bg-card)",
                cursor: "pointer",
              }}
            >
              {iconOption}
            </button>
          ))}
        </div>
      </div>

      <div style={{ marginBottom: "16px" }}>
        <label
          style={{
            display: "block",
            fontSize: "12px",
            fontWeight: "bold",
            marginBottom: "4px",
          }}
        >
          Color
        </label>
        <div style={{ display: "flex", gap: "4px" }}>
          {COMMON_COLORS.map((colorOption) => (
            <button
              key={colorOption}
              type="button"
              onClick={() => setColor(colorOption)}
              style={{
                width: "32px",
                height: "32px",
                border:
                  color === colorOption
                    ? "3px solid var(--color-text-main)"
                    : "1px solid var(--color-border)",
                borderRadius: "4px",
                backgroundColor: colorOption,
                cursor: "pointer",
              }}
              aria-label={`Color ${colorOption}`}
            />
          ))}
        </div>
      </div>

      <div style={{ display: "flex", gap: "8px", justifyContent: "flex-end" }}>
        <button
          type="button"
          onClick={onCancel}
          style={{
            padding: "8px 16px",
            fontSize: "13px",
            border: "1px solid var(--color-border)",
            borderRadius: "4px",
            backgroundColor: "var(--color-bg-card)",
            color: "var(--color-text-primary)",
            cursor: "pointer",
          }}
        >
          Cancel
        </button>
        <button
          type="submit"
          style={{
            padding: "8px 16px",
            fontSize: "13px",
            border: "none",
            borderRadius: "4px",
            backgroundColor: "var(--color-primary)",
            color: "white",
            cursor: "pointer",
          }}
        >
          {workspace ? "Update" : "Create"}
        </button>
      </div>
    </form>
  );
};
