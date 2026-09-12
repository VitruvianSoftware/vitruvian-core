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
 * Server-OWNED API Explorer endpoint table.
 *
 * The frontend (frontend/utils/apiEndpoints.ts) advertises these same endpoints
 * for UX, but the server MUST NOT trust the URL the client sends — that is the
 * SSRF hole. Instead /api/explore looks the (provider, endpointId) pair up in
 * THIS table, which is the single source of truth for what host the server will
 * actually call:
 *
 *   - `kind: 'fixed'`  — github/google/gitlab/linkedin. The full provider API
 *     URL is a hardcoded constant here; the client cannot influence the host.
 *   - `kind: 'issuer'` — auth0/zitadel. Only a relative `path` is fixed here;
 *     the host is the user's IdP issuer domain, which the caller MUST validate
 *     via resolveAndPin() before this URL is fetched.
 *
 * Keep this in sync with frontend/utils/apiEndpoints.ts. Tests pin that the ids
 * line up so a drift is caught in CI.
 */

export type ExploreEndpointKind = "fixed" | "issuer";

export interface ExploreEndpointDef {
  method: string;
  kind: ExploreEndpointKind;
  /** Absolute provider API URL — present for kind: 'fixed'. */
  url?: string;
  /** Issuer-relative path (leading slash) — present for kind: 'issuer'. */
  path?: string;
}

export type ExploreProvider =
  "github" | "google" | "gitlab" | "auth0" | "zitadel" | "linkedin";

/**
 * The full server-owned table. Mirrors frontend/utils/apiEndpoints.ts.
 */
export const EXPLORE_ENDPOINTS: Record<
  ExploreProvider,
  Record<string, ExploreEndpointDef>
> = {
  github: {
    user: { method: "GET", kind: "fixed", url: "https://api.github.com/user" },
    user_emails: {
      method: "GET",
      kind: "fixed",
      url: "https://api.github.com/user/emails",
    },
    user_repos: {
      method: "GET",
      kind: "fixed",
      url: "https://api.github.com/user/repos",
    },
    user_orgs: {
      method: "GET",
      kind: "fixed",
      url: "https://api.github.com/user/orgs",
    },
    user_followers: {
      method: "GET",
      kind: "fixed",
      url: "https://api.github.com/user/followers",
    },
    user_following: {
      method: "GET",
      kind: "fixed",
      url: "https://api.github.com/user/following",
    },
  },
  google: {
    userinfo: {
      method: "GET",
      kind: "fixed",
      url: "https://www.googleapis.com/oauth2/v1/userinfo",
    },
    userinfo_v2: {
      method: "GET",
      kind: "fixed",
      url: "https://www.googleapis.com/oauth2/v2/userinfo",
    },
    people_me: {
      method: "GET",
      kind: "fixed",
      url: "https://people.googleapis.com/v1/people/me?personFields=names,emailAddresses,photos,urls,organizations",
    },
    gmail_profile: {
      method: "GET",
      kind: "fixed",
      url: "https://gmail.googleapis.com/gmail/v1/users/me/profile",
    },
  },
  gitlab: {
    user: {
      method: "GET",
      kind: "fixed",
      url: "https://gitlab.com/api/v4/user",
    },
    user_projects: {
      method: "GET",
      kind: "fixed",
      url: "https://gitlab.com/api/v4/projects?membership=true",
    },
    user_groups: {
      method: "GET",
      kind: "fixed",
      url: "https://gitlab.com/api/v4/groups?min_access_level=10",
    },
    user_keys: {
      method: "GET",
      kind: "fixed",
      url: "https://gitlab.com/api/v4/user/keys",
    },
  },
  auth0: {
    // Issuer-relative: host is the user's Auth0 tenant domain.
    userinfo: { method: "GET", kind: "issuer", path: "/userinfo" },
  },
  zitadel: {
    // Issuer-relative: host is the resolved Zitadel domain.
    userinfo: { method: "GET", kind: "issuer", path: "/oidc/v1/userinfo" },
  },
  linkedin: {
    // "Sign In with LinkedIn using OpenID Connect": a single userinfo GET
    // returns the profile + email. The legacy /v2/people/~ + /v2/emailAddress
    // endpoints (r_liteprofile/r_emailaddress) were retired in 2023.
    userinfo: {
      method: "GET",
      kind: "fixed",
      url: "https://api.linkedin.com/v2/userinfo",
    },
  },
};

/** Thrown when a (provider, endpointId) is not in the server-owned table. */
export class UnknownExploreEndpointError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "UnknownExploreEndpointError";
    Object.setPrototypeOf(this, UnknownExploreEndpointError.prototype);
  }
}

/**
 * Resolve a (provider, endpointId) — and, for issuer providers, the validated
 * issuer domain — to the ABSOLUTE URL the server will fetch.
 *
 * Throws UnknownExploreEndpointError for any provider/endpointId not in the
 * table, or for an issuer endpoint called without an issuerDomain. The caller
 * MUST have validated `issuerDomain` via resolveAndPin() before calling this;
 * this function only assembles the URL — it performs no network egress and no
 * SSRF check of its own.
 */
export function resolveExploreTarget(
  provider: string,
  endpointId: string,
  issuerDomain?: string,
): string {
  const providerTable = (
    EXPLORE_ENDPOINTS as Record<string, Record<string, ExploreEndpointDef>>
  )[provider];
  if (!providerTable) {
    throw new UnknownExploreEndpointError(`unknown provider: ${provider}`);
  }

  const def = providerTable[endpointId];
  if (!def) {
    throw new UnknownExploreEndpointError(
      `unknown endpoint '${endpointId}' for provider '${provider}'`,
    );
  }

  if (def.kind === "fixed") {
    if (!def.url) {
      // Defensive: a 'fixed' entry must carry an absolute URL.
      throw new UnknownExploreEndpointError(
        `endpoint '${endpointId}' for provider '${provider}' has no url`,
      );
    }
    return def.url;
  }

  // kind === "issuer": prefix the validated issuer domain.
  if (!issuerDomain) {
    throw new UnknownExploreEndpointError(
      `issuer domain required for provider '${provider}'`,
    );
  }
  if (!def.path) {
    throw new UnknownExploreEndpointError(
      `endpoint '${endpointId}' for provider '${provider}' has no path`,
    );
  }
  return `https://${issuerDomain}${def.path}`;
}
