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
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import "@testing-library/jest-dom";
import { AccountSettings } from "./AccountSettings";
import { ApiService } from "../services/api";
import { StorageService } from "../services/storage";
import { TabService } from "../services/tabs";
import { AuthService } from "../services/auth";
import { UpdateCheckService } from "../services/updateCheck";
import { mockLocationReload } from "../testUtils/jsdomLocation";

jest.mock("../services/updateCheck", () => ({
  UpdateCheckService: {
    getDisplayIdentity: jest.fn().mockResolvedValue(null),
  },
}));

// Mock services
jest.mock("../services/api", () => ({
  ApiService: {
    getUserProfile: jest.fn(),
    updateUserProfile: jest.fn(),
    getPasswordResetUrl: jest.fn(),
    deleteUserAccount: jest.fn(),
    getBackups: jest.fn(),
    createBackup: jest.fn(),
    getBackupStats: jest.fn(),
    restoreBackup: jest.fn(),
    deleteBackup: jest.fn(),
    getWorkspaces: jest.fn(),
  },
}));

jest.mock("../services/auth", () => ({
  AuthService: {
    logout: jest.fn(),
    login: jest.fn(),
    getToken: jest.fn(),
    hasSession: jest.fn(),
  },
}));

jest.mock("../services/storage", () => ({
  StorageService: {
    saveWorkspaces: jest.fn(),
    getActiveWorkspaceId: jest.fn(),
  },
}));

jest.mock("../services/tabs", () => ({
  TabService: {
    getCurrentTabs: jest.fn(),
    openTabs: jest.fn(),
  },
}));

// Mock chrome.storage.local
const mockChromeStorage = {
  set: jest.fn().mockResolvedValue(undefined),
};
(globalThis as any).chrome = {
  storage: {
    local: mockChromeStorage,
  },
};

// Absorb the component's window.location.reload() calls (jsdom 26 makes
// location unforgeable, so the old defineProperty override throws).
mockLocationReload();

// Mock Modal component
jest.mock("./Modal", () => ({
  Modal: ({ children, title, onClose }: any) => (
    <div data-testid="modal">
      <h1>{title}</h1>
      <button onClick={onClose}>Close</button>
      {children}
    </div>
  ),
}));

// Mock Icon component
jest.mock("./icons", () => ({
  Icon: ({ name }: any) => <span>{name}</span>,
}));

describe("AccountSettings", () => {
  const mockOnClose = jest.fn();
  const mockSetTheme = jest.fn();
  const mockUser = {
    id: "user1",
    name: "Test User",
    email: "test@example.com",
    tier: "free",
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (AuthService.getToken as jest.Mock).mockResolvedValue("test-token");
    (AuthService.hasSession as jest.Mock).mockResolvedValue(true);
    (ApiService.getUserProfile as jest.Mock).mockResolvedValue(mockUser);
  });

  describe("signed out", () => {
    beforeEach(() => {
      // No session at all: neither access token nor refresh token.
      (AuthService.getToken as jest.Mock).mockResolvedValue(null);
      (AuthService.hasSession as jest.Mock).mockResolvedValue(false);
    });

    it("should show a sign-in prompt instead of fetching the profile", async () => {
      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      expect(
        await screen.findByText("You're not signed in"),
      ).toBeInTheDocument();
      expect(screen.getByText("Sign in")).toBeInTheDocument();
      expect(ApiService.getUserProfile).not.toHaveBeenCalled();
      expect(
        screen.queryByText("Authentication failed"),
      ).not.toBeInTheDocument();
    });

    it("should call AuthService.login when Sign in clicked", async () => {
      (AuthService.login as jest.Mock).mockImplementation(
        () => new Promise(() => {}),
      );
      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      fireEvent.click(await screen.findByText("Sign in"));
      expect(AuthService.login).toHaveBeenCalled();
    });

    it("should keep Preferences usable without a session", async () => {
      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      fireEvent.click(await screen.findByText("Preferences"));
      expect(screen.getByText("Theme")).toBeInTheDocument();
    });

    it("should prompt for sign-in on the Backups tab without loading", async () => {
      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      fireEvent.click(await screen.findByText("Backups"));
      expect(screen.getByText("You're not signed in")).toBeInTheDocument();
      expect(ApiService.getBackups).not.toHaveBeenCalled();
    });
  });

  it("should render loading state initially", () => {
    (ApiService.getUserProfile as jest.Mock).mockImplementation(
      () => new Promise(() => {}),
    );

    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    expect(screen.getByText("Loading...")).toBeInTheDocument();
  });

  it("should render user profile after loading", async () => {
    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Test User")).toBeInTheDocument();
    });

    expect(screen.getByText("test@example.com")).toBeInTheDocument();
    expect(screen.getByText("free")).toBeInTheDocument();
  });

  it("should show error state on load failure", async () => {
    (ApiService.getUserProfile as jest.Mock).mockRejectedValue(
      new Error("Failed to load"),
    );

    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Failed to load")).toBeInTheDocument();
    });

    expect(screen.getByText("Retry")).toBeInTheDocument();
  });

  it("should allow editing user name", async () => {
    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Test User")).toBeInTheDocument();
    });

    const editButton = screen.getByTitle("Edit name");
    fireEvent.click(editButton);

    const input = screen.getByDisplayValue("Test User");
    fireEvent.change(input, { target: { value: "New Name" } });

    (ApiService.updateUserProfile as jest.Mock).mockResolvedValue({
      ...mockUser,
      name: "New Name",
    });

    const saveButton = screen.getByText("Save");
    fireEvent.click(saveButton);

    await waitFor(() => {
      expect(ApiService.updateUserProfile).toHaveBeenCalledWith({
        name: "New Name",
      });
    });
  });

  it("should switch to preferences tab", async () => {
    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Test User")).toBeInTheDocument();
    });

    const preferencesTab = screen.getByText("Preferences");
    fireEvent.click(preferencesTab);

    expect(screen.getByText("Appearance")).toBeInTheDocument();
  });

  it("should change theme", async () => {
    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Test User")).toBeInTheDocument();
    });

    const preferencesTab = screen.getByText("Preferences");
    fireEvent.click(preferencesTab);

    const darkButton = screen.getByText("dark");
    fireEvent.click(darkButton);

    expect(mockSetTheme).toHaveBeenCalledWith("dark");
  });

  it("should handle password change", async () => {
    const mockOpen = jest.fn();
    window.open = mockOpen;

    (ApiService.getPasswordResetUrl as jest.Mock).mockResolvedValue(
      "https://auth.example.com/reset",
    );

    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Change Password")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText("Change Password"));

    await waitFor(() => {
      expect(mockOpen).toHaveBeenCalledWith(
        "https://auth.example.com/reset",
        "_blank",
        "width=600,height=700",
      );
    });
  });

  it("should show delete confirmation modal", async () => {
    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Delete Account")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText("Delete Account"));

    await waitFor(() => {
      expect(
        screen.getByText(/Are you sure you want to delete/),
      ).toBeInTheDocument();
    });
  });

  it("should cancel edit and restore original name", async () => {
    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Test User")).toBeInTheDocument();
    });

    const editButton = screen.getByTitle("Edit name");
    fireEvent.click(editButton);

    const input = screen.getByDisplayValue("Test User");
    fireEvent.change(input, { target: { value: "Changed Name" } });

    const cancelButton = screen.getByText("Cancel");
    fireEvent.click(cancelButton);

    // Should go back to display mode with original name
    await waitFor(() => {
      expect(
        screen.queryByDisplayValue("Changed Name"),
      ).not.toBeInTheDocument();
      expect(screen.getByText("Test User")).toBeInTheDocument();
    });
  });

  it("should retry loading profile after error", async () => {
    (ApiService.getUserProfile as jest.Mock)
      .mockRejectedValueOnce(new Error("Failed to load"))
      .mockResolvedValueOnce(mockUser);

    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Failed to load")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText("Retry"));

    await waitFor(() => {
      expect(screen.getByText("Test User")).toBeInTheDocument();
    });
  });

  it("should handle password change error", async () => {
    (ApiService.getPasswordResetUrl as jest.Mock).mockRejectedValue(
      new Error("Password reset failed"),
    );

    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Change Password")).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText("Change Password"));

    await waitFor(() => {
      expect(screen.getByText("Password reset failed")).toBeInTheDocument();
    });
  });

  it("should handle name update error", async () => {
    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Test User")).toBeInTheDocument();
    });

    const editButton = screen.getByTitle("Edit name");
    fireEvent.click(editButton);

    (ApiService.updateUserProfile as jest.Mock).mockRejectedValue(
      new Error("Update failed"),
    );

    const saveButton = screen.getByText("Save");
    fireEvent.click(saveButton);

    await waitFor(() => {
      expect(screen.getByText("Update failed")).toBeInTheDocument();
    });
  });

  it("should switch back to account tab from preferences", async () => {
    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Test User")).toBeInTheDocument();
    });

    // Go to preferences
    fireEvent.click(screen.getByText("Preferences"));
    expect(screen.getByText("Appearance")).toBeInTheDocument();

    // Go back to account
    fireEvent.click(screen.getByText("Account"));
    expect(screen.getByText("User Information")).toBeInTheDocument();
  });

  it("should handle non-Error object in profile load failure", async () => {
    (ApiService.getUserProfile as jest.Mock).mockRejectedValue("String error");

    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Failed to load profile")).toBeInTheDocument();
    });
  });
  it("should render popup variant correctly", async () => {
    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
        variant="popup"
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Test User")).toBeInTheDocument();
    });

    // Should have back button in header
    expect(screen.getByTitle("Back")).toBeInTheDocument();
    expect(screen.getByText("Settings")).toBeInTheDocument();

    // Should NOT have Danger Zone in popup
    expect(screen.queryByText("Danger Zone")).not.toBeInTheDocument();
    expect(screen.queryByText("Delete Account")).not.toBeInTheDocument();

    // Should have compact tabs
    expect(screen.getByText("Account")).toBeInTheDocument();
    expect(screen.getByText("Preferences")).toBeInTheDocument();
  });

  it("should render modal variant correctly", async () => {
    // default Is modal
    render(
      <AccountSettings
        onClose={mockOnClose}
        theme="light"
        setTheme={mockSetTheme}
      />,
    );

    await waitFor(() => {
      expect(screen.getByText("Test User")).toBeInTheDocument();
    });

    // Should have "Danger Zone" in modal
    expect(screen.getByText("Danger Zone")).toBeInTheDocument();
    expect(screen.getByText("Delete Account")).toBeInTheDocument();
  });

  describe("Backups Tab", () => {
    beforeEach(() => {
      (ApiService.getBackups as jest.Mock).mockResolvedValue({
        backups: [],
        total: 0,
      });
      (ApiService.getBackupStats as jest.Mock).mockResolvedValue({
        totalBackups: 0,
        totalSizeBytes: 0,
      });
    });

    it("should switch to backups tab and load backups", async () => {
      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      const backupsTab = screen.getByText("Backups");
      fireEvent.click(backupsTab);

      await waitFor(() => {
        expect(ApiService.getBackups).toHaveBeenCalled();
        expect(ApiService.getBackupStats).toHaveBeenCalled();
      });

      expect(screen.getByText("0")).toBeInTheDocument();
      expect(screen.getByText("Total Backups")).toBeInTheDocument();
    });

    it("should show backups list when backups exist", async () => {
      (ApiService.getBackups as jest.Mock).mockResolvedValue({
        backups: [
          {
            id: "backup-1",
            workspaceName: "Work",
            sizeBytes: 1024,
            createdAt: new Date().toISOString(),
          },
        ],
        total: 1,
      });
      (ApiService.getBackupStats as jest.Mock).mockResolvedValue({
        totalBackups: 1,
        totalSizeBytes: 1024,
      });

      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(screen.getByText("Work")).toBeInTheDocument();
      });

      expect(screen.getByText("1.0 KB")).toBeInTheDocument();
    });

    it("should handle create backup click", async () => {
      (ApiService.createBackup as jest.Mock).mockResolvedValue({
        id: "new-backup",
      });

      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(screen.getByText("Create Backup Now")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Create Backup Now"));

      await waitFor(() => {
        expect(ApiService.createBackup).toHaveBeenCalledWith({
          type: "manual",
        });
      });
    });

    it("should show loading state for backups", async () => {
      (ApiService.getBackups as jest.Mock).mockImplementation(
        () => new Promise(() => {}),
      );
      (ApiService.getBackupStats as jest.Mock).mockImplementation(
        () => new Promise(() => {}),
      );

      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(screen.getByText("Loading backups...")).toBeInTheDocument();
      });
    });

    it("should show tier retention info", async () => {
      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(screen.getByText(/Backup Retention/)).toBeInTheDocument();
      });
    });

    it("should handle backup load error", async () => {
      (ApiService.getBackups as jest.Mock).mockRejectedValue(
        new Error("Load failed"),
      );
      (ApiService.getBackupStats as jest.Mock).mockRejectedValue(
        new Error("Load failed"),
      );

      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(screen.getByText("Load failed")).toBeInTheDocument();
      });
    });

    it("should show empty state when no backups exist", async () => {
      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(
          screen.getByText(
            "No backups yet. Create your first backup to protect your workspaces.",
          ),
        ).toBeInTheDocument();
      });
    });

    it("should work in popup variant", async () => {
      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
          variant="popup"
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      // Popup should have Backups tab
      expect(screen.getByText("Backups")).toBeInTheDocument();
      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(screen.getByText("Total Backups")).toBeInTheDocument();
      });
    });

    it("should handle create backup error", async () => {
      (ApiService.createBackup as jest.Mock).mockRejectedValue(
        new Error("Create failed"),
      );

      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(screen.getByText("Create Backup Now")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Create Backup Now"));

      await waitFor(() => {
        expect(screen.getByText("Create failed")).toBeInTheDocument();
      });
    });

    it("should display pro tier retention info", async () => {
      (ApiService.getUserProfile as jest.Mock).mockResolvedValue({
        ...mockUser,
        tier: "pro",
      });

      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(screen.getByText(/90 days/)).toBeInTheDocument();
      });
    });

    it("should handle restore backup click", async () => {
      const mockWorkspaces = [
        {
          id: "ws-1",
          name: "Test Workspace",
          tabs: [{ url: "https://restored-tab.com", title: "Restored" }],
        },
      ];
      (ApiService.getBackups as jest.Mock).mockResolvedValue({
        backups: [
          {
            id: "backup-1",
            workspaceName: "Work",
            sizeBytes: 1024,
            createdAt: new Date().toISOString(),
          },
        ],
        total: 1,
      });
      (ApiService.getBackupStats as jest.Mock).mockResolvedValue({
        totalBackups: 1,
        totalSizeBytes: 1024,
      });
      (ApiService.restoreBackup as jest.Mock).mockResolvedValue(undefined);
      (ApiService.getWorkspaces as jest.Mock).mockResolvedValue(mockWorkspaces);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
      (StorageService.getActiveWorkspaceId as jest.Mock).mockResolvedValue(
        "ws-1",
      );
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([]);
      (TabService.openTabs as jest.Mock).mockResolvedValue(undefined);

      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(screen.getByText("Work")).toBeInTheDocument();
      });

      // Click restore button
      const restoreButton = screen.getByTitle("Restore this backup");
      fireEvent.click(restoreButton);

      await waitFor(() => {
        expect(ApiService.restoreBackup).toHaveBeenCalledWith("backup-1");
      });

      await waitFor(() => {
        expect(ApiService.getWorkspaces).toHaveBeenCalled();
        expect(StorageService.saveWorkspaces).toHaveBeenCalledWith(
          mockWorkspaces,
        );
        expect(TabService.openTabs).toHaveBeenCalled();
      });
    });

    it("should handle restore backup error", async () => {
      (ApiService.getBackups as jest.Mock).mockResolvedValue({
        backups: [
          {
            id: "backup-1",
            workspaceName: "Work",
            sizeBytes: 1024,
            createdAt: new Date().toISOString(),
          },
        ],
        total: 1,
      });
      (ApiService.getBackupStats as jest.Mock).mockResolvedValue({
        totalBackups: 1,
        totalSizeBytes: 1024,
      });
      (ApiService.restoreBackup as jest.Mock).mockRejectedValue(
        new Error("Restore failed"),
      );

      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(screen.getByText("Work")).toBeInTheDocument();
      });

      // Click restore button
      const restoreButton = screen.getByTitle("Restore this backup");
      fireEvent.click(restoreButton);

      await waitFor(() => {
        expect(screen.getByText("Restore failed")).toBeInTheDocument();
      });
    });

    it("should handle delete backup click", async () => {
      (ApiService.getBackups as jest.Mock).mockResolvedValue({
        backups: [
          {
            id: "backup-1",
            workspaceName: "Work",
            sizeBytes: 1024,
            createdAt: new Date().toISOString(),
          },
        ],
        total: 1,
      });
      (ApiService.getBackupStats as jest.Mock).mockResolvedValue({
        totalBackups: 1,
        totalSizeBytes: 1024,
      });
      (ApiService.deleteBackup as jest.Mock).mockResolvedValue(undefined);

      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(screen.getByText("Work")).toBeInTheDocument();
      });

      // Click delete button
      const deleteButton = screen.getByTitle("Delete this backup");
      fireEvent.click(deleteButton);

      await waitFor(() => {
        expect(ApiService.deleteBackup).toHaveBeenCalledWith("backup-1");
      });
    });

    it("should handle delete backup error", async () => {
      (ApiService.getBackups as jest.Mock).mockResolvedValue({
        backups: [
          {
            id: "backup-1",
            workspaceName: "Work",
            sizeBytes: 1024,
            createdAt: new Date().toISOString(),
          },
        ],
        total: 1,
      });
      (ApiService.getBackupStats as jest.Mock).mockResolvedValue({
        totalBackups: 1,
        totalSizeBytes: 1024,
      });
      (ApiService.deleteBackup as jest.Mock).mockRejectedValue(
        new Error("Delete failed"),
      );

      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(screen.getByText("Work")).toBeInTheDocument();
      });

      // Click delete button
      const deleteButton = screen.getByTitle("Delete this backup");
      fireEvent.click(deleteButton);

      await waitFor(() => {
        expect(screen.getByText("Delete failed")).toBeInTheDocument();
      });
    });

    it("should not open tabs if workspace has no tabs", async () => {
      const mockWorkspaces = [
        { id: "ws-1", name: "Empty Workspace", tabs: [] },
      ];
      (ApiService.getBackups as jest.Mock).mockResolvedValue({
        backups: [
          {
            id: "backup-1",
            workspaceName: "Work",
            sizeBytes: 1024,
            createdAt: new Date().toISOString(),
          },
        ],
        total: 1,
      });
      (ApiService.getBackupStats as jest.Mock).mockResolvedValue({
        totalBackups: 1,
        totalSizeBytes: 1024,
      });
      (ApiService.restoreBackup as jest.Mock).mockResolvedValue(undefined);
      (ApiService.getWorkspaces as jest.Mock).mockResolvedValue(mockWorkspaces);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
      (StorageService.getActiveWorkspaceId as jest.Mock).mockResolvedValue(
        "ws-1",
      );
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([]);
      (TabService.openTabs as jest.Mock).mockResolvedValue(undefined);

      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(screen.getByText("Work")).toBeInTheDocument();
      });

      const restoreButton = screen.getByTitle("Restore this backup");
      fireEvent.click(restoreButton);

      await waitFor(() => {
        expect(ApiService.restoreBackup).toHaveBeenCalledWith("backup-1");
      });

      // Should NOT call openTabs since workspace has no tabs
      expect(TabService.openTabs).not.toHaveBeenCalled();
    });

    it("should use fallback workspace if active workspace has no tabs", async () => {
      const mockWorkspaces = [
        { id: "ws-1", name: "Empty Workspace", tabs: [] },
        {
          id: "ws-2",
          name: "Full Workspace",
          tabs: [{ url: "https://test.com", title: "Test" }],
        },
      ];
      (ApiService.getBackups as jest.Mock).mockResolvedValue({
        backups: [
          {
            id: "backup-1",
            workspaceName: "Work",
            sizeBytes: 1024,
            createdAt: new Date().toISOString(),
          },
        ],
        total: 1,
      });
      (ApiService.getBackupStats as jest.Mock).mockResolvedValue({
        totalBackups: 1,
        totalSizeBytes: 1024,
      });
      (ApiService.restoreBackup as jest.Mock).mockResolvedValue(undefined);
      (ApiService.getWorkspaces as jest.Mock).mockResolvedValue(mockWorkspaces);
      (StorageService.saveWorkspaces as jest.Mock).mockResolvedValue(undefined);
      (StorageService.getActiveWorkspaceId as jest.Mock).mockResolvedValue(
        "ws-1",
      ); // Empty one
      (TabService.getCurrentTabs as jest.Mock).mockResolvedValue([]);
      (TabService.openTabs as jest.Mock).mockResolvedValue(undefined);

      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );

      await waitFor(() => {
        expect(screen.getByText("Test User")).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText("Backups"));

      await waitFor(() => {
        expect(screen.getByText("Work")).toBeInTheDocument();
      });

      const restoreButton = screen.getByTitle("Restore this backup");
      fireEvent.click(restoreButton);

      await waitFor(() => {
        expect(ApiService.restoreBackup).toHaveBeenCalledWith("backup-1");
      });

      // Should call openTabs with fallback workspace tabs
      await waitFor(() => {
        expect(TabService.openTabs).toHaveBeenCalled();
      });
    });
  });

  describe("Developer section", () => {
    const renderAndGoToPreferences = async () => {
      render(
        <AccountSettings
          onClose={mockOnClose}
          theme="light"
          setTheme={mockSetTheme}
        />,
      );
      // Wait for the profile load to settle, then navigate to Preferences
      await waitFor(() =>
        expect(screen.getByText("Test User")).toBeInTheDocument(),
      );
      fireEvent.click(screen.getByText("Preferences"));
    };

    beforeEach(() => {
      (UpdateCheckService.getDisplayIdentity as jest.Mock).mockResolvedValue(
        null,
      );
    });

    afterEach(() => {
      // Remove any clipboard stub set by individual tests
      Object.defineProperty(navigator, "clipboard", {
        value: undefined,
        configurable: true,
        writable: true,
      });
    });

    it("hidden when getDisplayIdentity resolves null", async () => {
      await renderAndGoToPreferences();
      await waitFor(() =>
        expect(screen.getByText("Appearance")).toBeInTheDocument(),
      );
      expect(screen.queryByText("Developer")).not.toBeInTheDocument();
    });

    it("shows channel/version/sha line for an eligible install", async () => {
      (UpdateCheckService.getDisplayIdentity as jest.Mock).mockResolvedValue({
        channel: "alpha",
        commit: "abc1234def",
        version: "0.1.9",
      });
      await renderAndGoToPreferences();
      await waitFor(() =>
        expect(screen.getByText("Developer")).toBeInTheDocument(),
      );
      expect(
        screen.getByText(/alpha · v0\.1\.9 · abc1234/),
      ).toBeInTheDocument();
    });

    it("clicking beta picker reveals tabcli command and Copy button", async () => {
      Object.defineProperty(navigator, "clipboard", {
        value: { writeText: jest.fn().mockResolvedValue(undefined) },
        configurable: true,
        writable: true,
      });
      (UpdateCheckService.getDisplayIdentity as jest.Mock).mockResolvedValue({
        channel: "alpha",
        commit: "abc1234def",
        version: "0.1.9",
      });
      await renderAndGoToPreferences();
      await waitFor(() =>
        expect(screen.getByText("Developer")).toBeInTheDocument(),
      );

      // Click the beta channel button
      fireEvent.click(screen.getByRole("button", { name: "beta" }));

      await waitFor(() =>
        expect(
          screen.getByText(/tabcli ext update --channel beta/),
        ).toBeInTheDocument(),
      );

      const copyBtn = screen.getByRole("button", { name: "Copy" });
      fireEvent.click(copyBtn);

      await waitFor(() =>
        expect(navigator.clipboard.writeText).toHaveBeenCalledWith(
          "tabcli ext update --channel beta",
        ),
      );
    });

    it("clicking stable shows Web Store listing (M3) text and no --channel flag", async () => {
      (UpdateCheckService.getDisplayIdentity as jest.Mock).mockResolvedValue({
        channel: "alpha",
        commit: "abc1234def",
        version: "0.1.9",
      });
      await renderAndGoToPreferences();
      await waitFor(() =>
        expect(screen.getByText("Developer")).toBeInTheDocument(),
      );

      fireEvent.click(screen.getByRole("button", { name: "stable" }));

      await waitFor(() =>
        expect(
          screen.getByText(/Web Store listing \(M3\)/),
        ).toBeInTheDocument(),
      );
      expect(screen.queryByText(/--channel stable/)).not.toBeInTheDocument();
    });
  });
});
