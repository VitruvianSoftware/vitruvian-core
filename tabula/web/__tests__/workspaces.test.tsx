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
import { render, screen, fireEvent } from "@testing-library/react";
import WorkspacesPage from "@/app/workspaces/page";
import { useWorkspaceStore } from "@/lib/store";

// Mock dependencies
jest.mock("@/lib/store", () => ({
  useWorkspaceStore: jest.fn(),
}));

// Mock Next.js Link
jest.mock("next/link", () => {
  return function MockLink({
    children,
    href,
  }: {
    children: React.ReactNode;
    href: string;
  }) {
    return <a href={href}>{children}</a>;
  };
});

describe("Workspaces Page", () => {
  const mockFetchWorkspaces = jest.fn();

  const mockWorkspaces = [
    {
      id: "ws-1",
      name: "Project Alpha",
      description: "The first project",
      icon: "🚀",
      tabs: [
        { id: 1, title: "Tab 1", url: "https://a.com" },
        { id: 2, title: "Tab 2", url: "https://b.com" },
      ],
      resources: [{ id: "r1" }],
      notes: [],
      tasks: [],
    },
    {
      id: "ws-2",
      name: "Marketing",
      description: "Campaign stuff",
      icon: "📢",
      tabs: [],
      resources: [],
      notes: [],
      tasks: [],
    },
  ];

  const defaultState = {
    workspaces: mockWorkspaces,
    dataSource: {
      type: "local-storage",
      available: true,
      message: "Local storage",
    },
    loading: false,
    error: null,
    fetchWorkspaces: mockFetchWorkspaces,
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (useWorkspaceStore as unknown as jest.Mock).mockReturnValue(defaultState);
  });

  it("should show loading state", () => {
    (useWorkspaceStore as unknown as jest.Mock).mockReturnValue({
      ...defaultState,
      loading: true,
    });

    render(<WorkspacesPage />);
    expect(screen.getByText("Loading workspaces...")).toBeInTheDocument();
  });

  it("should show error state", () => {
    (useWorkspaceStore as unknown as jest.Mock).mockReturnValue({
      ...defaultState,
      error: "Failed to load",
    });

    render(<WorkspacesPage />);
    expect(screen.getByText("Failed to load")).toBeInTheDocument();
  });

  it("should render workspace cards", () => {
    render(<WorkspacesPage />);
    expect(screen.getByText("Project Alpha")).toBeInTheDocument();
    expect(screen.getByText("Marketing")).toBeInTheDocument();
    expect(screen.getByText("The first project")).toBeInTheDocument();
    expect(screen.getByText("🚀")).toBeInTheDocument();
  });

  it("should filter workspaces based on search query", () => {
    render(<WorkspacesPage />);
    const searchInput = screen.getByPlaceholderText("Search workspaces...");

    fireEvent.change(searchInput, { target: { value: "Alpha" } });

    expect(screen.getByText("Project Alpha")).toBeInTheDocument();
    expect(screen.queryByText("Marketing")).not.toBeInTheDocument();
  });

  it("should show empty state when no matches", () => {
    render(<WorkspacesPage />);
    const searchInput = screen.getByPlaceholderText("Search workspaces...");

    fireEvent.change(searchInput, { target: { value: "Nonexistent" } });

    expect(
      screen.getByText("No workspaces found matching your search."),
    ).toBeInTheDocument();
  });

  it("should show empty state when no workspaces at all", () => {
    (useWorkspaceStore as unknown as jest.Mock).mockReturnValue({
      ...defaultState,
      workspaces: [],
    });

    render(<WorkspacesPage />);
    expect(screen.getByText("No workspaces yet.")).toBeInTheDocument();
  });
});
