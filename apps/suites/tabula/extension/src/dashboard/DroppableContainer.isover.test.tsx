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
import { DroppableContainer } from "./DroppableContainer";

// Mock dnd-kit with isOver = true to cover the conditional branches
jest.mock("@dnd-kit/core", () => ({
  useDroppable: () => ({
    setNodeRef: jest.fn(),
    isOver: true,
  }),
  DndContext: ({ children }: any) => <>{children}</>,
}));

describe("DroppableContainer isOver state", () => {
  it("should apply dashed outline when isOver is true for section", () => {
    const { container } = render(
      <DroppableContainer id="section-isover">
        <span>Section Content</span>
      </DroppableContainer>,
    );

    expect(screen.getByText("Section Content")).toBeInTheDocument();

    // Check that the wrapper div has the outline style
    const wrapper = container.firstChild as HTMLElement;
    expect(wrapper.style.outline).toBe(
      "2px dashed var(--color-accent-primary)",
    );
  });

  it("should apply dashed outline when isOver is true for group", () => {
    const { container } = render(
      <DroppableContainer id="group-isover" containerType="group">
        <span>Group Content</span>
      </DroppableContainer>,
    );

    const wrapper = container.firstChild as HTMLElement;
    expect(wrapper.style.outline).toBe(
      "2px dashed var(--color-accent-primary)",
    );
  });
});
