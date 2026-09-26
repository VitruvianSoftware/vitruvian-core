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

/** WGS84 coordinate pair in longitude/latitude order. */
export function validCoordinate(pair) {
  return (
    Array.isArray(pair) &&
    pair.length >= 2 &&
    Number.isFinite(pair[0]) &&
    Math.abs(pair[0]) <= 180 &&
    Number.isFinite(pair[1]) &&
    Math.abs(pair[1]) <= 90
  );
}

/** Compose independent geospatial operations; unsupported operations stay explicit. */
export function createGeospatialServices({
  providers = {},
  signal: lifetime,
} = {}) {
  const capabilities = Object.freeze(
    Object.fromEntries(
      ['reverseGeocode', 'textSearch', 'nearby', 'route'].map((name) => [
        name,
        typeof providers[name] === 'function',
      ]),
    ),
  );
  async function invoke(name, args, options = {}) {
    const signal = AbortSignal.any(
      [
        lifetime,
        options.signal,
        AbortSignal.timeout(name === 'route' ? 13_000 : 5_000),
      ].filter(Boolean),
    );
    signal.throwIfAborted();
    if (!capabilities[name]) return null;
    const result = await providers[name](...args, { ...options, signal });
    signal.throwIfAborted();
    return result;
  }
  return {
    capabilities,
    signal: lifetime,
    attribution: Object.freeze({ ...providers.attribution }),
    reverseGeocode(latitude, longitude, options) {
      if (!validCoordinate([longitude, latitude])) return Promise.resolve(null);
      return invoke('reverseGeocode', [latitude, longitude], options);
    },
    async textSearch(query, point, options) {
      if (
        !String(query || '').trim() ||
        !validCoordinate([point?.longitude, point?.latitude])
      )
        return [];
      return (
        (await invoke('textSearch', [String(query).trim(), point], options)) ||
        []
      );
    },
    async nearby(point, options) {
      if (!validCoordinate([point?.longitude, point?.latitude])) return [];
      return (await invoke('nearby', [point], options)) || [];
    },
    async route(coordinates, profile = 'foot', options) {
      if (
        !Array.isArray(coordinates) ||
        coordinates.length < 2 ||
        coordinates.length > 12 ||
        !coordinates.every(validCoordinate)
      )
        return null;
      const profiles = providers.routeProfiles || ['foot', 'car', 'bike'];
      if (!profiles.includes(profile)) return null;
      const result = await invoke('route', [coordinates, profile], options);
      if (
        !result ||
        !Array.isArray(result.geometry) ||
        result.geometry.length < 2 ||
        !result.geometry.every(validCoordinate) ||
        !Number.isFinite(result.distanceM) ||
        result.distanceM < 0 ||
        !Number.isFinite(result.durationS) ||
        result.durationS < 0
      )
        return null;
      return { ...result, ok: true, profile };
    },
  };
}
