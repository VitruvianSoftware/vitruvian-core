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
  apiOriginFor,
  buildContentSecurityPolicy,
  securityHeaders,
} from "./security-headers";

describe("apiOriginFor", () => {
  it("extracts the origin from a full API URL", () => {
    expect(apiOriginFor("https://tabula-api.vitruviansoftware.dev/api/v1")).toBe(
      "https://tabula-api.vitruviansoftware.dev",
    );
  });

  it("falls back to the local default on an unparsable URL", () => {
    expect(apiOriginFor("not a url")).toBe("http://localhost:8080");
  });
});

describe("buildContentSecurityPolicy", () => {
  it("scopes connect-src to self and the given API's origin only", () => {
    const csp = buildContentSecurityPolicy(
      "https://tabula-api.staging.vitruviansoftware.dev/api/v1",
    );
    expect(csp).toContain(
      "connect-src 'self' https://tabula-api.staging.vitruviansoftware.dev",
    );
    // Must not leak a DIFFERENT environment's host into the policy — this is
    // the exact class of bug this file exists to prevent.
    expect(csp).not.toContain("tabula-api.dev.vitruviansoftware.dev");
    expect(csp).not.toContain("tabula-api.vitruviansoftware.dev/");
  });

  it("still forbids framing and restricts other directives", () => {
    const csp = buildContentSecurityPolicy("https://tabula-api.vitruviansoftware.dev/api/v1");
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).toContain("object-src 'none'");
    expect(csp).toContain("default-src 'self'");
  });
});

describe("securityHeaders", () => {
  it("returns CSP plus the standard hardening headers", () => {
    const headers = Object.fromEntries(
      securityHeaders("https://tabula-api.vitruviansoftware.dev/api/v1"),
    );
    expect(headers["Content-Security-Policy"]).toContain("tabula-api.vitruviansoftware.dev");
    expect(headers["X-Frame-Options"]).toBe("DENY");
    expect(headers["X-Content-Type-Options"]).toBe("nosniff");
    expect(headers["Referrer-Policy"]).toBe("no-referrer");
  });
});
