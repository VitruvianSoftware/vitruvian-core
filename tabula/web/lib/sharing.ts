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
 * SharingService — the web companion's API client for the #139 sharing layer.
 *
 * API-authoritative by design: unlike lib/data.ts (which falls back to
 * chrome.storage / localStorage), a SHARED space is never in the visitor's
 * local storage, so every call here goes straight to the REST API with the
 * logged-in user's Bearer token. Read-only vs editable is enforced SERVER-SIDE
 * by #139 (GET needs view, PUT needs edit); this client never decides access.
 */
import type { Workspace } from "@tabula/shared";
import { AuthService } from "./auth";
import { getApiUrl } from "./runtime-config";

/** Role a logged-in user holds on a space (mirrors #139's lowercase GrantRole + owner). */
export type SpaceRole = "owner" | "edit" | "view";

export interface SharedSpace {
  workspaceId: string;
  role: "view" | "edit";
  name: string;
}

export interface AcceptResult {
  workspaceId: string;
  workspaceName: string;
  role: SpaceRole;
}

/** Public preview of a relay link (no token material). */
export interface RelayInfo {
  workspaceId: string;
  workspaceName: string;
  ownerName: string;
  role: "view" | "edit";
}

/**
 * A failed API call, carrying the HTTP status so callers branch on it (401 →
 * login, 403 → view-only, 404 → existence-masked, 409 → conflict). For a 409 the
 * server's current copy of the workspace is attached as `data`.
 */
export class ApiError extends Error {
  readonly status: number;
  readonly data?: unknown;

  constructor(status: number, message: string, data?: unknown) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.data = data;
  }
}

function authHeaders(): Record<string, string> {
  const token = AuthService.getToken();
  if (!token) {
    throw new ApiError(401, "Not authenticated");
  }
  return {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  };
}

async function unwrap<T>(res: Response): Promise<T> {
  if (!res.ok) {
    throw new ApiError(res.status, `Request failed (${res.status})`);
  }
  const json = (await res.json()) as { data: T };
  return json.data;
}

export const SharingService = {
  /** GET a full space the user has at least VIEW access to. 404 = no access / not found. */
  async getSpace(id: string): Promise<Workspace> {
    const res = await fetch(`${getApiUrl()}/workspaces/${encodeURIComponent(id)}`, {
      headers: authHeaders(),
    });
    return unwrap<Workspace>(res);
  },

  /**
   * PUT an edited space (requires EDIT). On 409 the server returns its current
   * copy; this throws ApiError(409, …, currentWorkspace) so the editor can offer
   * a reload instead of silently clobbering.
   */
  async saveSpace(
    id: string,
    workspace: Partial<Workspace>,
    baseVersion?: number,
  ): Promise<Workspace> {
    const res = await fetch(`${getApiUrl()}/workspaces/${encodeURIComponent(id)}`, {
      method: "PUT",
      headers: authHeaders(),
      body: JSON.stringify({ ...workspace, baseVersion }),
    });
    if (res.status === 409) {
      const json = (await res.json()) as { data: Workspace };
      throw new ApiError(409, "Space changed elsewhere", json.data);
    }
    return unwrap<Workspace>(res);
  },

  /** Spaces shared WITH the current user (not owned), with their effective role. */
  async getSharedWithMe(): Promise<SharedSpace[]> {
    const res = await fetch(`${getApiUrl()}/workspaces/shared-with-me`, {
      headers: authHeaders(),
    });
    return unwrap<SharedSpace[]>(res);
  },

  /**
   * Redeem a share-link token (carried in the BODY, never the URL) to materialize
   * a grant for the current user. Idempotent server-side; never downgrades.
   */
  async acceptShareLink(token: string): Promise<AcceptResult> {
    const res = await fetch(`${getApiUrl()}/share-links/accept`, {
      method: "POST",
      headers: authHeaders(),
      body: JSON.stringify({ token }),
    });
    return unwrap<AcceptResult>(res);
  },

  /**
   * PUBLIC preview of a relay link (tabula.com/s/<relayId>) — no auth, so a
   * logged-out stranger sees what they were invited to. The relayId is the URL
   * handle (not the bearer token). 404 = unknown / revoked / expired.
   */
  async getRelayInfo(relayId: string): Promise<RelayInfo> {
    const res = await fetch(
      `${getApiUrl()}/share-links/relay/${encodeURIComponent(relayId)}/info`,
    );
    return unwrap<RelayInfo>(res);
  },

  /** Redeem a relay link (requires login) → materializes the caller's grant. */
  async acceptRelay(relayId: string): Promise<AcceptResult> {
    const res = await fetch(
      `${getApiUrl()}/share-links/relay/${encodeURIComponent(relayId)}/accept`,
      { method: "POST", headers: authHeaders() },
    );
    return unwrap<AcceptResult>(res);
  },
};
