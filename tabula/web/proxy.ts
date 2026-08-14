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

import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { getApiUrl } from "./lib/runtime-config";
import { securityHeaders } from "./lib/security-headers";

// Security headers (including CSP's connect-src) are set here, per request,
// rather than via next.config.ts's `headers()` — that config is evaluated by
// `next build` and frozen into routes-manifest.json, so it can't reflect the
// per-environment API_URL Cloud Run env var when the same built image is
// promoted unchanged across dev/nonprod/prod (see lib/runtime-config.ts).
// Middleware runs as real per-request server code, so getApiUrl()'s server
// branch (process.env.API_URL) is read fresh on every request.
export function proxy(_request: NextRequest) {
  const response = NextResponse.next();
  for (const [key, value] of securityHeaders(getApiUrl())) {
    response.headers.set(key, value);
  }
  return response;
}

export const config = {
  matcher: "/:path*",
};
