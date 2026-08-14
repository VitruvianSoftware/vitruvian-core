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
 * Defense-in-depth security headers. The PRIMARY XSS guard is React's default
 * text escaping (note bodies render as escaped text, never
 * dangerouslySetInnerHTML; user URLs go through lib/safeHref). This CSP is a
 * secondary layer — and, because script-src still allows 'unsafe-inline' (see
 * below), it is not yet a hard backstop against injected inline script.
 * frame-ancestors + Referrer-Policy specifically protect the relay landing (no
 * clickjacking, and the /s/<relayId> handle never leaks via Referer on link-out).
 * NOTE: script-src keeps 'unsafe-inline' for Next's hydration bootstrap AND the
 * runtime-config script tag (app/layout.tsx); tightening it away needs a
 * per-request nonce pipeline (follow-up). 'unsafe-eval' is NOT needed at
 * runtime, so it is omitted.
 *
 * connect-src is derived from the CALLER-SUPPLIED apiUrl rather than a module-
 * level constant: this file is invoked per-request from proxy.ts, which
 * reads apiUrl fresh via runtime-config.ts's server branch. next.config.ts's
 * `headers()` would have made this a build-time constant again (embedded into
 * routes-manifest.json by `next build`), which is exactly the bug this whole
 * change fixes for the API host itself — see runtime-config.ts.
 */
export function apiOriginFor(apiUrl: string): string {
  try {
    return new URL(apiUrl).origin;
  } catch {
    return "http://localhost:8080";
  }
}

export function buildContentSecurityPolicy(apiUrl: string): string {
  const apiOrigin = apiOriginFor(apiUrl);
  return [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: https:",
    `connect-src 'self' ${apiOrigin}`,
    "object-src 'none'",
    "base-uri 'self'",
    "frame-ancestors 'none'",
  ].join("; ");
}

export function securityHeaders(apiUrl: string): [string, string][] {
  return [
    ["Content-Security-Policy", buildContentSecurityPolicy(apiUrl)],
    ["X-Frame-Options", "DENY"],
    ["X-Content-Type-Options", "nosniff"],
    ["Referrer-Policy", "no-referrer"],
  ];
}
