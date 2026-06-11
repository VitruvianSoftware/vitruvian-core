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
import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import type { Resource } from "../types";
import { Icon } from "../components/icons";

export interface SortableResourceItemProps {
  resource: Resource;
  onRemove: (e: React.MouseEvent) => void;
  onEdit: (e: React.MouseEvent) => void;
  onActivate: () => void;
}

export const SortableResourceItem: React.FC<SortableResourceItemProps> = ({
  resource,
  onRemove,
  onEdit,
  onActivate,
}) => {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({
    id: resource.id,
    data: { resource },
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
    cursor: "pointer",
  };

  return (
    <div
      ref={setNodeRef}
      style={{ ...style, cursor: "grab" }}
      className="list-item"
      data-testid="resource-item"
    >
      {/* Draggable area */}
      <div
        {...attributes}
        {...listeners}
        style={{ display: "flex", alignItems: "center", flex: 1, minWidth: 0 }}
      >
        <img
          src={
            resource.faviconUrl ||
            `https://www.google.com/s2/favicons?domain=${resource.url}`
          }
          className="item-icon"
          alt=""
        />
        <div className="item-content">
          <div className="item-title">{resource.title}</div>
          <div className="item-subtitle">{resource.url}</div>
        </div>
      </div>
      {/* Action buttons */}
      <div className="item-actions">
        <button
          className="btn-icon"
          onPointerDown={(e) => e.stopPropagation()}
          onClick={(e) => {
            e.stopPropagation();
            onActivate();
          }}
          title="Open Link"
        >
          <Icon name="open_in_new" size="sm" />
        </button>
        <button
          className="btn-icon"
          onPointerDown={(e) => e.stopPropagation()}
          onClick={(e) => {
            e.stopPropagation();
            onEdit(e);
          }}
          title="Edit"
        >
          <Icon name="edit" size="sm" />
        </button>
        <button
          className="btn-icon danger"
          onPointerDown={(e) => e.stopPropagation()}
          onClick={onRemove}
          title="Remove"
        >
          <Icon name="close" size="sm" />
        </button>
      </div>
    </div>
  );
};
