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
 * @file The satellites layer's class choice as share-link and saved-state
 * letters. Shared by the layer-state codec and the layer, which takes a saved
 * choice back in this form.
 */

/**
 * Satellite classes shown, as one letter each in legend order: stations,
 * imaging, telecom, probes, debris (`sitpd`, every one; `0`, none).
 * Starlink is the `catalog` option's, so it has no letter here.
 */
const SATELLITE_CLASS_LETTERS = Object.freeze([
  ['stations', 's'],
  ['imaging', 'i'],
  ['telecom', 't'],
  ['probes', 'p'],
  ['debris', 'd'],
]);
const SATELLITE_CLASS_MASK = /^(0|s?i?t?p?d?)$/;

/**
 * The canonical class letters for a class choice (an object of booleans, as
 * the layer's `classes` param, or a partial one) or for letters already,
 * else null.
 * @param {unknown} value
 * @returns {string|null}
 */
export function normalizeSatelliteClassMask(value) {
  if (typeof value === 'string')
    return value && SATELLITE_CLASS_MASK.test(value) ? value : null;
  if (!value || typeof value !== 'object') return null;
  // A class the choice leaves out keeps its default, which is shown: a
  // partial request (`{debris: false}`) hides only what it names.
  const letters = SATELLITE_CLASS_LETTERS.filter(([id]) => value[id] !== false)
    .map(([, letter]) => letter)
    .join('');
  return letters || '0';
}

/**
 * The class choice the letters stand for, without Starlink, or null.
 * @param {string} mask
 * @returns {Record<string, boolean>|null}
 */
export function decodeSatelliteClassMask(mask) {
  const normalized = normalizeSatelliteClassMask(mask);
  if (normalized === null || typeof mask !== 'string') return null;
  return Object.fromEntries(
    SATELLITE_CLASS_LETTERS.map(([id, letter]) => [
      id,
      normalized.includes(letter),
    ]),
  );
}
