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
  createNominatimClient,
  normalizeNominatimResult,
  normalizeNominatimReverse,
} from '../sources/nominatim.js';
import { normalizeGooglePlace } from './google.js';
export {
  createNominatimClient,
  normalizeNominatimResult,
  normalizeNominatimReverse,
};

/** Forward and reverse operations only; feature queries and routing are separate. */
export function createNominatimProvider(options = {}) {
  const client = createNominatimClient(options);
  return {
    attribution: {
      geocode: 'OpenStreetMap / Nominatim',
      reverseGeocode: 'OpenStreetMap / Nominatim',
    },
    ...(client.search
      ? {
          async geocode(query, options = {}) {
            try {
              const rows = await client.search(query, options);
              return {
                place: rows.length
                  ? normalizeGooglePlace(normalizeNominatimResult(rows[0]))
                  : null,
                answered: true,
              };
            } catch {
              options.signal?.throwIfAborted();
              return { place: null, answered: false };
            }
          },
        }
      : {}),
    ...(client.reverse
      ? {
          async reverseGeocode(latitude, longitude, options) {
            const row = await client.reverse(latitude, longitude, options);
            return row ? normalizeNominatimReverse(row) : null;
          },
        }
      : {}),
  };
}
