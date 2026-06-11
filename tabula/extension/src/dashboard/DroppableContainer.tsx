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
import { useDroppable } from "@dnd-kit/core";

export interface DroppableContainerProps {
  id: string;
  children: React.ReactNode;
  className?: string;
  containerType?: "section" | "group";
  style?: React.CSSProperties;
}

export const DroppableContainer: React.FC<DroppableContainerProps> = ({
  id,
  children,
  className,
  containerType = "section",
  style,
}) => {
  const { setNodeRef, isOver } = useDroppable({
    id,
    data: { type: containerType, [`${containerType}Id`]: id },
  });

  return (
    <div
      id={id}
      ref={setNodeRef}
      className={className}
      style={{
        ...style,
        outline:
          isOver && (containerType === "section" || containerType === "group")
            ? "2px dashed var(--color-accent-primary)"
            : "none",
        transition: "outline 0.15s ease",
      }}
    >
      {children}
    </div>
  );
};
