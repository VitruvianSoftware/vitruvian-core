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

import { createOpenFreeMapSource } from '../sources/openFreeMap.js';
import {
  createFlightSource,
  createMilitarySource,
  createVesselSource,
} from '../sources/live/standalone.js';
import { createCctvSource } from '../layers/cctv/source.js';
import { createRadioSource } from '../layers/radio/source.js';
import { createTransitSource } from '../layers/transit/source.js';
import { createTrafficSource } from '../layers/traffic/source.js';
import { createBikeshareSource } from '../layers/bikeshare/source.js';
import { createInstallationSource } from '../layers/installations/source.js';
import { createSatelliteSource } from '../layers/satellites/source.js';
import { createLaunchSource } from '../layers/launches/source.js';
import { createAlprTileSource } from '../layers/alpr/source.js';
import { createWeatherSource } from '../layers/weather/source.js';
import { createCycloneSource } from '../layers/cyclones/source.js';
import { createWindSource } from '../layers/wind/source.js';
import { createFirmsSource } from '../layers/firms/source.js';
import { createMapillarySource } from '../layers/streetLevel/providers/mapillary/source.js';
import { createReferenceSources } from '../sources/reference.js';
export { createReferenceSources as createStandaloneReferenceSources } from '../sources/reference.js';

/** Select standalone providers without starting their acquisition. */
export function createStandaloneLayerSources() {
  const mapTiles = createOpenFreeMapSource();
  return {
    ...createReferenceSources(),
    flights: createFlightSource(),
    military: createMilitarySource(),
    vessels: createVesselSource({
      apiUrl: import.meta.env?.VITE_AIS_LIVE_API_URL || '/api/vessels',
      // Resolved against the document's address, which a panel host may
      // serve from its own scheme.
      origin: () => globalThis.document?.baseURI ?? 'http://localhost',
    }),
    cctv: createCctvSource(),
    radio: createRadioSource(),
    traffic: createTrafficSource({ mapTiles }),
    transit: createTransitSource(),
    bikeshare: createBikeshareSource(),
    installations: createInstallationSource({ mapTiles }),
    satellites: createSatelliteSource(),
    launches: createLaunchSource(),
    alpr: createAlprTileSource(),
    firms: createFirmsSource(),
    wind: createWindSource(),
    weather: createWeatherSource(),
    cyclones: createCycloneSource(),
    mapillary: createMapillarySource({
      token: import.meta.env?.MAPILLARY_CLIENT_TOKEN || '',
    }),
  };
}
