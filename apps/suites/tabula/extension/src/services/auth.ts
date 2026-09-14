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

// Configurable via environment variables injected by Webpack
const { API_URL } = process.env;

export interface User {
  id: string;
  email: string;
  name: string;
  tier: string;
  picture?: string;
}

export interface AuthResponse {
  token: string;
  user: User;
  /** Long-lived, server-revocable refresh token (rotated on each use) */
  refreshToken?: string;
}

const REFRESH_TOKEN_KEY = "tabula_refresh_token";

/**
 * Per-user local storage keys that MUST be purged on logout / account switch.
 * Device-level settings (tabula_settings) are intentionally excluded so they
 * survive across users on a shared profile.
 */
const PER_USER_LOCAL_KEYS = [
  "tabula_user",
  "tabula_workspaces",
  "tabula_space_groups",
  "tabula_active_workspace",
  "tabula_sync_queue",
  "tabula_window_ownership",
  "tabula_data_owner",
  REFRESH_TOKEN_KEY,
];

/** Derive the API origin for validating auth postMessage events. */
function getApiOrigin(): string | null {
  try {
    return API_URL ? new URL(API_URL).origin : null;
  } catch {
    return null;
  }
}

/** Best-effort access to chrome.storage.session (in-memory; not on disk). */
function sessionStorage(): chrome.storage.StorageArea | null {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const session = (chrome.storage as any)?.session;
  return session || null;
}

function randomState(): string {
  if (
    typeof crypto !== "undefined" &&
    typeof crypto.randomUUID === "function"
  ) {
    return crypto.randomUUID();
  }
  return `${Date.now()}_${Math.random().toString(36).slice(2)}`;
}

export class AuthService {
  private static tokenKey = "tabula_access_token";

  private static userKey = "tabula_user";

  private static ownerKey = "tabula_data_owner";

  private static readonly LOGIN_TIMEOUT_MS = 5 * 60 * 1000;

  static async login(): Promise<User> {
    return new Promise((resolve, reject) => {
      // Calculate center position for the popup
      const width = 600;
      const height = 700;
      const left = window.screen.width / 2 - width / 2;
      const top = window.screen.height / 2 - height / 2;

      // CSRF/replay guard: a fresh nonce tied to this login attempt
      const state = randomState();
      const apiOrigin = getApiOrigin();

      const authWindow = window.open(
        `${API_URL}/auth/login?state=${encodeURIComponent(state)}`,
        "tabula_auth",
        `width=${width},height=${height},left=${left},top=${top}`,
      );

      if (!authWindow) {
        reject(new Error("Failed to open authentication window"));
        return;
      }

      let checkClosed: ReturnType<typeof setInterval> | null = null;
      let timeoutId: ReturnType<typeof setTimeout> | null = null;

      // handleMessage and cleanup reference each other; one must forward-ref
      /* eslint-disable no-use-before-define, @typescript-eslint/no-use-before-define */
      // Handler for auth message
      const handleMessage = async (event: MessageEvent) => {
        // Only trust messages from the auth popup we opened...
        if (event.source && event.source !== authWindow) return;
        // ...originating from the API origin (the callback HTML is served by it)
        if (apiOrigin && event.origin && event.origin !== apiOrigin) return;

        if (event.data?.type === "TABULA_AUTH_SUCCESS") {
          // If the callback echoes a state, it MUST match ours (forged
          // messages from other contexts cannot know it)
          const echoedState = event.data?.state;
          if (echoedState !== undefined && echoedState !== state) return;

          const { token, user, refreshToken } = event.data
            .payload as AuthResponse;

          try {
            await AuthService.setSession(token, user, refreshToken);
            cleanup();
            resolve(user);
          } catch (error) {
            cleanup();
            reject(error);
          }
        }
      };

      const cleanup = () => {
        window.removeEventListener("message", handleMessage);
        if (checkClosed) clearInterval(checkClosed);
        if (timeoutId) clearTimeout(timeoutId);
      };
      /* eslint-enable no-use-before-define, @typescript-eslint/no-use-before-define */

      window.addEventListener("message", handleMessage);

      // Reject (rather than hang forever) if the user closes the popup
      checkClosed = setInterval(() => {
        if (authWindow.closed) {
          cleanup();
          reject(new Error("Authentication window was closed"));
        }
      }, 1000);

      // Absolute timeout so a stuck/erroring auth page cannot pin the UI
      timeoutId = setTimeout(() => {
        cleanup();
        reject(new Error("Authentication timed out"));
      }, AuthService.LOGIN_TIMEOUT_MS);
    });
  }

  static async logout(): Promise<void> {
    // Best-effort server-side session revocation before clearing local state
    const refreshToken = await this.getRefreshToken();
    if (refreshToken) {
      try {
        await fetch(`${API_URL}/auth/logout`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ refreshToken }),
        });
      } catch {
        // Network failure must not block local logout
      }
    }

    // Clear ALL per-user local state so a different account on the same
    // profile can never inherit (or sync) the previous user's data.
    await chrome.storage.local.remove([this.tokenKey, ...PER_USER_LOCAL_KEYS]);
    const session = sessionStorage();
    if (session) {
      await session.remove(this.tokenKey);
    }
  }

  static async getRefreshToken(): Promise<string | null> {
    const result = await chrome.storage.local.get(REFRESH_TOKEN_KEY);
    return (result[REFRESH_TOKEN_KEY] as string | undefined) || null;
  }

  /**
   * Exchange the refresh token for a fresh access token (rotation). Returns
   * the new access token, or null if refresh failed (caller should re-login).
   * Single-flighted so concurrent 401s don't race the rotating refresh token.
   */
  static async refreshAccessToken(): Promise<string | null> {
    if (!this.refreshInFlight) {
      this.refreshInFlight = this.doRefresh().finally(() => {
        this.refreshInFlight = null;
      });
    }
    return this.refreshInFlight;
  }

  private static refreshInFlight: Promise<string | null> | null = null;

  private static async doRefresh(): Promise<string | null> {
    const refreshToken = await this.getRefreshToken();
    if (!refreshToken) return null;
    try {
      const response = await fetch(`${API_URL}/auth/refresh`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ refreshToken }),
      });
      if (!response.ok) {
        // Refresh token invalid/expired/revoked — session is dead
        if (response.status === 401) {
          await this.clearTokens();
        }
        return null;
      }
      const json = await response.json();
      const data = (json.data || json) as {
        token: string;
        refreshToken?: string;
      };
      await this.storeTokens(data.token, data.refreshToken);
      return data.token;
    } catch {
      return null;
    }
  }

  private static async storeTokens(
    token: string,
    refreshToken?: string,
  ): Promise<void> {
    const session = sessionStorage();
    if (session) {
      await session.set({ [this.tokenKey]: token });
      await chrome.storage.local.remove(this.tokenKey);
    } else {
      await chrome.storage.local.set({ [this.tokenKey]: token });
    }
    if (refreshToken) {
      await chrome.storage.local.set({ [REFRESH_TOKEN_KEY]: refreshToken });
    }
  }

  private static async clearTokens(): Promise<void> {
    await chrome.storage.local.remove([this.tokenKey, REFRESH_TOKEN_KEY]);
    const session = sessionStorage();
    if (session) await session.remove(this.tokenKey);
  }

  static async getUser(): Promise<User | null> {
    const result = await chrome.storage.local.get(this.userKey);
    return (result[this.userKey] as User | undefined) || null;
  }

  /**
   * Overwrite the cached user record (tabula_user) in place.
   *
   * The cache is otherwise only written at login. That made it a sticky home
   * for stale or mis-encoded fields: a name that an older login flow stored as
   * mojibake (UTF-8 decoded as windows-1252, e.g. "Nguyá»…n") stays wrong on
   * every cache-backed surface until the user logs out and back in. This lets
   * callers re-project the authoritative profile over the cache without a full
   * re-login. Writing it fires chrome.storage.onChanged, so open dashboards
   * pick the corrected value up automatically.
   */
  static async setCachedUser(user: User): Promise<void> {
    await chrome.storage.local.set({ [this.userKey]: user });
  }

  static async getToken(): Promise<string | null> {
    // Token lives in session storage (in-memory) when available, falling back
    // to local for environments without storage.session.
    const session = sessionStorage();
    if (session) {
      const result = await session.get(this.tokenKey);
      const sessionToken = result[this.tokenKey] as string | undefined;
      if (sessionToken) return sessionToken;
    }
    const local = await chrome.storage.local.get(this.tokenKey);
    return (local[this.tokenKey] as string | undefined) || null;
  }

  /**
   * Whether a session exists locally — an in-memory access token OR a persisted
   * refresh token.
   *
   * "Signed in" must NOT be judged by the access token alone: it lives in
   * session storage (in-memory) and is wiped on browser restart, whereas the
   * server-revocable refresh token persists on disk and is what actually keeps
   * the user logged in (the API layer trades it for a fresh access token on
   * demand). Gating UI on getToken() made Settings show "not signed in" after a
   * restart while the rest of the app — backed by the persisted user cache —
   * still showed the user logged in.
   */
  static async hasSession(): Promise<boolean> {
    if (await this.getToken()) return true;
    return Boolean(await this.getRefreshToken());
  }

  private static async setSession(
    token: string,
    user: User,
    refreshToken?: string,
  ): Promise<void> {
    // Account-switch guard: if cached data belongs to a different user, purge
    // it before this session takes over (covers logout paths that were
    // bypassed by a crash or token expiry).
    const ownerResult = await chrome.storage.local.get(this.ownerKey);
    const previousOwner = ownerResult[this.ownerKey] as string | undefined;
    if (previousOwner && previousOwner !== user.id) {
      await chrome.storage.local.remove(PER_USER_LOCAL_KEYS);
    }

    // Access token lives in memory (session); refresh token persists on disk
    // (it is server-revocable, unlike the old forever-JWT) so the user stays
    // logged in across browser restarts despite the 1h access-token expiry.
    await this.storeTokens(token, refreshToken);

    await chrome.storage.local.set({
      [this.userKey]: user,
      [this.ownerKey]: user.id,
    });
  }
}
