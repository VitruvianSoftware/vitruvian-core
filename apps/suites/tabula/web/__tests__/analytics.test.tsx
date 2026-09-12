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
import AnalyticsPage from "@/app/analytics/page";
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

describe("Analytics Page", () => {
  const mockFetchWorkspaces = jest.fn();

  const mockWorkspaces = [
    {
      id: "ws-1",
      name: "Workspace 1",
      tabs: [{ id: 1 }, { id: 2 }],
      resources: [{ id: "r1" }],
      sections: [{ resources: [{ id: "sr1" }] }],
      notes: [{ id: "n1" }],
      tasks: [
        { id: "t1", completed: true },
        { id: "t2", completed: false },
      ],
    },
    {
      id: "ws-2",
      name: "Workspace 2",
      tabs: [{ id: 3 }],
      resources: [],
      sections: [],
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

    render(<AnalyticsPage />);
    expect(screen.getByText("Loading analytics...")).toBeInTheDocument();
  });

  it("should show error state and allow retry", () => {
    (useWorkspaceStore as unknown as jest.Mock).mockReturnValue({
      ...defaultState,
      error: "Failed to load",
    });

    render(<AnalyticsPage />);
    expect(screen.getByText("Failed to load")).toBeInTheDocument();

    const retryBtn = screen.getByText("Retry");
    fireEvent.click(retryBtn);
    expect(mockFetchWorkspaces).toHaveBeenCalled();
  });

  it("should calculate and render summary metrics", () => {
    render(<AnalyticsPage />);
    expect(screen.getByText("Total Workspaces")).toBeInTheDocument();
    // Use getAllByText for '2' since it appears twice (Workspaces and Resources)
    expect(screen.getAllByText("2").length).toBeGreaterThanOrEqual(2);
    // Use getAllByText for '3' since it appears twice (Total Tabs and Active Tabs)
    expect(screen.getAllByText("3").length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText("50%")).toBeInTheDocument(); // task completion rate
  });

  it("should render workspace distribution", () => {
    render(<AnalyticsPage />);
    expect(screen.getByText("Workspace Distribution")).toBeInTheDocument();
    expect(screen.getAllByText("Workspace 1").length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText("2 tabs")).toBeInTheDocument();
    expect(screen.getAllByText("Workspace 2").length).toBeGreaterThanOrEqual(1);
    expect(screen.getByText("1 tabs")).toBeInTheDocument();
  });

  it("should render insights correctly", () => {
    render(<AnalyticsPage />);
    expect(screen.getByText("Insights")).toBeInTheDocument();
    // Use getAllByText for 'Workspace 1' since it appears in distribution and insights
    expect(screen.getAllByText("Workspace 1").length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText("has the most tabs (2)")).toBeInTheDocument();
  });

  it("should handle empty workspaces gracefully", () => {
    (useWorkspaceStore as unknown as jest.Mock).mockReturnValue({
      ...defaultState,
      workspaces: [],
    });

    render(<AnalyticsPage />);
    expect(screen.getByText("No workspaces to display.")).toBeInTheDocument();
    expect(screen.getByText("N/A")).toBeInTheDocument(); // Task completion
  });
});
