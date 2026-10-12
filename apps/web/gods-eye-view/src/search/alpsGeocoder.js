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

import { findNaturalRegion, pointInRing } from '../data/naturalEarthRegions.js';

/**
 * The unqualified Alps ask names the European range, not a same-named peak
 * or local POI. Keep this correction exact and Alps-only: other ranges and
 * geographic qualifiers retain the caller's configured geocoder semantics.
 */
export function createAlpsGeocoder({ lookupRegion = findNaturalRegion } = {}) {
  return {
    async geocode(query, { signal } = {}) {
      signal?.throwIfAborted();
      const name = String(query ?? '')
        .trim()
        .replace(/\s+/g, ' ');
      if (!/^(?:the )?alps(?: mountains)?$/i.test(name))
        return { place: null, answered: true };

      const region = await lookupRegion('Alps');
      signal?.throwIfAborted();
      if (
        region?.name !== 'Alps' ||
        region.kind !== 'natural' ||
        !Array.isArray(region.polygons) ||
        region.polygons.length === 0 ||
        !region.polygons.every(
          (ring) =>
            Array.isArray(ring) &&
            ring.length >= 3 &&
            ring.every(
              (point) =>
                Array.isArray(point) &&
                point.length === 2 &&
                point.every(Number.isFinite) &&
                Math.abs(point[0]) <= 180 &&
                Math.abs(point[1]) <= 90,
            ),
        )
      )
        throw new Error('Bundled Alps geometry unavailable');
      const vertices = region.polygons.flat();
      const west = Math.min(...vertices.map(([lon]) => lon));
      const east = Math.max(...vertices.map(([lon]) => lon));
      const south = Math.min(...vertices.map(([, lat]) => lat));
      const north = Math.max(...vertices.map(([, lat]) => lat));
      const lat = (south + north) / 2;
      const lng = (west + east) / 2;
      if (
        ![west, east, south, north, lat, lng].every(Number.isFinite) ||
        !region.polygons.some((ring) => pointInRing(ring, lat, lng))
      ) {
        // A broken pack is not permission to cache an unrelated network peak
        // as the canonical range. Existing search error/retry handling owns it.
        throw new Error('Bundled Alps geometry unavailable');
      }
      return {
        answered: true,
        place: {
          lat,
          lng,
          name: region.name,
          label: region.name,
          types: ['natural_feature'],
          exact: true,
          viewport: {
            southwest: { lat: south, lng: west },
            northeast: { lat: north, lng: east },
          },
        },
      };
    },
  };
}
