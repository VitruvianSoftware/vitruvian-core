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

import { t } from '../../i18n/index.js';
import { UNNAMED_PLACE_NAMES } from '../../data/installationNames.js';

const UNNAMED_NAMES = new Set(UNNAMED_PLACE_NAMES);

/**
 * An installation's card title: a mapped name as it is; the English label
 * the data gives an unnamed feature ("Firing range", "Military area") in the
 * UI language. The record keeps the English name.
 * @param {string} name
 * @returns {string} Empty when the record has no name.
 */
export function installationTitle(name) {
  const text = String(name ?? '');
  return UNNAMED_NAMES.has(text.trim()) ? t(text.trim()) : text;
}

/**
 * An installation class as a map card shows it: AIRFIELD, NAVAL BASE…, in
 * the UI language. The class itself stays an English identifier in data.
 * @param {string} klass
 * @returns {string}
 */
export function installationClassLabel(klass) {
  const key = String(klass || 'installation');
  switch (key) {
    case 'airfield':
      return t('AIRFIELD', { context: 'installation class' });
    case 'naval_base':
      return t('NAVAL BASE', { context: 'installation class' });
    case 'range':
      return t('RANGE', { context: 'installation class' });
    case 'military_land':
      return t('MILITARY LAND', { context: 'installation class' });
    case 'base':
      return t('BASE', { context: 'installation class' });
    case 'barracks':
      return t('BARRACKS', { context: 'installation class' });
    case 'training_area':
      return t('TRAINING AREA', { context: 'installation class' });
    case 'places_candidate':
      return t('PLACES CANDIDATE', { context: 'installation class' });
    case 'installation':
      return t('INSTALLATION', { context: 'installation class' });
    default:
      return key.replaceAll('_', ' ').toUpperCase();
  }
}
