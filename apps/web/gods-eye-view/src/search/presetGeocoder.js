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

/** Half-width of the box a bundled landmark is framed with, in degrees. */
const LANDMARK_HALF_SPAN_DEG = 0.005;

/** Fold a name to the form an exact comparison uses: case, spacing, punctuation. */
function normalizeName(value) {
  return String(value || '')
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

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
    northeast: { lat: Math.min(90, lat + halfSpan), lng: wrap(lon + halfSpan) },
  };
}

/**
 * Build the exact-match index once, so a search is a lookup rather than a scan.
 *
 * Only exact names match. A bundled preset that answered a partial or fuzzy
 * query would shadow the real geocoders for everything that merely resembles a
 * bundled name, and the operator would have no way to reach the place they
 * meant.
 */
function indexPresets(presets) {
  const byName = new Map();
  const remember = (key, place) => {
    const name = normalizeName(key);
    if (name && !byName.has(name)) byName.set(name, place);
  };

  for (const [cityId, city] of Object.entries(presets || {})) {
    const anchor = city?.pois?.[0];
    const bounds = city?.viewBounds;
    const lat = Number(anchor?.lat);
    const lon = Number(anchor?.lon);
    if (Number.isFinite(lat) && Number.isFinite(lon)) {
      const place = {
        lat,
        lng: lon,
        name: city.name,
        label: city.name,
        types: ['locality'],
        exact: true,
        viewport:
          Number.isFinite(bounds?.southwest?.lat) &&
          Number.isFinite(bounds?.southwest?.lng) &&
          Number.isFinite(bounds?.northeast?.lat) &&
          Number.isFinite(bounds?.northeast?.lng)
            ? {
                southwest: {
                  lat: bounds.southwest.lat,
                  lng: bounds.southwest.lng,
                },
                northeast: {
                  lat: bounds.northeast.lat,
                  lng: bounds.northeast.lng,
                },
              }
            : boundedBox(lat, lon, 0.1),
      };
      remember(cityId, place);
      remember(city.name, place);
    }

    for (const poi of city?.pois || []) {
      const poiLat = Number(poi?.lat);
      const poiLon = Number(poi?.lon);
      if (!Number.isFinite(poiLat) || !Number.isFinite(poiLon)) continue;
      remember(poi.name, {
        lat: poiLat,
        lng: poiLon,
        name: poi.name,
        label: city?.name ? `${poi.name}, ${city.name}` : poi.name,
        types: ['point_of_interest'],
        exact: true,
        viewport: boundedBox(poiLat, poiLon, LANDMARK_HALF_SPAN_DEG),
      });
    }
  }
  return byName;
}

/**
 * Answer the bundled city and landmark names without asking anyone.
 *
 * Matching is exact on the city id, the city name, or a landmark name; anything
 * else is passed on to the network geocoders untouched.
 */
export function createPresetGeocoder({ presets = {} } = {}) {
  const byName = indexPresets(presets);
  return {
    async geocode(query, { signal } = {}) {
      signal?.throwIfAborted();
      const place = byName.get(normalizeName(query));
      return place
        ? { place, answered: true }
        : { place: null, answered: true };
    },
  };
}
