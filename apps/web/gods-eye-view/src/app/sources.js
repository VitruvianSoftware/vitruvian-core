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

import flights from '../data/flights.js';
import military from '../data/militaryFlights.js';
import vessels from '../data/aisLiveVessels.js';
import { configureAlprSource } from '../data/alprCameras.js';
import { configureCctvSource } from '../data/cctv.js';
import { configureRadioSource } from '../data/radio.js';
import { configureTrafficSource } from '../data/traffic.js';
import { configureBikeshareSource } from '../data/bikeshare.js';
import { configureInstallationSource } from '../data/militaryInstallations.js';
import { configureSatelliteSource } from '../data/satellites.js';
import { configureLaunchSource } from '../data/rocketLaunches.js';
import { configureFirmsSource } from '../data/firmsHeatmap.js';
import { configureWindSource } from '../data/wind.js';
import { configureMilitaryRegistrySource } from '../data/militaryRegistry.js';
const configure = {
  alpr: configureAlprSource,
  cctv: configureCctvSource,
  radio: configureRadioSource,
  traffic: configureTrafficSource,
  bikeshare: configureBikeshareSource,
  installations: configureInstallationSource,
  satellites: configureSatelliteSource,
  launches: configureLaunchSource,
  firms: configureFirmsSource,
  wind: configureWindSource,
};
/** Configure sources before any registration or state restoration starts. */
export function configureApplicationSources({
  layers = {},
  live = {},
  signal,
  defer,
}) {
  for (const [name, source] of Object.entries(layers)) {
    if (!configure[name]) throw new TypeError(`Unknown layer source: ${name}`);
    defer(configure[name](source));
  }
  if (live.flights) flights.setSource(live.flights);
  if (live.military) {
    military.setSource(live.military);
    defer(configureMilitaryRegistrySource(live.military, { signal }));
  }
  if (live.vessels) vessels.setSource(live.vessels);
}
export const liveLayers = Object.freeze({ flights, military, vessels });
