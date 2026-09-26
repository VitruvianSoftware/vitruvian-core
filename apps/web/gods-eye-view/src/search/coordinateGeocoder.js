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

import { parseCoordinateQuery } from './coordinateParser.js';

/** Half-width of the box a bare coordinate is framed with, in degrees. */
const COORDINATE_HALF_SPAN_DEG = 0.015;

/** Keep a generated box inside the poles and inside the dateline. */
function boundedBox(lat, lon, halfSpan) {
  const wrap = (value) => {
    const wrapped = ((((value + 180) % 360) + 360) % 360) - 180;
    return wrapped === -180 ? 180 : wrapped;
  };
  return {
    southwest: {
      lat: Math.max(-90, lat - halfSpan),
      lng: wrap(lon - halfSpan),
    },
    northeast: {
      lat: Math.min(90, lat + halfSpan),
      lng: wrap(lon + halfSpan),
    },
  };
}

/**
 * Answer a decimal-degree query without asking anyone.
 *
 * It sits ahead of the network geocoders, so a coordinate costs no request and
 * works with no key. Anything that is not exactly a coordinate is passed on
 * untouched, and `answered: true` on a decline means only that this provider
 * had nothing to say — it is not a verdict on the query.
 */
export function createCoordinateGeocoder() {
  return {
    async geocode(query, { signal } = {}) {
      signal?.throwIfAborted();
      const parsed = parseCoordinateQuery(query);
      if (!parsed) return { place: null, answered: true };
      return {
        place: {
          lat: parsed.lat,
          lng: parsed.lon,
          name: parsed.label,
          label: parsed.label,
          types: ['coordinate'],
          // The point is the answer; nothing nearby can improve on it.
          exact: true,
          viewport: boundedBox(
            parsed.lat,
            parsed.lon,
            COORDINATE_HALF_SPAN_DEG,
          ),
        },
        answered: true,
      };
    },
  };
}
