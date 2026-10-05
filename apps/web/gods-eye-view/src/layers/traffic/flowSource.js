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

/** Own one bounded decoded flow cache; every request still passes the server tile budget. */
export function createFlowTileSource({
  fetchImpl = (...args) => globalThis.fetch(...args),
} = {}) {
  const tiles = createVectorTileSource({
    template: '/api/tomtom/flow/{z}/{x}/{y}.pbf',
    allowedOrigin: 'http://localhost',
    decode: (bytes, z, x, y) =>
      decodeFlowTile(bytes, z, x, y, { strict: true })
        .filter(isDrivableFlowSegment)
        .flatMap((segment) =>
          clipTileLine(segment.coords, tileToBBox(z, x, y)).map((coords) => ({
            ...segment,
            coords,
          })),
        ),
    fetchImpl,
    ttlMs: 120_000,
    maxTiles: 16,
  });
  let partial = false;
  /**
   * Flow segments for bounds, with whether any covering tile failed to load
   * for this request.
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
    return { segments, partial: result.partial === true };
  }
  return {
    fetchFlowDetail,
    async fetchFlowForBounds(bounds, options) {
      return (await fetchFlowDetail(bounds, options)).segments;
    },
    getFlowSessionStats: () => ({ ...tiles.getStats(), partial }),
    resetFlowTileCache: () => tiles.clear(),
  };
}
