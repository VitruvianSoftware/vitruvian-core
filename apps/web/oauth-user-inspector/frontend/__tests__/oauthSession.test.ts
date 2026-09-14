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
 * Regression coverage for the BYO (bring-your-own-credentials) refresh/revoke
 * credential lifecycle. The historical bug: at token-exchange time the
 * user-supplied credentials lived only in a single-use sessionStorage entry
 * that was cleared right after exchange, and refresh/revoke unconditionally
 * tried hosted-first (Secret Manager credentials) before falling back to that
 * already-cleared entry — so BYO refresh/revoke always failed. The fix persists
 * an `isHosted` flag (plus the BYO credentials) into auth_meta and branches on
 * it. These tests pin that behaviour for every provider.
 */

import {
  buildAuthMeta,
  buildRefreshRequest,
  buildRevokeRequest,
  parseAuthMeta,
  MissingCredentialsError,
  type ByoCredentials,
  type StoredAuthMeta,
} from "../utils/oauthSession";

const FETCHED_AT = 1_700_000_000_000;

describe("buildAuthMeta", () => {
  it("persists the BYO client credentials and isHosted=false for a BYO session", () => {
    const byoCreds: ByoCredentials = {
      clientId: "byo-client-id",
      clientSecret: "byo-client-secret",
    };
    const meta = buildAuthMeta(
      {
        access_token: "at",
        refresh_token: "rt",
        expires_in: 3600,
        token_type: "Bearer",
        scope: "openid profile",
      } as any,
      false,
      byoCreds,
      FETCHED_AT,
    );

    expect(meta.isHosted).toBe(false);
    expect(meta.client_id).toBe("byo-client-id");
    expect(meta.client_secret).toBe("byo-client-secret");
    expect(meta.refresh_token).toBe("rt");
    expect(meta.fetched_at).toBe(FETCHED_AT);
  });

  it("does NOT persist client credentials for a hosted session", () => {
    const meta = buildAuthMeta(
      { refresh_token: "rt", expires_in: 3600 } as any,
      true,
      null,
      FETCHED_AT,
    );

    expect(meta.isHosted).toBe(true);
    expect(meta.client_id).toBeUndefined();
    expect(meta.client_secret).toBeUndefined();
  });

  it("captures the provider domain for BYO auth0/zitadel, preferring the server echo", () => {
    const auth0Meta = buildAuthMeta(
      { auth0_domain: "tenant.us.auth0.com" } as any,
      false,
      {
        clientId: "id",
        clientSecret: "secret",
        auth0Domain: "tenant.us.auth0.com",
      },
      FETCHED_AT,
    );
    expect(auth0Meta.auth0_domain).toBe("tenant.us.auth0.com");

    // Falls back to the user-supplied domain when the server omits it.
    const zitadelMeta = buildAuthMeta(
      {} as any,
      false,
      {
        clientId: "id",
        clientSecret: "secret",
        zitadelDomain: "auth.ipv1337.dev",
      },
      FETCHED_AT,
    );
    expect(zitadelMeta.zitadel_domain).toBe("auth.ipv1337.dev");
  });
});

describe("buildRefreshRequest", () => {
  it("replays the stored BYO credentials with isHosted=false (the regression)", () => {
    const meta = buildAuthMeta(
      { refresh_token: "rt" } as any,
      false,
      { clientId: "byo-client-id", clientSecret: "byo-client-secret" },
      FETCHED_AT,
    );

    const body = buildRefreshRequest("google", "rt", meta);

    expect(body).toEqual({
      provider: "google",
      refreshToken: "rt",
      isHosted: false,
      clientId: "byo-client-id",
      clientSecret: "byo-client-secret",
    });
  });

  it("forwards the BYO auth0 domain so the server can reach the right tenant", () => {
    const meta = buildAuthMeta(
      { auth0_domain: "tenant.us.auth0.com" } as any,
      false,
      {
        clientId: "byo-client-id",
        clientSecret: "byo-client-secret",
        auth0Domain: "tenant.us.auth0.com",
      },
      FETCHED_AT,
    );

    const body = buildRefreshRequest("auth0", "rt", meta);

    expect(body.isHosted).toBe(false);
    expect(body.clientId).toBe("byo-client-id");
    expect(body.auth0Domain).toBe("tenant.us.auth0.com");
  });

  it("forwards the BYO zitadel domain", () => {
    const meta = buildAuthMeta(
      { zitadel_domain: "auth.ipv1337.dev" } as any,
      false,
      {
        clientId: "byo-client-id",
        clientSecret: "byo-client-secret",
        zitadelDomain: "auth.ipv1337.dev",
      },
      FETCHED_AT,
    );

    const body = buildRefreshRequest("zitadel", "rt", meta);

    expect(body.isHosted).toBe(false);
    expect(body.clientId).toBe("byo-client-id");
    expect(body.zitadelDomain).toBe("auth.ipv1337.dev");
  });

  it("refreshes a hosted session with isHosted=true and no client credentials", () => {
    const meta = buildAuthMeta(
      { refresh_token: "rt" } as any,
      true,
      null,
      FETCHED_AT,
    );

    const body = buildRefreshRequest("google", "rt", meta);

    expect(body).toEqual({
      provider: "google",
      refreshToken: "rt",
      isHosted: true,
    });
    expect(body.clientId).toBeUndefined();
    expect(body.clientSecret).toBeUndefined();
  });

  it("throws rather than falling back to hosted creds when BYO creds are missing", () => {
    const meta: StoredAuthMeta = { isHosted: false };
    expect(() => buildRefreshRequest("google", "rt", meta)).toThrow(
      MissingCredentialsError,
    );
    expect(() => buildRefreshRequest("google", "rt", null)).toThrow(
      MissingCredentialsError,
    );
  });
});

describe("buildRevokeRequest", () => {
  it("replays the stored BYO credentials with isHosted=false", () => {
    const meta = buildAuthMeta(
      {} as any,
      false,
      { clientId: "byo-client-id", clientSecret: "byo-client-secret" },
      FETCHED_AT,
    );

    const body = buildRevokeRequest("gitlab", "access-token", meta);

    expect(body).toEqual({
      provider: "gitlab",
      token: "access-token",
      tokenTypeHint: "access_token",
      isHosted: false,
      clientId: "byo-client-id",
      clientSecret: "byo-client-secret",
    });
  });

  it("revokes a hosted session with isHosted=true and no client credentials", () => {
    const meta = buildAuthMeta({} as any, true, null, FETCHED_AT);

    const body = buildRevokeRequest("github", "access-token", meta);

    expect(body).toEqual({
      provider: "github",
      token: "access-token",
      tokenTypeHint: "access_token",
      isHosted: true,
    });
  });

  it("returns null (→ local logout) for a BYO session with no stored credentials", () => {
    expect(
      buildRevokeRequest("github", "access-token", { isHosted: false }),
    ).toBeNull();
    expect(buildRevokeRequest("github", "access-token", null)).toBeNull();
  });
});

describe("parseAuthMeta", () => {
  it("round-trips a persisted BYO session so refresh replays the same credentials", () => {
    const stored = JSON.stringify(
      buildAuthMeta(
        { refresh_token: "rt" } as any,
        false,
        { clientId: "byo-client-id", clientSecret: "byo-client-secret" },
        FETCHED_AT,
      ),
    );

    const body = buildRefreshRequest("google", "rt", parseAuthMeta(stored));

    expect(body.isHosted).toBe(false);
    expect(body.clientId).toBe("byo-client-id");
    expect(body.clientSecret).toBe("byo-client-secret");
  });

  it("tolerates absent or corrupt metadata", () => {
    expect(parseAuthMeta(null)).toBeNull();
    expect(parseAuthMeta("not json{")).toBeNull();
  });
});
