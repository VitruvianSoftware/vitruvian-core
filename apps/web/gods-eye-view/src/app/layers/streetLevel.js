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

import { createStreetLevelLayer } from '../../layers/streetLevel/index.js';
import { createMapillaryProvider } from '../../layers/streetLevel/providers/mapillary/index.js';
import { createGoogleProvider } from '../../layers/streetLevel/providers/google/index.js';
import { createKartaViewProvider } from '../../layers/streetLevel/providers/kartaview/index.js';
import { createPanoramaxProvider } from '../../layers/streetLevel/providers/panoramax/index.js';
import * as sprites from '../../data/spriteOrder.js';
import * as picking from '../../data/pickRegistry.js';
import * as input from '../../data/inputOwnership.js';
import * as scenePick from '../../data/scenePick.js';
import * as render from '../../renderGovernor.js';

/** The browser Maps key the scene was started with (src/app/scene.js). */
const googleApiKey = () => globalThis.window?.__GOOGLE_MAPS_API_KEY__ || null;

/**
 * Mapillary, Google Street View, KartaView and Panoramax, once the Mapillary
 * source is supplied; else none.
 */
function defaultProviders(sources) {
  if (sources.mapillary == null) return [];
  return [
    createMapillaryProvider({ source: sources.mapillary }),
    createGoogleProvider({ getApiKey: googleApiKey }),
    createKartaViewProvider(),
    createPanoramaxProvider(),
  ];
}

/**
 * Inject providers, or use the defaults. An explicit provider list replaces
 * them; an unused sources.mapillary is neither constructed nor validated,
 * including when the list is empty.
 */
export function createApplicationStreetLevel({
  sources = {},
  providers = defaultProviders(sources),
}) {
  return createStreetLevelLayer({
    providers,
    services: { sprites, picking, input, scenePick, render },
  });
}
