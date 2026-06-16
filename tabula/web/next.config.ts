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

import type { NextConfig } from "next";

// Defense-in-depth security headers. The PRIMARY XSS guard is React's default
// text escaping (note bodies render as escaped text, never
// dangerouslySetInnerHTML; user URLs go through lib/safeHref). This CSP is a
// secondary layer — and, because script-src still allows 'unsafe-inline' (see
// below), it is not yet a hard backstop against injected inline script.
// frame-ancestors + Referrer-Policy specifically protect the relay landing (no
// clickjacking, and the /s/<relayId> handle never leaks via Referer on link-out).
// NOTE: script-src keeps 'unsafe-inline' for Next's hydration bootstrap;
// tightening it away needs a per-request nonce pipeline (follow-up). 'unsafe-eval'
// is NOT needed at runtime, so it is omitted. connect-src hardcodes the dev API
// origin, matching the rest of the app (lib/data.ts / lib/auth.ts).
const CSP = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: https:",
  "connect-src 'self' http://localhost:8080",
  "object-src 'none'",
  "base-uri 'self'",
  "frame-ancestors 'none'",
].join("; ");

const nextConfig: NextConfig = {
  // geist ships ESM-only; transpile it for both next build and next/jest
  // (next/jest derives its jest transformIgnorePatterns from this list).
  transpilePackages: ["geist"],
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "Content-Security-Policy", value: CSP },
          { key: "X-Frame-Options", value: "DENY" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "no-referrer" },
        ],
      },
    ];
  },
};

export default nextConfig;
