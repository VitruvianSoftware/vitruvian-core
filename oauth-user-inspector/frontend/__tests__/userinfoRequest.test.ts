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

import {
  buildUserinfoRequest,
  type UserinfoProvider,
} from "../utils/userinfoRequest";

describe("buildUserinfoRequest", () => {
  // The regression this guards: after the OIDC migration the SPA fetched
  // https://api.linkedin.com/v2/userinfo DIRECTLY from the browser, but
  // api.linkedin.com sends no CORS headers, so the browser blocked it and the
  // app showed "Failed to fetch". LinkedIn MUST instead route through the
  // same-origin /api/explore proxy (server-side safeFetch).
  it("routes LinkedIn userinfo through the same-origin /api/explore proxy, never api.linkedin.com", () => {
    const req = buildUserinfoRequest("linkedin", "tok-abc");

    expect(req.mode).toBe("proxy");
    expect(req.url).toBe("/api/explore");
    expect(req.url).not.toContain("api.linkedin.com");
    expect(req.init.method).toBe("POST");
    expect(req.init.headers).toMatchObject({
      "Content-Type": "application/json",
    });
    // No cross-origin Authorization header (the token rides in the body).
    expect(req.init.headers?.Authorization).toBeUndefined();

    const body = JSON.parse(req.init.body as string);
    expect(body).toEqual({
      provider: "linkedin",
      accessToken: "tok-abc",
      endpoint: { id: "userinfo", method: "GET" },
    });
  });

  it("fetches GitHub directly with the bearer + API-version header", () => {
    const req = buildUserinfoRequest("github", "t");
    expect(req.mode).toBe("direct");
    expect(req.url).toBe("https://api.github.com/user");
    expect(req.init.method).toBeUndefined(); // GET
    expect(req.init.headers).toEqual({
      Authorization: "Bearer t",
      "X-GitHub-Api-Version": "2022-11-28",
    });
  });

  it.each<[UserinfoProvider, string]>([
    ["google", "https://www.googleapis.com/oauth2/v1/userinfo?alt=json"],
    ["gitlab", "https://gitlab.com/api/v4/user"],
  ])("fetches %s directly with a bearer token", (provider, url) => {
    const req = buildUserinfoRequest(provider, "t");
    expect(req.mode).toBe("direct");
    expect(req.url).toBe(url);
    expect(req.init.headers).toEqual({ Authorization: "Bearer t" });
  });

  it("targets the caller-supplied issuer domain for auth0 and zitadel", () => {
    expect(
      buildUserinfoRequest("auth0", "t", { auth0Domain: "acme.us.auth0.com" })
        .url,
    ).toBe("https://acme.us.auth0.com/userinfo");
    expect(
      buildUserinfoRequest("zitadel", "t", {
        zitadelDomain: "auth.ipv1337.dev",
      }).url,
    ).toBe("https://auth.ipv1337.dev/oidc/v1/userinfo");
  });

  it("throws when a required issuer domain is missing", () => {
    expect(() => buildUserinfoRequest("auth0", "t")).toThrow(/Auth0 domain/);
    expect(() => buildUserinfoRequest("zitadel", "t")).toThrow(
      /Zitadel domain/,
    );
  });

  it("every supported provider yields a usable request", () => {
    const providers: UserinfoProvider[] = [
      "github",
      "google",
      "gitlab",
      "linkedin",
    ];
    for (const p of providers) {
      const req = buildUserinfoRequest(p, "t");
      expect(req.url.length).toBeGreaterThan(0);
      expect(["direct", "proxy"]).toContain(req.mode);
    }
  });
});
