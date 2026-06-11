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
import { render, screen } from "@testing-library/react";
import { GhostOverlay } from "./GhostOverlay";
import { Workspace, SpaceGroup, Resource, Tab } from "../types";

// Mock DragOverlay since we just want to test content rendering
jest.mock("@dnd-kit/core", () => ({
  DragOverlay: ({ children }: { children: React.ReactNode }) => (
    <div>{children}</div>
  ),
}));

// Mock Icon component
jest.mock("../components/icons", () => ({
  Icon: ({ name }: { name: string }) => (
    <span data-testid={`icon-${name}`}>{name}</span>
  ),
}));

describe("GhostOverlay", () => {
  const mockTab: Tab = {
    id: 1,
    url: "https://example.com",
    title: "Example Tab",
    active: false,
    pinned: false,
    index: 0,
    favIconUrl: "https://example.com/favicon.ico",
  };

  const mockResource: Resource = {
    id: "res-1",
    url: "https://resource.com",
    title: "Example Resource",
    faviconUrl: "https://resource.com/favicon.ico",
    createdAt: 123,
  };

  const mockSection = {
    id: "sec-1",
    title: "Section 1",
    resources: [mockResource],
    collapsed: false,
  };

  const mockWorkspace: Workspace = {
    id: "ws-1",
    name: "Workspace 1",
    icon: "🚀",
    sections: [mockSection],
    tabs: [mockTab],
    notes: [],
    tasks: [],
    history: [],
    settings: {}, // Add required 'settings' property
  } as unknown as Workspace; // Cast to avoid missing optional props noise if any

  const mockSpaceGroup: SpaceGroup = {
    id: "group-1",
    title: "Group 1",
    collapsed: false,
    color: "#ff0000",
    position: 0,
    createdAt: 123,
    updatedAt: 123,
  };

  const defaultProps = {
    activeId: null,
    activeWorkspace: mockWorkspace,
    workspaces: [mockWorkspace],
    spaceGroups: [mockSpaceGroup],
  };

  it("renders nothing when activeId is null", () => {
    const { container } = render(<GhostOverlay {...defaultProps} />);
    expect(container).toBeEmptyDOMElement();
  });

  it("renders nothing when item is not found", () => {
    const { container } = render(
      <GhostOverlay {...defaultProps} activeId="unknown" />,
    );
    expect(container).toBeEmptyDOMElement();
  });

  it("renders Workspace ghost", () => {
    render(<GhostOverlay {...defaultProps} activeId="ws-1" />);
    expect(screen.getByText("Workspace 1")).toBeInTheDocument();
    expect(screen.getByText("1 tabs")).toBeInTheDocument();
    expect(screen.getByText("🚀")).toBeInTheDocument();
  });

  it("renders SpaceGroup ghost", () => {
    render(<GhostOverlay {...defaultProps} activeId="group-1" />);
    expect(screen.getByText("Group 1")).toBeInTheDocument();
    expect(screen.getByText("Space Group")).toBeInTheDocument();
    expect(screen.getByTestId("icon-folder_open")).toBeInTheDocument();
  });

  it("renders Section ghost", () => {
    render(<GhostOverlay {...defaultProps} activeId="sec-1" />);
    expect(screen.getByText("Section 1")).toBeInTheDocument();
    expect(screen.getByText("1 resources")).toBeInTheDocument();
    expect(screen.getByTestId("icon-dns")).toBeInTheDocument();
  });

  it("renders Resource ghost", () => {
    render(<GhostOverlay {...defaultProps} activeId="res-1" />);
    expect(screen.getByText("Example Resource")).toBeInTheDocument();
    expect(screen.getByText("https://resource.com")).toBeInTheDocument();
    const img = screen.getByRole("img");
    expect(img).toHaveAttribute("src", "https://resource.com/favicon.ico");
  });

  it("renders Tab ghost", () => {
    render(<GhostOverlay {...defaultProps} activeId="tab-1" />);
    expect(screen.getByText("Example Tab")).toBeInTheDocument();
    expect(screen.getByText("https://example.com")).toBeInTheDocument();
    const img = screen.getByRole("img");
    expect(img).toHaveAttribute("src", "https://example.com/favicon.ico");
  });

  it("uses fallback icon for Workspace when icon is undefined", () => {
    const wsNoIcon = { ...mockWorkspace, id: "ws-no-icon", icon: undefined };
    render(
      <GhostOverlay
        {...defaultProps}
        workspaces={[wsNoIcon]}
        activeId="ws-no-icon"
      />,
    );
    expect(screen.getByText("Workspace 1")).toBeInTheDocument();
    // It should render fallback '📁'
    expect(screen.getByText("📁")).toBeInTheDocument();
  });

  it("uses fallback icon for Resource when faviconUrl is missing", () => {
    const resNoIcon = {
      ...mockResource,
      id: "res-no-icon",
      faviconUrl: undefined,
    };
    const ws = {
      ...mockWorkspace,
      sections: [{ ...mockSection, resources: [resNoIcon] }],
    };
    render(
      <GhostOverlay
        {...defaultProps}
        activeWorkspace={ws}
        activeId="res-no-icon"
      />,
    );
    // It should render Icon with name 'link'
    expect(screen.getByTestId("icon-link")).toBeInTheDocument();
  });

  it("uses fallback icon for Tab when favIconUrl is missing", () => {
    const tabNoIcon = { ...mockTab, id: 2, favIconUrl: undefined };
    const ws = {
      ...mockWorkspace,
      tabs: [tabNoIcon],
    };
    render(
      <GhostOverlay {...defaultProps} activeWorkspace={ws} activeId="tab-2" />,
    );
    // It should render Icon with name 'public'
    expect(screen.getByTestId("icon-public")).toBeInTheDocument();
  });
});
