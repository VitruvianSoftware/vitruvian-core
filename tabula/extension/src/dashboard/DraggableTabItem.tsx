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
import type { Tab } from "../types";
import { Icon } from "../components/icons";
import { getFaviconSrc } from "../utils/favicon";

export interface DraggableTabItemProps {
  tab: Tab;
  onClose: () => void;
  onEdit: () => void;
  onActivate: () => void;
}

/**
 * Sortable Tab Item Component for "Open Tabs"
 * We use a different component to distinguish types in drag handling
 */
export const DraggableTabItem: React.FC<DraggableTabItemProps> = ({
  tab,
  onClose,
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
    id: `tab-${tab.id}`,
    data: { type: "tab", tab },
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      className="list-item"
      data-testid="tab-item"
    >
      {/* Draggable area - only this part gets drag listeners */}
      <div
        {...attributes}
        {...listeners}
        style={{
          display: "flex",
          alignItems: "center",
          flex: 1,
          cursor: "grab",
          minWidth: 0,
        }}
        data-testid="tab-drag-handle"
      >
        <img src={getFaviconSrc(tab)} className="item-icon" alt="" />
        <div className="item-content">
          <div className="item-title">{tab.title}</div>
          <div className="item-subtitle">{tab.url}</div>
        </div>
      </div>
      {/* Action buttons - outside of drag listeners */}
      <div className="item-actions">
        <button
          className="btn-icon"
          onClick={(e) => {
            e.stopPropagation();
            onActivate();
          }}
          title="Focus Tab"
        >
          <Icon name="open_in_new" size="sm" />
        </button>
        <button
          className="btn-icon"
          onClick={(e) => {
            e.stopPropagation();
            onEdit();
          }}
          title="Edit"
        >
          <Icon name="edit" size="sm" />
        </button>
        <button
          className="btn-icon danger"
          onClick={(e) => {
            e.stopPropagation();
            onClose();
          }}
          title="Close Tab"
        >
          <Icon name="close" size="sm" />
        </button>
      </div>
    </div>
  );
};
