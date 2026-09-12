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
 * Unit tests for lib/auth: JWT secret resolution and refresh-token primitives.
 */
import {
  resolveJwtSecret,
  generateRefreshToken,
  hashRefreshToken,
  refreshTokenExpiry,
} from "../../src/lib/auth";

describe("lib/auth", () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  describe("resolveJwtSecret", () => {
    it("returns the configured JWT_SECRET when present", () => {
      process.env.JWT_SECRET = "a-real-secret";
      expect(resolveJwtSecret()).toBe("a-real-secret");
    });

    it("throws in production when JWT_SECRET is missing (fail fast)", () => {
      delete process.env.JWT_SECRET;
      process.env.NODE_ENV = "production";
      expect(() => resolveJwtSecret()).toThrow(/JWT_SECRET/);
    });

    it("falls back to a labeled dev secret outside production", () => {
      delete process.env.JWT_SECRET;
      process.env.NODE_ENV = "development";
      const secret = resolveJwtSecret();
      expect(secret).toContain("dev-only");
      // The old public default must never be used.
      expect(secret).not.toBe("supersecret");
    });

    it("throws on an empty-string JWT_SECRET in production", () => {
      process.env.JWT_SECRET = "";
      process.env.NODE_ENV = "production";
      expect(() => resolveJwtSecret()).toThrow(/JWT_SECRET/);
    });
  });

  describe("refresh token primitives", () => {
    it("generates distinct opaque tokens", () => {
      const a = generateRefreshToken();
      const b = generateRefreshToken();
      expect(a).not.toBe(b);
      expect(a.length).toBeGreaterThan(32);
    });

    it("hashes deterministically and irreversibly (not the raw token)", () => {
      const token = generateRefreshToken();
      const hash1 = hashRefreshToken(token);
      const hash2 = hashRefreshToken(token);
      expect(hash1).toBe(hash2);
      expect(hash1).not.toBe(token);
      expect(hash1).toHaveLength(64); // sha256 hex
    });

    it("computes an expiry in the future", () => {
      const now = new Date("2026-01-01T00:00:00Z");
      const expiry = refreshTokenExpiry(now);
      expect(expiry.getTime()).toBeGreaterThan(now.getTime());
    });
  });
});
