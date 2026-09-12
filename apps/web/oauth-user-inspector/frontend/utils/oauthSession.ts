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

import type {
  AuthProvider,
  TokenRefreshRequest,
  TokenRevocationRequest,
} from "../types";

/**
 * Credentials a user supplies for a bring-your-own (BYO) OAuth login. These are
 * captured at login time in the single-use sessionStorage `oauth_credentials`
 * entry, which is cleared immediately after the code-for-token exchange.
 */
export interface ByoCredentials {
  clientId: string;
  clientSecret: string;
  auth0Domain?: string;
  zitadelDomain?: string;
}

/**
 * The shape persisted to localStorage under `auth_meta`. Alongside the token
 * metadata used to render the session, it records HOW the session
 * authenticated (`isHosted`) and, for BYO sessions, the client credentials
 * needed to later refresh/revoke the token.
 *
 * Why persist the BYO credentials here? They are issued to the user's OWN OAuth
 * client, so refresh/revoke must replay them. The sessionStorage
 * `oauth_credentials` entry is single-use (cleared right after the token
 * exchange), so without stashing them here a later refresh/revoke would have
 * nothing to send and would be forced to (incorrectly) fall back to the hosted
 * Secret Manager credentials — which the IdP rejects with invalid_client /
 * invalid_grant for a token issued to a different client.
 */
export interface StoredAuthMeta {
  scope?: string;
  expires_in?: number;
  token_type?: string;
  id_token?: string;
  refresh_token?: string;
  fetched_at?: number;
  auth0_domain?: string;
  zitadel_domain?: string;
  // Credential-lifecycle fields (added to fix BYO refresh/revoke):
  isHosted?: boolean;
  client_id?: string;
  client_secret?: string;
}

/** Raw token-exchange response fields we care about when persisting metadata. */
interface TokenExchangeResponse {
  scope?: string;
  expires_in?: number;
  token_type?: string;
  id_token?: string;
  refresh_token?: string;
  auth0_domain?: string;
  zitadel_domain?: string;
}

/**
 * Thrown when a BYO session needs to refresh but its stored client credentials
 * are missing (e.g. an old session persisted before this fix). The caller
 * should surface a "please log in again" message rather than silently falling
 * back to hosted credentials.
 */
export class MissingCredentialsError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MissingCredentialsError";
  }
}

/**
 * Build the `auth_meta` blob to persist after a successful token exchange.
 *
 * For hosted sessions only `isHosted: true` is recorded; the server resolves
 * the client credentials from Secret Manager on every refresh/revoke. For BYO
 * sessions the user-supplied client id/secret (and any provider domain) are
 * stored so they can be replayed later.
 */
export function buildAuthMeta(
  tokenData: TokenExchangeResponse,
  isHosted: boolean,
  byoCreds: ByoCredentials | null,
  fetchedAt: number,
): StoredAuthMeta {
  const meta: StoredAuthMeta = {
    scope: tokenData.scope,
    expires_in: tokenData.expires_in,
    token_type: tokenData.token_type,
    id_token: tokenData.id_token,
    refresh_token: tokenData.refresh_token,
    fetched_at: fetchedAt,
    // Prefer the domain echoed back by the server; fall back to what the user
    // supplied so the value is always present for BYO auth0/zitadel sessions.
    auth0_domain: tokenData.auth0_domain || byoCreds?.auth0Domain,
    zitadel_domain: tokenData.zitadel_domain || byoCreds?.zitadelDomain,
    isHosted,
  };

  if (!isHosted && byoCreds) {
    meta.client_id = byoCreds.clientId;
    meta.client_secret = byoCreds.clientSecret;
  }

  return meta;
}

/**
 * Build the POST body for `/api/oauth/refresh` from the persisted session
 * metadata. Hosted sessions refresh with `isHosted: true` (server-side Secret
 * Manager credentials); BYO sessions replay their stored client credentials.
 *
 * Throws {@link MissingCredentialsError} for a BYO session with no stored
 * credentials instead of falling back to hosted credentials (which the IdP
 * would reject for a token issued to the user's own client).
 */
export function buildRefreshRequest(
  provider: AuthProvider,
  refreshToken: string,
  meta: StoredAuthMeta | null,
): TokenRefreshRequest {
  const isHosted = !!meta?.isHosted;
  const body: TokenRefreshRequest = { provider, refreshToken, isHosted };

  if (!isHosted) {
    if (!meta?.client_id || !meta?.client_secret) {
      throw new MissingCredentialsError(
        "No OAuth credentials available for token refresh. Please log in again.",
      );
    }
    body.clientId = meta.client_id;
    body.clientSecret = meta.client_secret;
    if (meta.auth0_domain) body.auth0Domain = meta.auth0_domain;
    if (meta.zitadel_domain) body.zitadelDomain = meta.zitadel_domain;
  }

  return body;
}

/**
 * Build the POST body for `/api/oauth/revoke` from the persisted session
 * metadata. Returns `null` for a BYO session with no stored credentials,
 * signalling the caller to just log out locally (some providers/sessions have
 * no usable revocation path).
 */
export function buildRevokeRequest(
  provider: AuthProvider,
  token: string,
  meta: StoredAuthMeta | null,
): TokenRevocationRequest | null {
  const isHosted = !!meta?.isHosted;
  const body: TokenRevocationRequest = {
    provider,
    token,
    tokenTypeHint: "access_token",
    isHosted,
  };

  if (!isHosted) {
    if (!meta?.client_id || !meta?.client_secret) {
      return null;
    }
    body.clientId = meta.client_id;
    body.clientSecret = meta.client_secret;
    if (meta.auth0_domain) body.auth0Domain = meta.auth0_domain;
    if (meta.zitadel_domain) body.zitadelDomain = meta.zitadel_domain;
  }

  return body;
}

/** Safely parse the persisted `auth_meta` JSON blob, tolerating absent/corrupt data. */
export function parseAuthMeta(raw: string | null): StoredAuthMeta | null {
  if (!raw) return null;
  try {
    return JSON.parse(raw) as StoredAuthMeta;
  } catch {
    return null;
  }
}
