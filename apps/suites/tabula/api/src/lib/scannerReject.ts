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

import type { FastifyInstance } from "fastify";

/**
 * Fast-reject for obvious vulnerability-scanner probes.
 *
 * An internet-facing Cloud Run service gets a constant background drip of
 * automated probes for other people's software (/.env, /.git/config,
 * WordPress, phpMyAdmin, xmlrpc). None of these paths can ever exist here,
 * yet each one used to run the full request pipeline -- the rate-limit
 * plugin's Redis round trip, request logging, the 404 handler -- and, on a
 * scale-to-zero service, could keep an instance warm (or wake one up) for
 * nothing. Answering 404 in the very first onRequest hook skips all of it.
 *
 * Deliberately a short, conservative prefix list: a false positive here would
 * hide a real route, so only prefixes that can never collide with the API
 * (whose entire surface lives under /api/v1, /health and /) are listed.
 */
export const SCANNER_PROBE_PREFIXES: readonly string[] = [
  "/.env",
  "/.git",
  "/wp-",
  "/phpmyadmin",
  "/xmlrpc.php",
];

/** True when the request path (no query string) is a known scanner probe. */
export function isScannerProbePath(path: string): boolean {
  const pathname = path.split("?", 1)[0].toLowerCase();
  return SCANNER_PROBE_PREFIXES.some((prefix) => pathname.startsWith(prefix));
}

/**
 * Register the fast-reject as an onRequest hook. Call it BEFORE any plugin
 * registration so it is the first hook in the chain.
 */
export function registerScannerFastReject(app: FastifyInstance): void {
  app.addHook("onRequest", async (request, reply) => {
    if (!isScannerProbePath(request.url)) return undefined;
    return reply
      .code(404)
      .send({ statusCode: 404, error: "Not Found", message: "Not Found" });
  });
}
