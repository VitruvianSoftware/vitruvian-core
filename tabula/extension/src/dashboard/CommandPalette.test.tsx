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

import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import "@testing-library/jest-dom";
import { CommandPalette } from "./CommandPalette";
import { useWorkspaceStore } from "../stores/workspace";

// Mock the workspace store
jest.mock("../stores/workspace");

// Mock chrome API
(globalThis as unknown as { chrome: unknown }).chrome = {
  tabs: {
    create: jest.fn(),
  },
};

const mockWorkspaces = [
  {
    id: "ws1",
    name: "Test Workspace 1",
    description: "First workspace",
    position: 0,
    tabs: [
      { id: 1, url: "https://example.com", title: "Example Site" },
      { id: 2, url: "https://github.com", title: "GitHub" },
    ],
    resources: [
      {
        id: "r1",
        url: "https://docs.example.com",
        title: "Documentation",
        createdAt: Date.now(),
      },
    ],
    sections: [
      {
        id: "s1",
        title: "Development",
        resources: [
          {
            id: "r2",
            url: "https://stackoverflow.com",
            title: "Stack Overflow",
            createdAt: Date.now(),
          },
        ],
      },
    ],
    notes: [
      {
        id: "n1",
        title: "Meeting Notes",
        content: "Important meeting",
        updatedAt: Date.now(),
      },
    ],
    tasks: [
      { id: "t1", title: "Review PR", completed: false, createdAt: Date.now() },
    ],
    createdAt: Date.now(),
    updatedAt: Date.now(),
  },
  {
    id: "ws2",
    name: "Test Workspace 2",
    description: "Second workspace",
    position: 1,
    tabs: [],
    resources: [],
    sections: [],
    notes: [],
    tasks: [],
    createdAt: Date.now(),
    updatedAt: Date.now(),
  },
];

describe("CommandPalette", () => {
  const mockSwitchWorkspace = jest.fn();
  const mockOnClose = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    (useWorkspaceStore as unknown as jest.Mock).mockReturnValue({
      workspaces: mockWorkspaces,
      switchWorkspace: mockSwitchWorkspace,
    });
  });

  it("should not render when isOpen is false", () => {
    const { container } = render(
      <CommandPalette isOpen={false} onClose={mockOnClose} />,
    );
    expect(
      container.querySelector(".command-palette-overlay"),
    ).not.toBeInTheDocument();
  });

  it("should render when isOpen is true", () => {
    render(<CommandPalette isOpen={true} onClose={mockOnClose} />);
    expect(
      screen.getByPlaceholderText(/Search workspaces/i),
    ).toBeInTheDocument();
  });

  it("should display initial results", () => {
    render(<CommandPalette isOpen={true} onClose={mockOnClose} />);
    expect(screen.getByText("Test Workspace 1")).toBeInTheDocument();
    expect(screen.getByText("Test Workspace 2")).toBeInTheDocument();
  });

  it("should filter results based on search query", async () => {
    render(<CommandPalette isOpen={true} onClose={mockOnClose} />);
    const input = screen.getByPlaceholderText(/Search workspaces/i);

    fireEvent.change(input, { target: { value: "Example Site" } });

    await waitFor(() => {
      expect(screen.getByText("Example Site")).toBeInTheDocument();
    });
  });

  it("should handle keyboard navigation with arrow keys", async () => {
    render(<CommandPalette isOpen={true} onClose={mockOnClose} />);

    // Press down arrow
    fireEvent.keyDown(document, { key: "ArrowDown" });

    // Check that second item is selected
    const results = document.querySelectorAll(".command-palette-result");
    expect(results[1]).toHaveClass("selected");
  });

  it("should close on Escape key", () => {
    render(<CommandPalette isOpen={true} onClose={mockOnClose} />);

    fireEvent.keyDown(document, { key: "Escape" });

    expect(mockOnClose).toHaveBeenCalled();
  });

  it("should handle workspace selection", async () => {
    render(<CommandPalette isOpen={true} onClose={mockOnClose} />);

    const workspaceResult = screen.getByText("Test Workspace 1");
    fireEvent.click(workspaceResult);

    await waitFor(() => {
      expect(mockSwitchWorkspace).toHaveBeenCalledWith("ws1");
      expect(mockOnClose).toHaveBeenCalled();
    });
  });

  it("should open resource URL in new tab", async () => {
    render(<CommandPalette isOpen={true} onClose={mockOnClose} />);

    const resourceResult = screen.getByText("Documentation");
    fireEvent.click(resourceResult);

    await waitFor(() => {
      expect(chrome.tabs.create).toHaveBeenCalledWith({
        url: "https://docs.example.com",
        active: true,
      });
      expect(mockOnClose).toHaveBeenCalled();
    });
  });

  it("should handle Enter key to select result", async () => {
    render(<CommandPalette isOpen={true} onClose={mockOnClose} />);

    // First result should be selected by default
    fireEvent.keyDown(document, { key: "Enter" });

    await waitFor(() => {
      expect(mockSwitchWorkspace).toHaveBeenCalled();
      expect(mockOnClose).toHaveBeenCalled();
    });
  });

  it('should display "No results found" for invalid search', () => {
    render(<CommandPalette isOpen={true} onClose={mockOnClose} />);
    const input = screen.getByPlaceholderText(/Search workspaces/i);

    // Change the input value
    fireEvent.change(input, { target: { value: "xyznonexistent12345" } });

    // Since the filtering happens in useMemo and should be synchronous,
    // check if results are filtered
    const results = document.querySelectorAll(".command-palette-result");
    expect(results.length).toBe(0);
  });

  it("should index resources in sections", () => {
    render(<CommandPalette isOpen={true} onClose={mockOnClose} />);
    expect(screen.getByText("Stack Overflow")).toBeInTheDocument();
  });

  it("should index notes", () => {
    render(<CommandPalette isOpen={true} onClose={mockOnClose} />);
    expect(screen.getByText("Meeting Notes")).toBeInTheDocument();
  });

  it("should index tasks", () => {
    render(<CommandPalette isOpen={true} onClose={mockOnClose} />);
    expect(screen.getByText("Review PR")).toBeInTheDocument();
  });

  it("should focus input when opened", async () => {
    render(<CommandPalette isOpen={true} onClose={mockOnClose} />);

    await waitFor(() => {
      const input = screen.getByPlaceholderText(/Search workspaces/i);
      expect(document.activeElement).toBe(input);
    });
  });

  it("should close when clicking overlay", () => {
    render(<CommandPalette isOpen={true} onClose={mockOnClose} />);

    const overlay = document.querySelector(".command-palette-overlay");
    fireEvent.click(overlay!);

    expect(mockOnClose).toHaveBeenCalled();
  });
});
