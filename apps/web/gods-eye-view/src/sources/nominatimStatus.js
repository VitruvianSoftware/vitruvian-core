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
 * Whether the app's server has a Nominatim endpoint configured, asked once per
 * page from `/api/geocode/status` (like `/api/overpass/status`). When it says
 * no, callers skip lookups the server could only refuse, so a default install
 * never asks and never logs a failed request. An older server without the
 * probe, a failed or timed-out probe and a malformed answer leave the
 * capability unknown (`null`): lookups then go to the server as before, and
 * the probe is retried after a short backoff.
 *
 * @returns {() => Promise<boolean|null>}
 */
export function createNominatimStatus({
  fetchImpl = (...args) => globalThis.fetch(...args),
  url = '/api/geocode/status',
  timeoutMs = 3000,
  retryMs = 30_000,
  now = Date.now,
} = {}) {
  let decision = null;
  let retryAt = 0;
  return function configured() {
    if (decision) return decision;
    if (now() < retryAt) return Promise.resolve(null);
    decision = (async () => {
      try {
        const response = await fetchImpl(url, {
          signal: AbortSignal.timeout(timeoutMs),
        });
        const body = response.ok ? await response.json() : null;
        if (typeof body?.configured === 'boolean') return body.configured;
      } catch {
        // Unknown capability: ask the server as before.
      }
      decision = null;
      retryAt = now() + retryMs;
      return null;
    })();
    return decision;
  };
}
