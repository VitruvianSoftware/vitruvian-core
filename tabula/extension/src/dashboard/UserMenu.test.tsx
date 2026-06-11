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
 * Tests for UserMenu component
 *
 * Tests the user avatar and dropdown menu functionality.
 */

import "@testing-library/jest-dom";
import { render, screen, fireEvent } from "@testing-library/react";
import { UserMenu } from "./UserMenu";
import type { User } from "../services/auth";

describe("UserMenu", () => {
  const mockUser: User = {
    id: "user-1",
    email: "test@example.com",
    name: "Test User",
    tier: "free",
    picture: "https://example.com/avatar.jpg",
  };

  const mockUserNoPicture: User = {
    id: "user-2",
    email: "nopic@example.com",
    name: "Jane Doe",
    tier: "free",
  };

  const defaultProps = {
    user: mockUser,
    showUserMenu: false,
    onToggleUserMenu: jest.fn(),
    onCloseUserMenu: jest.fn(),
    onOpenSettings: jest.fn(),
    onLogout: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe("avatar rendering", () => {
    it("should render user avatar image when picture is provided", () => {
      render(<UserMenu {...defaultProps} />);
      const avatar = screen.getByAltText("Test User");
      expect(avatar).toBeInTheDocument();
      expect(avatar).toHaveAttribute("src", "https://example.com/avatar.jpg");
    });

    it("should render initials when no picture is provided", () => {
      render(<UserMenu {...defaultProps} user={mockUserNoPicture} />);
      expect(screen.getByText("JD")).toBeInTheDocument();
    });

    it("should render single initial when user has one name", () => {
      render(
        <UserMenu
          {...defaultProps}
          user={{ ...mockUserNoPicture, name: "Alice" }}
        />,
      );
      expect(screen.getByText("A")).toBeInTheDocument();
    });

    it("should render U when no user", () => {
      render(<UserMenu {...defaultProps} user={null} />);
      expect(screen.getByText("U")).toBeInTheDocument();
    });

    it("should call onToggleUserMenu when avatar clicked", () => {
      render(<UserMenu {...defaultProps} />);
      const avatar = screen.getByAltText("Test User");
      fireEvent.click(avatar.parentElement!);
      expect(defaultProps.onToggleUserMenu).toHaveBeenCalled();
    });
  });

  describe("dropdown menu", () => {
    it("should not show menu when showUserMenu is false", () => {
      render(<UserMenu {...defaultProps} />);
      expect(screen.queryByText("Settings")).not.toBeInTheDocument();
    });

    it("should show menu when showUserMenu is true", () => {
      render(<UserMenu {...defaultProps} showUserMenu={true} />);
      expect(screen.getByText("Settings")).toBeInTheDocument();
      expect(screen.getByText("Log out")).toBeInTheDocument();
    });

    it("should display user name in menu", () => {
      render(<UserMenu {...defaultProps} showUserMenu={true} />);
      expect(screen.getByText("Test User")).toBeInTheDocument();
    });

    it("should display user email in menu", () => {
      render(<UserMenu {...defaultProps} showUserMenu={true} />);
      expect(screen.getByText("test@example.com")).toBeInTheDocument();
    });

    it("should show Account when null user", () => {
      render(<UserMenu {...defaultProps} user={null} showUserMenu={true} />);
      expect(screen.getByText("Account")).toBeInTheDocument();
    });
  });

  describe("menu actions", () => {
    it("should call onOpenSettings when Settings clicked", () => {
      render(<UserMenu {...defaultProps} showUserMenu={true} />);
      fireEvent.click(screen.getByText("Settings"));
      expect(defaultProps.onOpenSettings).toHaveBeenCalled();
    });

    it("should call onLogout when Log out clicked", () => {
      render(<UserMenu {...defaultProps} showUserMenu={true} />);
      fireEvent.click(screen.getByText("Log out"));
      expect(defaultProps.onLogout).toHaveBeenCalled();
    });
  });

  describe("null user", () => {
    it("should handle null user gracefully", () => {
      render(<UserMenu {...defaultProps} user={null} />);
      expect(screen.getByText("U")).toBeInTheDocument();
    });
  });
});
