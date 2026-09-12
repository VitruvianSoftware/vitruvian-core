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

import { Request, Response, NextFunction } from "express";

/**
 * Content-Security-Policy for the OAuth User Inspector SPA.
 *
 * This is the load-bearing header: the app holds live OAuth access/refresh
 * tokens in the browser's localStorage, so an XSS that can run attacker JS can
 * exfiltrate them. A strict `script-src 'self'` (NO 'unsafe-inline', NO
 * 'unsafe-eval') is what stops an injected inline <script> or javascript: URL
 * from executing.
 *
 * Directive-by-directive rationale:
 *  - default-src 'self'            — deny by default; everything below is a
 *                                    deliberate, narrow opening.
 *  - script-src 'self'             — only our own bundled JS runs. The Vite
 *                                    build emits a hashed <script type="module">
 *                                    referencing a same-origin file (verified:
 *                                    no inline <script> in dist/index.html), so
 *                                    'self' is sufficient and we never weaken to
 *                                    'unsafe-inline'.
 *  - style-src 'self' 'unsafe-inline'
 *                                  — React injects inline styles via the
 *                                    `style` prop / styled runtime; 'unsafe-inline'
 *                                    for STYLE only is the standard, low-risk
 *                                    concession (CSS injection is not script
 *                                    execution).
 *  - img-src 'self' https: data:  — provider avatars are fetched from arbitrary
 *                                    https hosts (GitHub/Google/Gitlab CDNs) and
 *                                    some are inline data: URIs.
 *  - font-src 'self'              — fonts ship with the bundle.
 *  - connect-src 'self' https:    — the SPA loads the post-login profile /
 *                                    userinfo by fetching provider APIs DIRECTLY
 *                                    from the browser (api.github.com,
 *                                    www.googleapis.com, gitlab.com, and the
 *                                    user's own auth0/zitadel issuer host for
 *                                    BYO), so arbitrary https hosts must be
 *                                    allowed. 'self' https: still blocks http/ws;
 *                                    the XSS containment is script-src 'self' (an
 *                                    injected script can't run, so it cannot
 *                                    issue a fetch to abuse connect-src).
 *                                    [connect-src 'self' alone broke every
 *                                    provider's post-login fetch — see #381.]
 *  - frame-ancestors 'none'       — cannot be framed (clickjacking).
 *  - base-uri 'self'              — block <base> tag hijacking of relative URLs.
 *  - form-action 'self'          — forms can only post back to us.
 *  - object-src 'none'           — no plugins/embeds.
 */
export const CONTENT_SECURITY_POLICY =
  "default-src 'self'; " +
  "script-src 'self'; " +
  "style-src 'self' 'unsafe-inline'; " +
  "img-src 'self' https: data:; " +
  "font-src 'self'; " +
  "connect-src 'self' https:; " +
  "frame-ancestors 'none'; " +
  "base-uri 'self'; " +
  "form-action 'self'; " +
  "object-src 'none'";

/**
 * Defense-in-depth security headers, applied to EVERY response. Registered as
 * the very first middleware (before the request logger) so headers are present
 * even on early returns / error paths.
 */
export function securityHeaders() {
  return (req: Request, res: Response, next: NextFunction): void => {
    // The primary XSS containment for tokens-in-localStorage.
    res.setHeader("Content-Security-Policy", CONTENT_SECURITY_POLICY);
    // Force HTTPS for a year incl. subdomains (served behind Cloudflare/Cloud Run TLS).
    res.setHeader(
      "Strict-Transport-Security",
      "max-age=31536000; includeSubDomains",
    );
    // Don't let browsers MIME-sniff a response into an executable type.
    res.setHeader("X-Content-Type-Options", "nosniff");
    // Never leak the (token-bearing) URL/path to third parties via Referer.
    res.setHeader("Referrer-Policy", "no-referrer");
    // Legacy clickjacking guard (frame-ancestors covers modern browsers).
    res.setHeader("X-Frame-Options", "DENY");
    // Isolate our browsing context from any window.opener it might have.
    res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
    next();
  };
}
