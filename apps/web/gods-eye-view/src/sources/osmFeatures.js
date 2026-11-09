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
 * Browser client for `/api/osm/features`: one curated preset inside a box,
 * as a count or as features. The server writes and bounds the Overpass
 * query and answers only when an operator configured Overpass; this only
 * names the preset, box, mode and limit.
 * @module sources/osmFeatures
 */

/**
 * @param {{fetchImpl?: typeof fetch, endpoint?: string}} [options]
 * @returns {(request: {preset: string, bbox: number[], mode?: 'count'|'features', limit?: number}, options?: {signal?: AbortSignal}) => Promise<object>}
 */
export function createOsmFeatureSource({
  fetchImpl = (...args) => globalThis.fetch(...args),
  endpoint = '/api/osm/features',
} = {}) {
  return async function searchOsmFeatures(
    { preset, bbox, mode = 'features', limit },
    { signal } = {},
  ) {
    const params = new URLSearchParams({
      preset,
      bbox: bbox.map((v) => Number(v).toFixed(5)).join(','),
      mode,
    });
    if (Number.isFinite(limit)) params.set('limit', String(limit));
    let response;
    try {
      response = await fetchImpl(`${endpoint}?${params}`, { signal });
    } catch (error) {
      if (signal?.aborted) throw error;
      return {
        ok: false,
        status: 0,
        error: 'OpenStreetMap search is unreachable.',
      };
    }
    let body = null;
    try {
      body = await response.json();
    } catch {
      body = null;
    }
    if (!response.ok)
      return {
        ok: false,
        status: response.status,
        code: body?.code || null,
        error:
          body?.error || `OpenStreetMap search failed (${response.status}).`,
      };
    // A garbled success (a proxy's error page) is a failure, not zero places.
    if (!body || typeof body !== 'object')
      return {
        ok: false,
        status: response.status,
        code: null,
        error: 'OpenStreetMap search returned an unreadable answer.',
      };
    return { ok: true, ...body };
  };
}
