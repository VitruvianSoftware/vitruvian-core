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

import { readResponseJsonCapped } from '../../sources/httpBody.js';
import { normalizeShipwreckSnapshot } from './records.js';

const age = (value) => (Number.isFinite(value) && value >= 0 ? value : null);

/** Same-origin source for the proxy's EMODnet + Wikidata shipwreck snapshot. */
export function createShipwrecksSource({
  fetchImpl = (...args) => globalThis.fetch(...args),
} = {}) {
  return {
    async getSnapshot({ signal } = {}) {
      signal?.throwIfAborted();
      const response = await fetchImpl('/api/shipwrecks', { signal });
      if (!response.ok)
        throw new Error(`Shipwrecks unavailable (HTTP ${response.status})`);
      const payload = await readResponseJsonCapped(
        response,
        16 * 1024 * 1024,
        signal,
      );
      signal?.throwIfAborted();
      const records = normalizeShipwreckSnapshot(payload);
      if (!records) throw new Error('Malformed shipwrecks response');
      return {
        records,
        fetchedAt: Number.isFinite(payload.fetchedAt)
          ? payload.fetchedAt
          : null,
        stale: payload.stale === true,
        // Changes whenever either source's data does; null from an older proxy.
        version: typeof payload.version === 'string' ? payload.version : null,
        // Each source's age on the proxy's clock (null when unknown).
        ages: {
          emodnet: age(payload.ages?.emodnet),
          wikidata: age(payload.ages?.wikidata),
        },
        maxAgeMs: age(payload.maxAgeMs),
        sources: {
          emodnet: payload.sources?.emodnet !== false,
          wikidata: payload.sources?.wikidata !== false,
        },
      };
    },
  };
}
