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
 * Tests for the P1 defense-in-depth hardening:
 *   - security headers (CSP + the rest) on every response,
 *   - the hand-written in-memory rate limiter (429 + Retry-After),
 *   - the getSecret TTL cache (collapses repeated Secret Manager reads),
 *   - the 64kb JSON body limit (413 on oversized body).
 */

import express from "express";
import request from "supertest";

import { RateLimiter, rateLimitMiddleware, clientIp } from "../rateLimit.js";
import {
  securityHeaders,
  CONTENT_SECURITY_POLICY,
} from "../securityHeaders.js";

process.env.GOOGLE_CLOUD_PROJECT =
  process.env.GOOGLE_CLOUD_PROJECT || "test-project";

// Capture the underlying accessSecretVersion mock so the cache test can assert
// how many times the real Secret Manager read fired across getSecret() calls.
// Every secret name resolves to a non-empty payload so getSecret() caches it.
const accessSecretVersion = jest.fn(({ name }: { name: string }) =>
  Promise.resolve([{ payload: { data: `value-for:${name}` } }]),
);

jest.mock("@google-cloud/secret-manager", () => ({
  SecretManagerServiceClient: jest.fn().mockImplementation(() => ({
    accessSecretVersion,
  })),
}));

jest.mock("@google-cloud/logging-winston", () => ({
  LoggingWinston: jest.fn().mockImplementation(() => ({
    log: () => {},
    write: () => {},
  })),
}));

jest.mock("winston", () => {
  const fakeLogger = {
    info: () => {},
    error: () => {},
    warn: () => {},
    child: () => fakeLogger,
  };
  return {
    __esModule: true,
    default: {
      createLogger: () => fakeLogger,
      format: {
        combine: () => {},
        timestamp: () => {},
        errors: () => {},
        json: () => {},
        colorize: () => {},
        printf: () => {},
      },
      transports: { Console: function () {} },
    },
    createLogger: () => fakeLogger,
    format: {
      combine: () => {},
      timestamp: () => {},
      errors: () => {},
      json: () => {},
      colorize: () => {},
      printf: () => {},
    },
    transports: { Console: function () {} },
  };
});

import app from "../server.js";

describe("security headers", () => {
  it("sets CSP + the standard hardening headers on a sample route", async () => {
    const res = await request(app).get("/api/health");

    expect(res.status).toBe(200);
    // The load-bearing one: exact CSP string (no 'unsafe-inline' in script-src).
    expect(res.headers["content-security-policy"]).toBe(
      CONTENT_SECURITY_POLICY,
    );
    expect(res.headers["content-security-policy"]).toContain(
      "frame-ancestors 'none'",
    );
    expect(res.headers["content-security-policy"]).toContain(
      "script-src 'self'",
    );
    expect(res.headers["content-security-policy"]).not.toContain(
      "script-src 'self' 'unsafe-inline'",
    );

    expect(res.headers["x-content-type-options"]).toBe("nosniff");
    expect(res.headers["strict-transport-security"]).toBe(
      "max-age=31536000; includeSubDomains",
    );
    expect(res.headers["referrer-policy"]).toBe("no-referrer");
    expect(res.headers["x-frame-options"]).toBe("DENY");
    expect(res.headers["cross-origin-opener-policy"]).toBe("same-origin");
    // X-Powered-By is disabled.
    expect(res.headers["x-powered-by"]).toBeUndefined();
  });

  it("marks /api/* responses no-store", async () => {
    const res = await request(app).get("/api/health");
    expect(res.headers["cache-control"]).toBe("no-store");
  });
});

describe("rate limiter", () => {
  // Drive the middleware directly with a low limit so the test is fast and does
  // not depend on the production tier counts. Sweep timer disabled for a clean
  // synchronous test.
  function appWithLimiter(limit: number) {
    const limiter = new RateLimiter(
      { bucket: "test", limit, windowMs: 60_000 },
      60_000,
      /* enableSweep */ false,
    );
    const a = express();
    a.set("trust proxy", 1);
    a.use(
      "/x",
      rateLimitMiddleware({ bucket: "test", limit, windowMs: 60_000 }, limiter),
    );
    a.get("/x", (_req, res) => res.json({ ok: true }));
    return a;
  }

  it("returns 429 with Retry-After after the tier limit is exceeded", async () => {
    const limit = 3;
    const a = appWithLimiter(limit);

    // The first `limit` requests pass.
    for (let i = 0; i < limit; i++) {
      const ok = await request(a).get("/x");
      expect(ok.status).toBe(200);
    }

    // The (limit + 1)-th is rejected.
    const blocked = await request(a).get("/x");
    expect(blocked.status).toBe(429);
    expect(blocked.headers["retry-after"]).toBeDefined();
    expect(Number(blocked.headers["retry-after"])).toBeGreaterThan(0);
    expect(blocked.body.error).toMatch(/too many requests/i);
  });

  it("keys windows independently per client IP", () => {
    const limiter = new RateLimiter(
      { bucket: "perip", limit: 1, windowMs: 60_000 },
      60_000,
      false,
    );
    expect(limiter.hit("1.1.1.1").allowed).toBe(true);
    expect(limiter.hit("1.1.1.1").allowed).toBe(false); // same IP, over limit
    expect(limiter.hit("2.2.2.2").allowed).toBe(true); // different IP, fresh
  });

  it("prefers CF-Connecting-IP over req.ip", () => {
    const req = {
      headers: { "cf-connecting-ip": "203.0.113.7" },
      ip: "10.0.0.1",
    } as unknown as express.Request;
    expect(clientIp(req)).toBe("203.0.113.7");
  });
});

describe("getSecret TTL cache", () => {
  beforeEach(() => {
    accessSecretVersion.mockClear();
  });

  it("reads Secret Manager once across two getSecret calls within the TTL", async () => {
    // /api/oauth-hosted/init reads GITHUB_APP_OAUTH_CLIENT_ID via getSecret.
    // The first request populates the cache; the second must hit the cache, so
    // accessSecretVersion fires exactly once for that secret name across both.
    const body = {
      provider: "github",
      redirectUri: "https://example.com/callback",
    };

    await request(app).post("/api/oauth-hosted/init").send(body);
    await request(app).post("/api/oauth-hosted/init").send(body);

    const githubReads = accessSecretVersion.mock.calls.filter(([arg]) =>
      (arg as { name: string }).name.includes("GITHUB_APP_OAUTH_CLIENT_ID"),
    );
    expect(githubReads.length).toBe(1);
  });
});

describe("body limit", () => {
  it("rejects a JSON body larger than 64kb with 413", async () => {
    // ~70kb of JSON; comfortably over the 64kb limit.
    const huge = { blob: "a".repeat(70 * 1024) };
    const res = await request(app)
      .post("/api/oauth/token")
      .set("Content-Type", "application/json")
      .send(huge);

    expect(res.status).toBe(413);
  });
});
