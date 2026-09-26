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

import { resolveGoogleServerKey } from '../../../scripts/google-server-key.mjs';

/**
 * Optional Google place context is an empty capability when no key is present,
 * not a server outage. Returning 200 keeps a deliberately keyless session out
 * of the browser error console while preserving an explicit configured flag.
 */
export function keylessGooglePlacesResponse(apiKey) {
  if (String(apiKey ?? '').trim()) return null;
  return {
    statusCode: 200,
    payload: { configured: false, error: null, places: [] },
  };
}

/**
 * Google API key for the SERVER-SIDE calls (Places nearby/text search, the
 * CCTV Street View fallback). These never reach the browser, so this key can
 * be restricted by server IP and scoped to Places API + Street View Static
 * API — while GOOGLE_MAPS_API_KEY stays referrer-restricted to Map Tiles +
 * Geocoding for the browser (#33). Splitting them is opt-in: unset, this
 * falls back to the shared browser key and nothing changes.
 */
export function googleServerApiKey() {
  return resolveGoogleServerKey(process.env);
}
