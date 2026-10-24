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

import assert from 'node:assert/strict';
import test from 'node:test';
import { APPLICATION_LAYER_METADATA } from '../app/constructCatalog.js';
import { setLocale, t } from '../i18n/index.js';
import { FEED_SOURCE, COMBINED_SOURCE } from '../layers/localAdsb/status.js';
import {
  LAYER_NAME_KEYS,
  PANEL_LABEL_KEYS,
  sourceLabel,
} from './layerNames.js';

// Layers whose module name is a proper name and stays as it is in every
// language: the Bhote Koshi pair belong to a scripted scene.
const UNTRANSLATED_NAMES = new Set(['bhote-koshi-2026', 'bhote-koshi-locator']);

const catalogIds = APPLICATION_LAYER_METADATA.map((layer) => layer.id);

test('every catalog layer has a translatable name', () => {
  const missing = catalogIds.filter(
    (id) =>
      !UNTRANSLATED_NAMES.has(id) &&
      !Object.hasOwn(LAYER_NAME_KEYS, id) &&
      !Object.hasOwn(PANEL_LABEL_KEYS, id),
  );
  assert.deepEqual(
    missing,
    [],
    'add the layer to LAYER_NAME_KEYS in src/ui/layerNames.js',
  );
});

test('the name tables list only catalog layers', () => {
  const unknown = [
    ...Object.keys(LAYER_NAME_KEYS),
    ...Object.keys(PANEL_LABEL_KEYS),
    ...UNTRANSLATED_NAMES,
  ].filter((id) => !catalogIds.includes(id));
  assert.deepEqual(unknown, []);
});

for (const locale of ['es', 'ru']) {
  test(`${locale}: Local ADS-B source names translate without their own entry`, () => {
    setLocale(locale);
    try {
      for (const source of [FEED_SOURCE, COMBINED_SOURCE]) {
        assert.notEqual(t(source), source, 'the catalog has the entry');
        assert.equal(sourceLabel(source), t(source));
      }
    } finally {
      setLocale('en');
    }
  });
}
