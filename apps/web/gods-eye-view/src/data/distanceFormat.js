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
 * Kilometre decimals for a distance: one below 10 km, none from there on.
 * The cut is taken on the tenth that prints, so 9.96 km reads 10 km, not 10.0.
 * @param {number} meters
 * @returns {0|1}
 */
export function kilometreDigits(meters) {
  return Math.round(meters / 100) < 100 ? 1 : 0;
}

/**
 * The unit and precision a distance prints with: metres below 1 km, then
 * kilometres with `kilometreDigits`. Metres round to `metreStep` (10 for tens),
 * except below `exactBelowM`, where they stay whole. Each cut is taken after
 * rounding, so 999.6 m reads 1.0 km rather than 1000 m.
 * @param {number} meters
 * @param {{metreStep?: number, exactBelowM?: number}} [options]
 * @returns {{value: number, unit: 'm'|'km', digits: 0|1}|null} null for a
 *   distance that is negative or not finite. The value is already rounded to
 *   `digits`, so toFixed and Intl render it the same way.
 */
export function distanceParts(meters, { metreStep = 1, exactBelowM = 0 } = {}) {
  if (!Number.isFinite(meters) || meters < 0) return null;
  const step = meters < exactBelowM ? 1 : metreStep;
  const shownMeters = Math.round(meters / step) * step;
  if (shownMeters < 1000) return { value: shownMeters, unit: 'm', digits: 0 };
  const digits = kilometreDigits(meters);
  const value =
    digits === 1 ? Math.round(meters / 100) / 10 : Math.round(meters / 1000);
  return { value, unit: 'km', digits };
}

/**
 * Plain `850 m` / `4.6 km` / `12 km` text for labels that are not localized.
 * @param {number} meters
 * @param {{metreStep?: number, exactBelowM?: number}} [options]
 * @returns {string|null}
 */
export function formatDistanceText(meters, options) {
  const parts = distanceParts(meters, options);
  if (!parts) return null;
  return `${parts.value.toFixed(parts.digits)} ${parts.unit}`;
}
