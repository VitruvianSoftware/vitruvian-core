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

import { AuthService, User } from "./auth";
import { getDeviceId } from "./deviceId";
import { ApiError } from "./errors";
import type {
  Workspace,
  SpaceGroup,
  UserProfile,
  UserUpdateInput,
} from "../types";

// Re-export so callers can keep importing from the API module
export { ApiError } from "./errors";

// Configurable via environment variables injected by Webpack
const { API_URL } = process.env;

const REQUEST_TIMEOUT_MS = 30000;

/** Options for save operations participating in the sync protocol */
export interface SaveOptions {
  /** Last server version this client saw; server returns 409 if stale */
  baseVersion?: number;
  /** This save came from automatic tab sync (renews the active-device lease) */
  tabSync?: boolean;
  /** Explicitly claim the active-device lease (user switched to this workspace) */
  claimActiveDevice?: boolean;
}

export class ApiService {
  /**
   * Helper to perform authenticated requests
   */
  private static async request<T>(
    endpoint: string,
    options: RequestInit = {},
    allowRefresh = true,
  ): Promise<T> {
    const token = await AuthService.getToken();

    const headers = new Headers(options.headers);
    headers.set("Content-Type", "application/json");
    if (token) {
      headers.set("Authorization", `Bearer ${token}`);
    }
    try {
      headers.set("X-Device-Id", await getDeviceId());
    } catch {
      // Device ID is best-effort; requests must not fail because of it
    }

    const supportsTimeout =
      typeof AbortSignal !== "undefined" &&
      typeof AbortSignal.timeout === "function";

    const response = await fetch(`${API_URL}${endpoint}`, {
      ...options,
      headers,
      // A hung request must not stall the sync queue indefinitely
      ...(supportsTimeout
        ? { signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) }
        : {}),
    });

    if (!response.ok) {
      // Access tokens expire (~1h); on 401, transparently refresh once and
      // retry so the user isn't logged out mid-session.
      if (response.status === 401 && allowRefresh && token) {
        const refreshed = await AuthService.refreshAccessToken();
        if (refreshed) {
          return this.request<T>(endpoint, options, false);
        }
      }
      const error = await response
        .json()
        .catch(() => ({ message: "Unknown error" }));
      throw new ApiError(
        error.message || `API Error: ${response.statusText}`,
        response.status,
        error.data,
      );
    }

    // Some endpoints might return empty body (e.g. DELETE)
    if (response.status === 204) {
      return {} as T;
    }

    const json = await response.json();
    return json.data as T;
  }

  // ============================================
  // WORKSPACES
  // ============================================

  static async getWorkspaces(): Promise<Workspace[]> {
    return this.request<Workspace[]>("/workspaces");
  }

  static async getWorkspace(id: string): Promise<Workspace> {
    return this.request<Workspace>(`/workspaces/${id}`);
  }

  static async saveWorkspace(
    workspace: Workspace,
    options: SaveOptions = {},
  ): Promise<Workspace> {
    // We use PUT for idempotency if we're sending the whole object
    // Or we could differentiate create vs update.
    // For this implementation, let's assume the backend handles upsert or we check
    // existence. To match typical REST, we generally separate create (POST) and update (PUT/PATCH).
    // However, the `WorkspaceService` often just "saves" the state.
    // Let's assume we can PUT to /workspaces/:id to update/create with a known ID.
    return this.request<Workspace>(`/workspaces/${workspace.id}`, {
      method: "PUT",
      body: JSON.stringify({
        ...workspace,
        baseVersion: options.baseVersion ?? workspace.version,
        ...(options.tabSync ? { tabSync: true } : {}),
        ...(options.claimActiveDevice ? { claimActiveDevice: true } : {}),
      }),
    });
  }

  static async deleteWorkspace(id: string): Promise<void> {
    return this.request<void>(`/workspaces/${id}`, {
      method: "DELETE",
    });
  }

  // ============================================
  // SPACE GROUPS
  // ============================================

  static async getSpaceGroups(): Promise<SpaceGroup[]> {
    return this.request<SpaceGroup[]>("/space-groups");
  }

  static async saveSpaceGroup(
    group: SpaceGroup,
    options: SaveOptions = {},
  ): Promise<SpaceGroup> {
    return this.request<SpaceGroup>(`/space-groups/${group.id}`, {
      method: "PUT",
      body: JSON.stringify({
        ...group,
        baseVersion: options.baseVersion ?? group.version,
      }),
    });
  }

  static async deleteSpaceGroup(id: string): Promise<void> {
    return this.request<void>(`/space-groups/${id}`, {
      method: "DELETE",
    });
  }

  // ============================================
  // USER PROFILE
  // ============================================

  static async getUserProfile(): Promise<UserProfile> {
    return this.request<UserProfile>("/users/me");
  }

  /**
   * Re-project the authoritative /users/me profile onto the locally cached user
   * (tabula_user). The dashboard header and popup render the cache, which is
   * only populated at login; a name corrupted by an older mis-encoded login
   * (mojibake like "Nguyá»…n") therefore persists across the rotating 30-day
   * refresh window — the refresh flow never rewrites the cached user. Calling
   * this on app load lets those surfaces self-heal (and pick up tier changes)
   * without forcing a re-login.
   *
   * The avatar (picture) is preserved from the cache: it comes from the identity
   * provider at login and is not persisted server-side, so /users/me omits it.
   *
   * Best-effort: returns the existing cache when signed out or on any failure,
   * and never throws, so it is safe to fire-and-forget from a mount effect.
   */
  static async refreshCachedUser(): Promise<User | null> {
    let cached: User | null = null;
    try {
      cached = await AuthService.getUser();
      // No session -> nothing authoritative to fetch; keep whatever is cached.
      if (!(await AuthService.getToken())) return cached;

      const profile = await this.getUserProfile();
      const merged: User = {
        ...(cached ?? {}),
        id: profile.id,
        email: profile.email,
        name: profile.name,
        tier: profile.tier,
      };

      // Avoid a redundant write (and the storage event it triggers) when the
      // cache already matches the server.
      if (
        cached &&
        cached.id === merged.id &&
        cached.email === merged.email &&
        cached.name === merged.name &&
        cached.tier === merged.tier
      ) {
        return cached;
      }

      await AuthService.setCachedUser(merged);
      return merged;
    } catch {
      return cached;
    }
  }

  static async updateUserProfile(
    updates: UserUpdateInput,
  ): Promise<UserProfile> {
    return this.request<UserProfile>("/users/me", {
      method: "PATCH",
      body: JSON.stringify(updates),
    });
  }

  static async deleteUserAccount(): Promise<void> {
    return this.request<void>("/users/me", {
      method: "DELETE",
    });
  }

  static async getPasswordResetUrl(email: string): Promise<string> {
    const response = await this.request<{ resetUrl: string }>(
      "/users/password-reset",
      {
        method: "POST",
        body: JSON.stringify({ email }),
      },
    );
    return response.resetUrl;
  }

  // ============================================
  // BACKUPS
  // ============================================

  static async getBackups(
    query: {
      limit?: number;
      offset?: number;
      workspaceId?: string;
    } = {},
  ): Promise<{
    backups: Array<{
      id: string;
      workspaceId: string | null;
      sizeBytes: number | null;
      createdAt: string;
      workspaceName?: string;
    }>;
    total: number;
  }> {
    const params = new URLSearchParams();
    if (query.limit) params.set("limit", query.limit.toString());
    if (query.offset) params.set("offset", query.offset.toString());
    if (query.workspaceId) params.set("workspaceId", query.workspaceId);
    const queryStr = params.toString();
    return this.request(`/backups${queryStr ? `?${queryStr}` : ""}`);
  }

  static async createBackup(
    input: {
      workspaceId?: string;
      name?: string;
      type?: "manual" | "auto" | "scheduled";
    } = {},
  ): Promise<{
    id: string;
    workspaceId: string | null;
    sizeBytes: number;
    createdAt: string;
  }> {
    return this.request("/backups", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  static async getBackupStats(): Promise<{
    totalBackups: number;
    totalSizeBytes: number;
    autoBackups: number;
    manualBackups: number;
    oldestBackup: string | null;
    newestBackup: string | null;
    backupsByWorkspace: Record<string, number>;
  }> {
    return this.request("/backups/stats");
  }

  static async restoreBackup(
    backupId: string,
    options: { targetWorkspaceId?: string; createNew?: boolean } = {},
  ): Promise<{ restoredWorkspaceIds: string[] }> {
    return this.request(`/backups/${backupId}/restore`, {
      method: "POST",
      body: JSON.stringify(options),
    });
  }

  static async deleteBackup(backupId: string): Promise<void> {
    return this.request(`/backups/${backupId}`, {
      method: "DELETE",
    });
  }
}
