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

import {
  OVERPASS_URL,
  MAX_VIEWPORT_DEGREES,
  QUERY_SNAP_DEGREES,
  QUERY_LIMIT,
} from './policy.js';
import { buildOverpassQuery, normalizeAlprNode } from './records.js';
/** Construct the bounded OSM request adapter without starting a request. */
export function createOverpassAlprSource({
  fetchImpl = (...args) => globalThis.fetch(...args),
} = {}) {
  async function fetchAlprNodes(box, signal) {
    signal?.throwIfAborted();
    if (
      !box ||
      ![box.south, box.west, box.north, box.east].every(Number.isFinite) ||
      box.south < -90 ||
      box.north > 90 ||
      box.west < -180 ||
      box.east > 180 ||
      box.north <= box.south ||
      box.east <= box.west ||
      box.north - box.south >
        MAX_VIEWPORT_DEGREES + 2 * QUERY_SNAP_DEGREES + 1e-9 ||
      box.east - box.west > MAX_VIEWPORT_DEGREES + 2 * QUERY_SNAP_DEGREES + 1e-9
    ) {
      throw new TypeError('ALPR requires a bounded city viewport');
    }
    const query = buildOverpassQuery(box.south, box.west, box.north, box.east);
    const response = await fetchImpl(OVERPASS_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `data=${encodeURIComponent(query)}`,
      signal,
    });
    if (!response.ok) {
      try {
        await response.body?.cancel();
      } catch {
        /* already closed */
      }
      const message =
        response.status === 429
          ? 'Overpass rate-limited'
          : response.status === 504
            ? 'Overpass timed out'
            : 'Overpass temporarily unavailable';
      throw new Error(message);
    }
    const stale = response.headers.get('x-overpass-cache') === 'STALE';
    const payload = await response.json();
    signal?.throwIfAborted();
    // The shared proxy already rejects query errors. Validate here too so a
    // malformed or partial response never becomes an authoritative empty map.
    if (!Array.isArray(payload?.elements) || payload.remark) {
      throw new Error('Overpass returned an incomplete camera response');
    }
    return {
      records: [
        ...new Map(
          payload.elements
            .slice(0, QUERY_LIMIT)
            .map(normalizeAlprNode)
            .filter(Boolean)
            .map((record) => [record.id, record]),
        ).values(),
      ],
      stale,
      saturated: payload.elements.length >= QUERY_LIMIT,
    };
  }
  return {
    fetch: fetchAlprNodes,
    label: 'OpenStreetMap · community mapped',
    attribution: {
      name: 'OpenStreetMap',
      description: 'OpenStreetMap contributors (ODbL 1.0; community mapped)',
      text: '© OpenStreetMap',
      href: 'https://www.openstreetmap.org/copyright',
    },
  };
}

export { buildOverpassQuery } from './records.js';
