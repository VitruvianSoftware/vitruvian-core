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

const contract = (layers, methods) =>
  Object.freeze({
    layers: Object.freeze(layers),
    methods: Object.freeze(methods),
  });

/** Acquisition contracts and their consumers; records remain family-specific. */
export const CATALOG_SOURCE_CONTRACTS = Object.freeze({
  directions: contract(['directions'], ['getRoute']),
  'recent-imagery': contract(
    ['recent-imagery'],
    ['searchHls', 'getThumbnail', 'getTileTemplate'],
  ),
  flights: contract(['flights'], ['getSnapshot']),
  military: contract(['military'], ['getSnapshot']),
  vessels: contract(['ais-live-vessels'], ['getSnapshot']),
  cctv: contract(
    ['cctv'],
    ['getCatalog', 'getHealth', 'getFrameUrl', 'getMediaUrl'],
  ),
  radio: contract(['radio'], ['getDirectory', 'recordClick']),
  traffic: contract(
    ['traffic'],
    [
      'requestRoads',
      'getStatus',
      'fetchFlowForBounds',
      'getFlowSessionStats',
      'resetFlowTileCache',
    ],
  ),
  bikeshare: contract(['bikeshare'], ['getStations']),
  installations: contract(
    ['military-installations'],
    ['getMappedSites', 'searchNearby'],
  ),
  satellites: contract(['satellites'], ['readGroup']),
  launches: contract(['rocket-launches'], ['getLaunches', 'getActiveTle']),
  alpr: contract(['alpr-cameras'], ['fetch']),
  firms: contract(['local-firms'], ['getSnapshot']),
  wind: contract(['wind'], ['getSnapshot']),
  weather: contract(
    ['weather-radar', 'weather-satellite', 'weather-lightning'],
    ['getSnapshot'],
  ),
  cyclones: contract(['weather-cyclones'], ['getSnapshot']),
  earthquakes: contract(['earthquakes'], ['getSnapshot']),
  'fire-perimeters': contract(['fire-perimeters'], ['getSnapshot']),
  'air-quality': contract(['air-quality'], ['getSnapshot']),
  'gnss-integrity': contract(['gnss-integrity'], ['getSnapshot']),
  cables: contract(['telegeography-submarine-cables'], ['fetch']),
  transit: contract(['transit'], ['requestSnapshot', 'getHistory']),
});

/** An omitted provider is unavailable, never an authoritative empty dataset. */
class SourceUnavailableError extends Error {
  constructor(name) {
    super(`Data source not configured: ${name}`);
    this.name = 'SourceUnavailableError';
    this.code = 'unavailable';
    this.unavailable = true;
    this.retryable = false;
  }
}

/** Validate supplied contracts and keep omitted sources inert during construction. */
export function resolveCatalogSources(supplied = {}) {
  if (!supplied || typeof supplied !== 'object' || Array.isArray(supplied))
    throw new TypeError('Catalog sources must be an object');
  const sources = { ...supplied };
  const missing = new Set();
  for (const [name, { methods }] of Object.entries(CATALOG_SOURCE_CONTRACTS)) {
    const source = sources[name];
    if (source == null) {
      missing.add(name);
      const unavailable = () => {
        throw new SourceUnavailableError(name);
      };
      sources[name] = Object.freeze({
        label: name,
        ...Object.fromEntries(methods.map((method) => [method, unavailable])),
      });
    } else if (methods.some((method) => typeof source[method] !== 'function')) {
      throw new TypeError(`Invalid catalog source: ${name}`);
    }
  }
  return {
    sources,
    isConfigured: (name) => !missing.has(name),
    createAvailabilityLookup(layers) {
      const byId = new Map(layers.map((layer) => [layer.id, layer]));
      const availability = new Map();
      for (const [name, { layers: ids }] of Object.entries(
        CATALOG_SOURCE_CONTRACTS,
      )) {
        for (const id of ids) {
          const layer = byId.get(id);
          if (!layer) throw new Error(`Missing source consumer: ${id}`);
          availability.set(
            id,
            Object.freeze({
              available: !missing.has(name),
              source: name,
              reason: missing.has(name)
                ? `${layer.name || id}: data source not configured`
                : null,
            }),
          );
        }
      }
      return (id) =>
        availability.get(id) ?? byId.get(id)?.getSourceAvailability?.();
    },
  };
}
