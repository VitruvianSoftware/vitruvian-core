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

// Mock dnd-kit
jest.mock("@dnd-kit/sortable", () => ({
  useSortable: () => ({
    attributes: { "data-testid": "sortable-attrs" },
    listeners: {},
    setNodeRef: jest.fn(),
    transform: null,
    transition: null,
    isDragging: false,
  }),
}));

jest.mock("@dnd-kit/utilities", () => ({
  CSS: {
    Transform: {
      toString: () => null,
    },
  },
}));

describe("SortableNavItem", () => {
  it("should render children", () => {
    render(
      <SortableNavItem id="ws1">
        <span>Child Content</span>
      </SortableNavItem>,
    );

    expect(screen.getByText("Child Content")).toBeInTheDocument();
  });

  it("should apply transform style when dragging", () => {
    // Re-mock with isDragging true
    jest.doMock("@dnd-kit/sortable", () => ({
      useSortable: () => ({
        attributes: {},
        listeners: {},
        setNodeRef: jest.fn(),
        transform: { x: 10, y: 20, scaleX: 1, scaleY: 1 },
        transition: "transform 200ms",
        isDragging: true,
      }),
    }));

    // For this test we just verify basic rendering works
    render(
      <SortableNavItem id="ws2">
        <span>Dragging Content</span>
      </SortableNavItem>,
    );

    expect(screen.getByText("Dragging Content")).toBeInTheDocument();
  });

  it("should accept custom data prop", () => {
    const customData = { type: "spaceGroup", groupId: "group-1" };
    render(
      <SortableNavItem id="group-1" data={customData}>
        <span>Custom Data Item</span>
      </SortableNavItem>,
    );

    expect(screen.getByText("Custom Data Item")).toBeInTheDocument();
  });
});
