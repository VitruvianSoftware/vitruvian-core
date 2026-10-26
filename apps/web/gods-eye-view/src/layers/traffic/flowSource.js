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

import { isDrivableFlowSegment } from './roadModes.js';
import { createVectorTileSource } from '../../sources/vectorTiles.js';
import { clipTileLine } from '../../sources/openFreeMap.js';
import { tileToBBox } from '../../data/tomtomTiles.js';
import { decodeFlowTile } from './flowDecode.js';

const FLOW_TILE_PATH = (z, x, y) => `/api/tomtom/flow/${z}/${x}/${y}.pbf`;

/**
 * Whether the proxy answered a tile from its cache past the refresh window
 * (STALE-BUDGET once the daily budget is spent, STALE-ERROR when TomTom
 * fails), and when the proxy fetched it.
 */
function tileFreshness(response) {
  const status = response.headers?.get?.('x-tomtom-cache') || '';
  const fetchedAt = Number(response.headers?.get?.('x-tomtom-fetched-at'));
  return {
    stale: status.startsWith('STALE'),
    fetchedAt: fetchedAt > 0 ? fetchedAt : null,
  };
}

/** Own one bounded decoded flow cache; every request still passes the server tile budget. */
export function createFlowTileSource({
  fetchImpl = (...args) => globalThis.fetch(...args),
} = {}) {
  // Freshness travels in response headers, but the tile cache keeps only
  // decoded segments: hold each response's freshness until its tile decodes,
  // then key it by the decoded tile, which the cache hands back on a hit.
  const pending = new Map();
  const freshness = new WeakMap();
  const tiles = createVectorTileSource({
    template: FLOW_TILE_PATH('{z}', '{x}', '{y}'),
    allowedOrigin: 'http://localhost',
    decode: (bytes, z, x, y) => {
      // Take the mark before decoding, so a tile that fails to decode
      // leaves nothing behind.
      const path = FLOW_TILE_PATH(z, x, y);
      const entry = pending.get(path);
      const mark = entry?.mark;
      entry?.release();
      const segments = decodeFlowTile(bytes, z, x, y, { strict: true })
        .filter(isDrivableFlowSegment)
        .flatMap((segment) =>
          clipTileLine(segment.coords, tileToBBox(z, x, y)).map((coords) => ({
            ...segment,
            coords,
          })),
        );
      if (mark) freshness.set(segments, mark);
      return segments;
    },
    fetchImpl: async (url, init) => {
      const response = await fetchImpl(url, init);
      if (response.ok && !init.signal.aborted) {
        const path = String(url);
        const entry = {
          mark: tileFreshness(response),
          release() {
            if (pending.get(path) === entry) pending.delete(path);
            init.signal.removeEventListener('abort', entry.release);
          },
        };
        pending.get(path)?.release();
        pending.set(path, entry);
        // The vector source aborts this signal for failed/cancelled body reads,
        // including size-limit failures that never reach decode.
        init.signal.addEventListener('abort', entry.release, { once: true });
      }
      return response;
    },
    ttlMs: 120_000,
    maxTiles: 16,
  });
  let partial = false;
  /**
   * Flow segments for bounds, with whether any covering tile failed to load
   * for this request, whether any came from the proxy's stale cache, and when
   * the oldest tile was fetched.
   */
  async function fetchFlowDetail(bounds, { signal, zoom = 12 } = {}) {
    const result = await tiles.fetchBounds(bounds, {
      zoom,
      signal,
      tiles: bounds.coverage?.coarse,
    });
    partial = result.partial;
    const segments = bounds.coverage
      ? result.tiles.flat()
      : result.tiles.flat().flatMap((segment) =>
          clipTileLine(segment.coords, bounds).map((coords) => ({
            ...segment,
            coords,
          })),
        );
    const marks = result.tiles.map((tile) => freshness.get(tile) || {});
    const times = marks
      .map((mark) => mark.fetchedAt)
      .filter((at) => Number.isFinite(at));
    return {
      segments,
      partial: result.partial === true,
      stale: marks.some((mark) => mark.stale === true),
      oldestTileAt: times.length ? Math.min(...times) : null,
    };
  }
  return {
    fetchFlowDetail,
    async fetchFlowForBounds(bounds, options) {
      return (await fetchFlowDetail(bounds, options)).segments;
    },
    getFlowSessionStats: () => ({ ...tiles.getStats(), partial }),
    resetFlowTileCache: () => {
      for (const entry of pending.values()) entry.release();
      tiles.clear();
    },
  };
}
