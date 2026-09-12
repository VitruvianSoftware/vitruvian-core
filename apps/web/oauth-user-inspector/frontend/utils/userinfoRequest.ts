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
 * Decide HOW the browser fetches a provider's OIDC/userinfo profile after login.
 *
 * Most providers' userinfo endpoints are CORS-enabled, so the SPA fetches them
 * directly. **LinkedIn is the exception**: `api.linkedin.com` sends NO
 * `Access-Control-Allow-Origin` header, so a direct cross-origin browser fetch
 * is rejected by the browser and surfaces in JS as the opaque TypeError
 * "Failed to fetch". So LinkedIn's userinfo MUST be routed through our
 * same-origin server proxy (`POST /api/explore` → server-side `safeFetch`),
 * which calls LinkedIn from the backend (no CORS) and returns the upstream body
 * wrapped as `{ success, status, data }`.
 *
 * This module is intentionally PURE (no `fetch`, no DOM, no `localStorage`) so
 * it is unit-testable in the node jest env and so the routing decision — the
 * thing that actually regressed — is guarded by a test.
 */

export type UserinfoProvider =
  "github" | "google" | "gitlab" | "auth0" | "zitadel" | "linkedin";

export interface UserinfoRequestOptions {
  /** Auth0 tenant domain (issuer host) — required for provider "auth0". */
  auth0Domain?: string;
  /** Zitadel issuer domain — required for provider "zitadel". */
  zitadelDomain?: string;
}

/**
 * - `direct`: the provider's userinfo API is CORS-enabled; the fetch body IS
 *   the raw userinfo JSON.
 * - `proxy`: routed through `/api/explore`; the body is the envelope
 *   `{ success, status, data }` and the raw userinfo is in `data`.
 */
export type UserinfoFetchMode = "direct" | "proxy";

/**
 * A minimal, DOM-type-free request shape. It is structurally a subset of the
 * Fetch API's `RequestInit`, so `fetch(url, init)` accepts it, while this file
 * still type-checks under the server (node) tsconfig the jest suite uses.
 */
export interface UserinfoRequestInit {
  method?: string;
  headers?: Record<string, string>;
  body?: string;
}

export interface UserinfoRequest {
  url: string;
  init: UserinfoRequestInit;
  mode: UserinfoFetchMode;
}

export function buildUserinfoRequest(
  provider: UserinfoProvider,
  token: string,
  opts: UserinfoRequestOptions = {},
): UserinfoRequest {
  const auth = `Bearer ${token}`;
  switch (provider) {
    case "github":
      return {
        url: "https://api.github.com/user",
        init: {
          headers: {
            Authorization: auth,
            "X-GitHub-Api-Version": "2022-11-28",
          },
        },
        mode: "direct",
      };
    case "google":
      return {
        url: "https://www.googleapis.com/oauth2/v1/userinfo?alt=json",
        init: { headers: { Authorization: auth } },
        mode: "direct",
      };
    case "gitlab":
      return {
        url: "https://gitlab.com/api/v4/user",
        init: { headers: { Authorization: auth } },
        mode: "direct",
      };
    case "auth0":
      if (!opts.auth0Domain) {
        throw new Error(
          "Auth0 domain not found. Please log in again with your Auth0 domain.",
        );
      }
      return {
        url: `https://${opts.auth0Domain}/userinfo`,
        init: { headers: { Authorization: auth } },
        mode: "direct",
      };
    case "zitadel":
      if (!opts.zitadelDomain) {
        throw new Error(
          "Zitadel domain not found. Please log in again with your Zitadel domain.",
        );
      }
      return {
        url: `https://${opts.zitadelDomain}/oidc/v1/userinfo`,
        init: { headers: { Authorization: auth } },
        mode: "direct",
      };
    case "linkedin":
      // api.linkedin.com has no CORS → direct browser fetch = "Failed to fetch".
      // Route the OIDC userinfo call through the same-origin /api/explore proxy
      // (server-side safeFetch); the token rides in the JSON body, never a
      // cross-origin Authorization header.
      return {
        url: "/api/explore",
        init: {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            provider: "linkedin",
            accessToken: token,
            endpoint: { id: "userinfo", method: "GET" },
          }),
        },
        mode: "proxy",
      };
    default: {
      // Exhaustiveness guard: a new provider must declare its fetch strategy.
      const exhaustive: never = provider;
      throw new Error(`Unsupported provider: ${String(exhaustive)}`);
    }
  }
}
