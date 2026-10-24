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
 * @module hudLocalityFormat
 * @description The HUD summary's locality line in the active language — the
 * formatter `hud.js` hands to `composeLocalityTag`. Kept apart from `hud.js`
 * (which imports `mgrs`, not loadable under plain Node) so it is unit-testable.
 */
import { formatNumber, getLocale, t } from './i18n/index.js';
import { unitLabel } from './ui/unitLabels.js';
import { localizePlaceName } from './ui/placeNames.js';

/** An upper-case HUD quantity such as `13KM` / `13КМ`, in the active language. */
export function hudQuantity(value, unit, digits = 0) {
  const number = formatNumber(value, {
    useGrouping: false,
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  });
  const label = unitLabel(unit);
  if (getLocale() === 'zh-CN') return label ? `${number} ${label}` : number;
  return `${number}${label.toUpperCase()}`;
}

/** One hemisphere-tagged coordinate, e.g. `21.33N` / `21,33С`. */
function hudCoordinate(value, positive, negative) {
  return `${hudQuantity(Math.abs(value), '', 2)}${value >= 0 ? positive : negative}`;
}

/** The summary's locality line in the active language (see hudLocality.js). */
export const LOCALIZED_LOCALITY = Object.freeze({
  // Translate the catalogued name (`Tokyo`), then upper-case it in the page's
  // language: the place-name table knows `Tokyo`, not `TOKYO`.
  near: ({ poi, city, distKm }) =>
    t('NEAR {poi} ({city}) {distance}', {
      poi: poi.toLocaleUpperCase(getLocale()),
      city: localizePlaceName(city).toLocaleUpperCase(getLocale()),
      distance: hudQuantity(Math.round(distKm), 'km'),
    }),
  sector: ({ latDeg, lonDeg }) =>
    t('SECTOR {lat} {lon}', {
      // Hemisphere letters, not compass words: 21.33N, never 21.33北.
      lat: hudCoordinate(
        latDeg,
        t('N', { context: 'hemisphere' }),
        t('S', { context: 'hemisphere' }),
      ),
      lon: hudCoordinate(
        lonDeg,
        t('E', { context: 'hemisphere' }),
        t('W', { context: 'hemisphere' }),
      ),
    }),
});
