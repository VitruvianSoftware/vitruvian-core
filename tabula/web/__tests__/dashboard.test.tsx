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

import { render, screen, fireEvent } from "@testing-library/react";
import DashboardPage from "@/app/page";
import { useWorkspaceStore } from "@/lib/store";
import { exportWorkspaces, seedDemoData } from "@/lib/data";

// Mock dependencies
jest.mock("@/lib/store", () => ({
  useWorkspaceStore: jest.fn(),
}));

jest.mock("@/lib/data", () => ({
  exportWorkspaces: jest.fn(),
  downloadFile: jest.fn(),
  seedDemoData: jest.fn(),
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

describe("Dashboard Page (Home)", () => {
  const mockFetchStats = jest.fn();
  const mockLogin = jest.fn();
  const mockLogout = jest.fn();

  const defaultState = {
    stats: {
      totalWorkspaces: 1,
      totalTabs: 5,
      totalResources: 2,
      totalNotes: 1,
      totalTasks: 2,
      completedTasks: 1,
    },
    dataSource: {
      type: "local-storage",
      available: true,
      message: "Local storage",
    },
    loading: false,
    error: null,
    fetchStats: mockFetchStats,
    user: null,
    login: mockLogin,
    logout: mockLogout,
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (useWorkspaceStore as unknown as jest.Mock).mockReturnValue(defaultState);
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it("should show loading state", () => {
    (useWorkspaceStore as unknown as jest.Mock).mockReturnValue({
      ...defaultState,
      loading: true,
    });

    render(<DashboardPage />);
    expect(screen.getByText("Loading...")).toBeInTheDocument();
  });

  it("should show error state and allow retry", () => {
    (useWorkspaceStore as unknown as jest.Mock).mockReturnValue({
      ...defaultState,
      error: "Failed to load",
    });

    render(<DashboardPage />);
    expect(screen.getByText("Failed to load")).toBeInTheDocument();

    const retryBtn = screen.getByText("Retry");
    fireEvent.click(retryBtn);
    expect(mockFetchStats).toHaveBeenCalled();
  });

  it("should render stats correctly", () => {
    render(<DashboardPage />);
    expect(screen.getByText("Tabula Dashboard")).toBeInTheDocument();
    // Use getAllByText for '1' since it appears twice (Workspaces and Notes)
    expect(screen.getAllByText("1").length).toBeGreaterThanOrEqual(2);
    expect(screen.getByText("1/2")).toBeInTheDocument(); // tasks completed/total
    expect(screen.getByText("50%")).toBeInTheDocument(); // completion rate
  });

  it("should show user info and logout when authenticated", () => {
    (useWorkspaceStore as unknown as jest.Mock).mockReturnValue({
      ...defaultState,
      user: { name: "John Doe", email: "john@example.com", picture: "pic.jpg" },
    });

    render(<DashboardPage />);
    expect(screen.getByText("John Doe")).toBeInTheDocument();
    expect(screen.getByText("john@example.com")).toBeInTheDocument();

    const logoutBtn = screen.getByText("Logout");
    fireEvent.click(logoutBtn);
    expect(mockLogout).toHaveBeenCalled();
  });

  it("should allow login when not authenticated", () => {
    render(<DashboardPage />);
    const loginBtn = screen.getByText("Login");
    fireEvent.click(loginBtn);
    expect(mockLogin).toHaveBeenCalled();
  });

  it("should allow loading demo data when empty", () => {
    (useWorkspaceStore as unknown as jest.Mock).mockReturnValue({
      ...defaultState,
      stats: { totalWorkspaces: 0 },
      dataSource: { type: "none", available: true, message: "No data" },
    });

    render(<DashboardPage />);
    const demoBtn = screen.getByText("Load Demo Data");
    fireEvent.click(demoBtn);
    expect(seedDemoData).toHaveBeenCalled();
  });

  it("should handle export click", async () => {
    (exportWorkspaces as jest.Mock).mockResolvedValue("fake-csv-content");

    render(<DashboardPage />);
    const exportBtn = screen.getByText("Export JSON"); // Export JSON is hidden if workspaces > 0? No, it's visible.
    // Wait, line 130 in page.tsx: (stats?.totalWorkspaces || 0) > 0 && (...)

    fireEvent.click(exportBtn);

    // Wait for async export
    await jest.runAllTimersAsync?.(); // Note: might need better way to wait for microtasks
    // Since handleExport is async, we can just check if exportWorkspaces was called
    expect(exportWorkspaces).toHaveBeenCalledWith("json");
  });
});
