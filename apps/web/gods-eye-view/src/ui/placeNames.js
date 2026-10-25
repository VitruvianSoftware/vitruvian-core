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
 * Preset place names as the page shows them.
 *
 * The preset cities in src/cityPois.js keep their English names in data:
 * those are what voice tools, the AI model, share links and lookups match on.
 * This helper translates a known English name at a presentation boundary
 * only; any other place (a geocoded address, a name the model chose) is shown
 * as given.
 *
 * Pure: imports only i18n, no DOM.
 * @module ui/placeNames
 */
import { msg, t } from '../i18n/index.js';

// The preset cities (CITY_POIS names, kept in step by placeNames.test.mjs),
// and Los Angeles, which voice results name for the analyst's region scopes.
const PLACE_NAME_KEYS = new Map(
  [
    msg('Austin'),
    msg('San Francisco'),
    msg('New York'),
    msg('Tokyo'),
    msg('London'),
    msg('Paris'),
    msg('Dubai'),
    msg('Washington DC'),
    msg('Tallinn'),
    msg('Los Angeles'),
  ].map((key) => [key, key]),
);

/**
 * A preset place name in the active language; any other text unchanged.
 * @param {string} name English place name, e.g. `Tokyo`.
 * @returns {string}
 */
export function localizePlaceName(name) {
  if (typeof name !== 'string') return name;
  const key = PLACE_NAME_KEYS.get(name.trim());
  return key ? t(key) : name;
}

/** The English names this module translates (for tests). */
export const KNOWN_PLACE_NAMES = Object.freeze([...PLACE_NAME_KEYS.keys()]);
