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
 * Auth helpers shared across app bootstrap, routes, and the auth service.
 *
 * Covers two hardening concerns:
 *  1. JWT secret resolution that fails fast in production instead of falling
 *     back to a public default (the old `process.env.JWT_SECRET || 'supersecret'`
 *     let a misconfigured deploy sign every token with a known string).
 *  2. Refresh-token primitives backing the Session model: opaque refresh tokens
 *     are generated and only their SHA-256 hash is stored, so a database leak
 *     does not expose usable tokens.
 */
import { createHash, randomBytes } from "crypto";

/**
 * Access-token lifetime. Bounds the blast radius of a captured bearer token and
 * the window during which a stale `tier` claim is trusted. The extension sends
 * `Authorization: Bearer` and refreshes on 401 via POST /auth/refresh.
 */
export const ACCESS_TOKEN_TTL = process.env.JWT_EXPIRATION || "1h";

/** Refresh-token (Session) lifetime in days. */
export const REFRESH_TOKEN_TTL_DAYS = parseInt(
  process.env.REFRESH_TOKEN_TTL_DAYS || "30",
  10,
);

/** Dev/test-only fallback secret — never used when NODE_ENV is production. */
const DEV_FALLBACK_SECRET = "dev-only-insecure-secret-change-me";

/**
 * Resolve the JWT signing secret.
 *
 * - In production: JWT_SECRET MUST be set; otherwise throw so the process
 *   crash-loops instead of silently signing tokens with a guessable default.
 * - Otherwise (development/test): fall back to a clearly-labeled insecure
 *   secret so local dev and the test suite keep working without extra config.
 */
export function resolveJwtSecret(): string {
  const secret = process.env.JWT_SECRET;
  if (secret && secret.length > 0) {
    return secret;
  }
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "JWT_SECRET environment variable is required in production",
    );
  }
  return DEV_FALLBACK_SECRET;
}

/** Generate an opaque, URL-safe refresh token (raw value returned to client). */
export function generateRefreshToken(): string {
  return randomBytes(32).toString("hex");
}

/** Hash a refresh token for at-rest storage (only the hash is persisted). */
export function hashRefreshToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

/** Compute the absolute expiry for a new refresh-token session. */
export function refreshTokenExpiry(now: Date = new Date()): Date {
  const expiry = new Date(now);
  expiry.setDate(expiry.getDate() + REFRESH_TOKEN_TTL_DAYS);
  return expiry;
}
