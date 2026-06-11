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
import { render, screen, fireEvent } from "@testing-library/react";
import "@testing-library/jest-dom";
import { WorkspaceForm } from "./WorkspaceForm";
import type { Workspace } from "../types";

describe("WorkspaceForm", () => {
  const mockOnSubmit = jest.fn();
  const mockOnCancel = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should render empty form for new workspace", () => {
    render(<WorkspaceForm onSubmit={mockOnSubmit} onCancel={mockOnCancel} />);

    expect(screen.getByLabelText("Name *")).toHaveValue("");
    expect(screen.getByLabelText("Description")).toHaveValue("");
    expect(screen.getByText("Create")).toBeInTheDocument();
  });

  it("should render form with existing workspace data", () => {
    const workspace: Workspace = {
      id: "ws1",
      name: "Test Workspace",
      description: "Test description",
      icon: "💼",
      color: "#DC2626",
      tabs: [],
      resources: [],
      sections: [],
      notes: [],
      tasks: [],
      position: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };

    render(
      <WorkspaceForm
        workspace={workspace}
        onSubmit={mockOnSubmit}
        onCancel={mockOnCancel}
      />,
    );

    expect(screen.getByLabelText("Name *")).toHaveValue("Test Workspace");
    expect(screen.getByLabelText("Description")).toHaveValue(
      "Test description",
    );
    expect(screen.getByText("Update")).toBeInTheDocument();
  });

  it("should call onSubmit with form data", () => {
    render(<WorkspaceForm onSubmit={mockOnSubmit} onCancel={mockOnCancel} />);

    fireEvent.change(screen.getByLabelText("Name *"), {
      target: { value: "New Workspace" },
    });
    fireEvent.change(screen.getByLabelText("Description"), {
      target: { value: "A new workspace" },
    });

    fireEvent.click(screen.getByText("Create"));

    expect(mockOnSubmit).toHaveBeenCalledWith({
      name: "New Workspace",
      description: "A new workspace",
      icon: "📁",
      color: "#4F46E5",
    });
  });

  it("should not submit with empty name", () => {
    render(<WorkspaceForm onSubmit={mockOnSubmit} onCancel={mockOnCancel} />);

    fireEvent.click(screen.getByText("Create"));

    expect(mockOnSubmit).not.toHaveBeenCalled();
  });

  it("should call onCancel when cancel button clicked", () => {
    render(<WorkspaceForm onSubmit={mockOnSubmit} onCancel={mockOnCancel} />);

    fireEvent.click(screen.getByText("Cancel"));

    expect(mockOnCancel).toHaveBeenCalled();
  });

  it("should allow icon selection", () => {
    render(<WorkspaceForm onSubmit={mockOnSubmit} onCancel={mockOnCancel} />);

    fireEvent.click(screen.getByText("💼"));

    fireEvent.change(screen.getByLabelText("Name *"), {
      target: { value: "Test" },
    });
    fireEvent.click(screen.getByText("Create"));

    expect(mockOnSubmit).toHaveBeenCalledWith(
      expect.objectContaining({ icon: "💼" }),
    );
  });

  it("should allow color selection", () => {
    render(<WorkspaceForm onSubmit={mockOnSubmit} onCancel={mockOnCancel} />);

    fireEvent.click(screen.getByLabelText("Color #DC2626"));

    fireEvent.change(screen.getByLabelText("Name *"), {
      target: { value: "Test" },
    });
    fireEvent.click(screen.getByText("Create"));

    expect(mockOnSubmit).toHaveBeenCalledWith(
      expect.objectContaining({ color: "#DC2626" }),
    );
  });

  it("should display all icon options", () => {
    render(<WorkspaceForm onSubmit={mockOnSubmit} onCancel={mockOnCancel} />);

    expect(screen.getByText("📁")).toBeInTheDocument();
    expect(screen.getByText("💼")).toBeInTheDocument();
    expect(screen.getByText("🎨")).toBeInTheDocument();
    expect(screen.getByText("🔬")).toBeInTheDocument();
  });
});
