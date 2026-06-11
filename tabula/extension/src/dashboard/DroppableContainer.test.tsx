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
 * Tests for DroppableContainer component
 *
 * Tests the droppable functionality wrapper using dnd-kit.
 */

import "@testing-library/jest-dom";
import { render, screen } from "@testing-library/react";
import { DndContext } from "@dnd-kit/core";
import { DroppableContainer } from "./DroppableContainer";

// Wrap component with DndContext for testing
const renderWithDndContext = (ui: React.ReactElement) => {
  return render(<DndContext>{ui}</DndContext>);
};

describe("DroppableContainer", () => {
  it("should render children", () => {
    renderWithDndContext(
      <DroppableContainer id="test-container">
        <div data-testid="child">Child Content</div>
      </DroppableContainer>,
    );

    expect(screen.getByTestId("child")).toBeInTheDocument();
    expect(screen.getByText("Child Content")).toBeInTheDocument();
  });

  it("should apply className when provided", () => {
    renderWithDndContext(
      <DroppableContainer id="test-container" className="custom-class">
        <div>Content</div>
      </DroppableContainer>,
    );

    const container = screen.getByText("Content").parentElement;
    expect(container).toHaveClass("custom-class");
  });

  it("should default containerType to section", () => {
    const { container } = renderWithDndContext(
      <DroppableContainer id="test-section">
        <div>Section Content</div>
      </DroppableContainer>,
    );

    // The component should render without errors with default containerType
    expect(container.firstChild).toBeInTheDocument();
  });

  it("should accept group containerType", () => {
    const { container } = renderWithDndContext(
      <DroppableContainer id="test-group" containerType="group">
        <div>Group Content</div>
      </DroppableContainer>,
    );

    expect(container.firstChild).toBeInTheDocument();
    expect(screen.getByText("Group Content")).toBeInTheDocument();
  });

  it("should have transition style for outline", () => {
    renderWithDndContext(
      <DroppableContainer id="test-container">
        <div>Content</div>
      </DroppableContainer>,
    );

    const container = screen.getByText("Content").parentElement;
    expect(container).toHaveStyle({ transition: "outline 0.15s ease" });
  });
});
