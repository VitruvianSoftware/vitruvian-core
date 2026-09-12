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

/* eslint-disable @typescript-eslint/no-explicit-any */
import { render, screen } from "@testing-library/react";
import "@testing-library/jest-dom";
import { SortableNavItem } from "./SortableNavItem";

// Mock dnd-kit with isDragging = true to cover the conditional branches
jest.mock("@dnd-kit/sortable", () => ({
  useSortable: () => ({
    attributes: { "data-testid": "sortable-attrs" },
    listeners: {},
    setNodeRef: jest.fn(),
    transform: { x: 10, y: 20, scaleX: 1, scaleY: 1 },
    transition: "transform 200ms",
    isDragging: true,
  }),
}));

jest.mock("@dnd-kit/utilities", () => ({
  CSS: {
    Transform: {
      toString: (transform: any) =>
        transform ? `translate3d(${transform.x}px, ${transform.y}px, 0)` : null,
    },
  },
}));

describe("SortableNavItem isDragging state", () => {
  it("should apply dragging styles when isDragging is true", () => {
    const { container } = render(
      <SortableNavItem id="ws-dragging">
        <span>Dragging Content</span>
      </SortableNavItem>,
    );

    expect(screen.getByText("Dragging Content")).toBeInTheDocument();

    // Check that the wrapper div exists
    const wrapper = container.firstChild as HTMLElement;
    expect(wrapper).toBeInTheDocument();

    // The styles should include opacity: 0.5 and zIndex: 999 when dragging
    expect(wrapper.style.opacity).toBe("0.5");
    expect(wrapper.style.zIndex).toBe("999");
  });

  it("should apply transform when dragging", () => {
    const { container } = render(
      <SortableNavItem id="ws-transform">
        <span>Transform Content</span>
      </SortableNavItem>,
    );

    const wrapper = container.firstChild as HTMLElement;
    expect(wrapper.style.transform).toBe("translate3d(10px, 20px, 0)");
  });
});
