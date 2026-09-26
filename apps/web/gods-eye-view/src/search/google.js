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

/** Normalize a Google forward-geocode result without leaking its address shape. */
export function normalizeGooglePlace(result) {
  const lat = result?.geometry?.location?.lat;
  const lng = result?.geometry?.location?.lng;
  if (
    !Number.isFinite(lat) ||
    !Number.isFinite(lng) ||
    Math.abs(lat) > 90 ||
    Math.abs(lng) > 180
  )
    return null;
  const types = Array.isArray(result.types) ? result.types : [];
  const resultTypes = new Set(types.map((type) => String(type).toLowerCase()));
  const components = Array.isArray(result.address_components)
    ? result.address_components
    : [];
  // Address-only landmark results must retain the requested landmark identity.
  const canonical = components.find(
    (component) =>
      Array.isArray(component.types) &&
      component.types.some(
        (type) =>
          type !== 'political' && resultTypes.has(String(type).toLowerCase()),
      ),
  );
  return {
    lat,
    lng,
    name: canonical?.long_name || '',
    label: result.formatted_address || '',
    types,
    viewport: result.geometry.bounds || result.geometry.viewport || null,
  };
}

/** Construct Google geocoding with caller-owned transport and key selection. */
export function createGoogleGeocoder({ request }) {
  return {
    async geocode(query, { bias = null, signal } = {}) {
      signal?.throwIfAborted();
      try {
        const response = await request(query, { bias, signal });
        signal?.throwIfAborted();
        // An unconfigured provider did not contribute a negative verdict.
        if (!response) return { place: null, answered: true };
        if (response.ok === false) return { place: null, answered: false };
        const data = await response.json();
        signal?.throwIfAborted();
        if (
          data?.status === 'ZERO_RESULTS' &&
          Array.isArray(data.results) &&
          data.results.length === 0
        )
          return { place: null, answered: true };
        const place =
          data?.status === 'OK'
            ? normalizeGooglePlace(data.results?.[0])
            : null;
        return { place, answered: Boolean(place) };
      } catch {
        signal?.throwIfAborted();
        return { place: null, answered: false };
      }
    },
  };
}
