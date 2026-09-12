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
 * fastify-5 compat shim for field clients that claim a JSON body they don't
 * send.
 *
 * Deployed extension builds set `Content-Type: application/json` on EVERY
 * request, including body-less DELETEs. fastify 5 parses the body whenever a
 * content-type is present (v4 exempted DELETE) and rejects an empty JSON body
 * with 400 (FST_ERR_CTP_EMPTY_JSON_BODY) at the parsing step — before auth or
 * handlers run. Since extensions already in users' browsers can't be
 * force-updated, the server must tolerate the empty body: treat it as
 * `undefined` and delegate everything else to fastify's own secure parser
 * (which keeps proto-poisoning protection).
 */
export function registerEmptyJsonBodyTolerance(app: FastifyInstance): void {
  const defaultJsonParser = app.getDefaultJsonParser("error", "error");
  app.addContentTypeParser(
    "application/json",
    { parseAs: "string" },
    (req, body, done) => {
      if (body === "") {
        done(null, undefined);
        return;
      }
      defaultJsonParser(req, body as string, done);
    },
  );
}
