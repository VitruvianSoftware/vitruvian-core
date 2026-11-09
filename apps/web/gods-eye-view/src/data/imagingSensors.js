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

/**
 * @file The bundled imaging-sensor pack: swath and resolution for the main
 * Earth-observation platforms, matched to satellites by NORAD number or name.
 *
 * Data: `local_data/imaging_sensors/imaging_sensors.json`; sources, licences
 * and curation in that folder's README. Loaded once, on demand, by the
 * satellites layer; a failed load is retried after a cooldown rather than
 * remembered for the session.
 *
 * @module data/imagingSensors
 */

import { indexImagingSensors } from '../layers/satellites/sensors.js';
import { loadBundledJson } from './bundledJson.js';
import { createRetryableLoader } from './retryableLoad.js';

const PACK_URL = new URL(
  './local_data/imaging_sensors/imaging_sensors.json',
  import.meta.url,
);

/** The pack, loaded and indexed once. */
export const loadImagingSensors = createRetryableLoader(async () =>
  indexImagingSensors(await loadBundledJson(PACK_URL)),
);
