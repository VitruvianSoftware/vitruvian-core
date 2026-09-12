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
import { WorkspaceCard } from "./WorkspaceCard";
import type { Workspace } from "../types";

describe("WorkspaceCard", () => {
  const mockWorkspace: Workspace = {
    id: "ws1",
    name: "Test Workspace",
    icon: "📁",
    description: "A test workspace",
    tabs: [{ id: 1, url: "https://test.com", title: "Test" }] as any,
    resources: [],
    sections: [],
    notes: [],
    tasks: [],
    position: 0,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };

  const mockHandlers = {
    onSaveTabs: jest.fn(),
    onRestoreTabs: jest.fn(),
    onSwitch: jest.fn(),
    onEdit: jest.fn(),
    onDelete: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should render workspace name and tab count", () => {
    render(
      <WorkspaceCard
        workspace={mockWorkspace}
        isActive={false}
        {...mockHandlers}
      />,
    );

    expect(screen.getByText("Test Workspace")).toBeInTheDocument();
    expect(screen.getByText("1 tabs")).toBeInTheDocument();
  });

  it("should show active badge when active", () => {
    render(
      <WorkspaceCard
        workspace={mockWorkspace}
        isActive={true}
        {...mockHandlers}
      />,
    );

    expect(screen.getByText("ACTIVE")).toBeInTheDocument();
  });

  it("should not show switch button when active", () => {
    render(
      <WorkspaceCard
        workspace={mockWorkspace}
        isActive={true}
        {...mockHandlers}
      />,
    );

    expect(screen.queryByText("Switch")).not.toBeInTheDocument();
  });

  it("should show switch button when not active", () => {
    render(
      <WorkspaceCard
        workspace={mockWorkspace}
        isActive={false}
        {...mockHandlers}
      />,
    );

    expect(screen.getByText("Switch")).toBeInTheDocument();
  });

  it("should call onSaveTabs when save button clicked", () => {
    render(
      <WorkspaceCard
        workspace={mockWorkspace}
        isActive={false}
        {...mockHandlers}
      />,
    );

    fireEvent.click(screen.getByText("Save Tabs"));
    expect(mockHandlers.onSaveTabs).toHaveBeenCalled();
  });

  it("should call onRestoreTabs when restore button clicked", () => {
    render(
      <WorkspaceCard
        workspace={mockWorkspace}
        isActive={false}
        {...mockHandlers}
      />,
    );

    fireEvent.click(screen.getByText("Restore"));
    expect(mockHandlers.onRestoreTabs).toHaveBeenCalled();
  });

  it("should call onSwitch when switch button clicked", () => {
    render(
      <WorkspaceCard
        workspace={mockWorkspace}
        isActive={false}
        {...mockHandlers}
      />,
    );

    fireEvent.click(screen.getByText("Switch"));
    expect(mockHandlers.onSwitch).toHaveBeenCalled();
  });

  it("should call onEdit when edit button clicked", () => {
    render(
      <WorkspaceCard
        workspace={mockWorkspace}
        isActive={false}
        {...mockHandlers}
      />,
    );

    fireEvent.click(screen.getByText("Edit"));
    expect(mockHandlers.onEdit).toHaveBeenCalled();
  });

  it("should call onDelete when delete button clicked", () => {
    render(
      <WorkspaceCard
        workspace={mockWorkspace}
        isActive={false}
        {...mockHandlers}
      />,
    );

    fireEvent.click(screen.getByText("Delete"));
    expect(mockHandlers.onDelete).toHaveBeenCalled();
  });

  it("should render description when present", () => {
    render(
      <WorkspaceCard
        workspace={mockWorkspace}
        isActive={false}
        {...mockHandlers}
      />,
    );

    expect(screen.getByText("A test workspace")).toBeInTheDocument();
  });

  it("should disable restore button when no tabs", () => {
    const emptyWorkspace = { ...mockWorkspace, tabs: [] };

    render(
      <WorkspaceCard
        workspace={emptyWorkspace}
        isActive={false}
        {...mockHandlers}
      />,
    );

    expect(screen.getByText("Restore")).toBeDisabled();
  });

  it("should disable switch button when no tabs", () => {
    const emptyWorkspace = { ...mockWorkspace, tabs: [] };

    render(
      <WorkspaceCard
        workspace={emptyWorkspace}
        isActive={false}
        {...mockHandlers}
      />,
    );

    expect(screen.getByText("Switch")).toBeDisabled();
  });
});
