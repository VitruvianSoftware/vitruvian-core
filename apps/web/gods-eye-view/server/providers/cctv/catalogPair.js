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

import { readResponseTextCapped } from '../common/http.js';

/**
 * Read catalogs that are only useful together, because the pack joins them.
 *
 * The requests share one deadline and refuse redirects. Whichever fails first
 * (before its headers, on its status, or while its capped body is read or
 * parsed) aborts the others at once, so a stalled feed is not waited on until
 * the deadline. Every response body is released, including one that arrives
 * after another feed has already failed.
 *
 * @param {Array<{url: string, label: string}>} feeds `label` names the feed
 *   in the error ("locations download failed: 503").
 * @param {{accept: string, maxBytes: number, timeoutMs: number,
 *   parse?: (text: string) => unknown}} options
 * @returns {Promise<unknown[]>} The parsed bodies (texts without `parse`), in
 *   feed order.
 */
export async function readCatalogsTogether(
  feeds,
  { accept, maxBytes, timeoutMs, parse = (text) => text },
) {
  const sibling = new AbortController();
  const signal = AbortSignal.any([
    sibling.signal,
    AbortSignal.timeout(timeoutMs),
  ]);
  return Promise.all(
    feeds.map(async ({ url, label }) => {
      let response;
      try {
        response = await fetch(url, {
          headers: { Accept: accept },
          redirect: 'manual',
          signal,
        });
        signal.throwIfAborted();
        if (!response.ok) {
          throw new Error(
            response.status >= 300 && response.status < 400
              ? `${label} catalog redirected; redirects are not followed`
              : `${label} download failed: ${response.status}`,
          );
        }
        return parse(await readResponseTextCapped(response, maxBytes, signal));
      } catch (error) {
        sibling.abort();
        await response?.body?.cancel().catch(() => {});
        throw error;
      }
    }),
  );
}
