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

import { createEarthquakesLayer } from '../../layers/earthquakes/index.js';
import { overlayHost } from './overlayHost.js';
import { inputFor } from '../../input/dispatcher.js';
import * as picking from '../../data/pickRegistry.js';
import * as context from '../../data/contextStore.js';
import { isPointerFree } from '../../data/inputOwnership.js';
import { requestWorldFocus } from '../../worldFocus.js';
import { createEarthquakeRipples } from './earthquakeRipples.js';
import { heightsOf } from '../../queries/heights.js';
import { formatDate, formatNumber, t } from '../../i18n/index.js';

const EVENT_TIME = Object.freeze({
  day: 'numeric',
  month: 'short',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  timeZone: 'UTC',
  timeZoneName: 'short',
});

/** The clicked quake's card text, in the page's language. */
export const earthquakeCardText = Object.freeze({
  t,
  formatTime: (time) => formatDate(time, EVENT_TIME),
  formatDepth: (km) => formatNumber(km, { maximumFractionDigits: 1 }),
});

/**
 * Wire earthquake observations to the application overlay host, and its
 * discs to the globe's clicks: a clicked quake shows its detail card.
 */
export function createApplicationEarthquakes(options) {
  return createEarthquakesLayer({
    overlayHost,
    input: (viewer) => inputFor(viewer),
    picking,
    context,
    pointer: { isPointerFree },
    openExternal: (url) => window.open(url, '_blank', 'noopener,noreferrer'),
    focus: { requestWorldFocus },
    ripples: createEarthquakeRipples(),
    // The loaded ground (terrain or tiles) the clamped disc is draped on.
    groundHeight: (viewer, lon, lat) =>
      viewer ? heightsOf(viewer).now({ lon, lat }) : null,
    text: earthquakeCardText,
    ...options,
  });
}
