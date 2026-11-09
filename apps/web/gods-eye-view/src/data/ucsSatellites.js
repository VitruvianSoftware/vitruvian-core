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
 * @file The bundled UCS Satellite Database pack: operator, owner country and
 * purpose for active satellites, keyed by NORAD catalog number.
 *
 * Data: `local_data/ucs_satellites/ucs_satellites.json`, built by
 * `scripts/build-ucs-satellites.py` from UCS-Satellite-Database 5-1-2023
 * (https://www.ucsusa.org/satellite_database; free, unrestricted use, with an
 * acknowledgement). Loaded once, on demand, by the satellites layer; a failed
 * load is retried after a cooldown rather than remembered for the session.
 *
 * @module data/ucsSatellites
 */

import { loadBundledJson } from './bundledJson.js';
import { createRetryableLoader } from './retryableLoad.js';

const PACK_URL = new URL(
  './local_data/ucs_satellites/ucs_satellites.json',
  import.meta.url,
);

/**
 * One UCS row: what UCS says about a satellite's operator and purpose.
 * @typedef {{noradId: number, operator: string|null,
 *   operatorCountry: string|null, purpose: string|null}} UcsSatellite
 */

/**
 * Expand the pack's string-table rows into records keyed by NORAD number.
 * A pack of the wrong shape throws: read as an empty pack it would be kept
 * for the session, and every satellite would quietly lose its UCS evidence.
 * A malformed row is skipped.
 * @param {{fields: string[], strings: Record<string, string[]>,
 *   records: Array<number[]>}} pack Parsed `ucs_satellites.json`.
 * @returns {Map<number, UcsSatellite>}
 */
export function indexUcsPack(pack) {
  const byNorad = new Map();
  const fields = pack?.fields;
  if (
    !Array.isArray(fields) ||
    fields[0] !== 'noradId' ||
    !Array.isArray(pack.records)
  )
    throw new TypeError('UCS pack has an unexpected shape');
  for (const row of pack.records) {
    const noradId = row?.[0];
    if (!Number.isInteger(noradId) || noradId <= 0) continue;
    const record = { noradId };
    for (let i = 1; i < fields.length; i++) {
      const text = pack.strings?.[fields[i]]?.[row[i]];
      record[fields[i]] = text ? text : null;
    }
    byNorad.set(noradId, record);
  }
  return byNorad;
}

/** The pack, loaded and indexed once. */
export const loadUcsSatellites = createRetryableLoader(async () =>
  indexUcsPack(await loadBundledJson(PACK_URL)),
);
