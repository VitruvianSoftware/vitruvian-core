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

import test from 'node:test';
import assert from 'node:assert/strict';
import { setLocale, t, tn, getLocale } from './index.js';
import {
  resolveLocale,
  LOCALE_STORAGE_KEY,
  writeStoredLocale,
  applyDocumentLanguage,
} from './locale.js';
import { hudQuantity, LOCALIZED_LOCALITY } from '../hudLocalityFormat.js';
import { formatCockpitDistance } from '../ui/cockpitPresentation.js';
import { READOUT_WORDS } from '../layers/recentImagery/display.js';
import { cctvSourceStatusLabel } from '../ui/cctvFrames.js';

test('Traditional Chinese resolves from URL, saved preference and browser language', () => {
  assert.equal(
    resolveLocale({
      location: { search: '?lang=zh-TW' },
      storage: { getItem: () => 'en' },
      languages: ['en'],
    }),
    'zh-Hant',
  );
  assert.equal(
    resolveLocale({
      location: { search: '' },
      storage: {
        getItem: (key) => (key === LOCALE_STORAGE_KEY ? 'zh-TW' : null),
      },
      languages: ['en'],
    }),
    'zh-Hant',
  );
  assert.equal(
    resolveLocale({
      location: { search: '' },
      storage: { getItem: () => null },
      languages: ['zh-Hant', 'en'],
    }),
    'zh-Hant',
  );
});

test('Traditional Chinese persists and exposes the script locale for legacy choices', () => {
  const stored = new Map();
  assert.equal(
    writeStoredLocale('zh-TW', {
      setItem: (key, value) => stored.set(key, value),
    }),
    true,
  );
  assert.equal(stored.get(LOCALE_STORAGE_KEY), 'zh-Hant');
  const doc = { documentElement: {} };
  assert.equal(applyDocumentLanguage(doc, 'zh-TW'), true);
  assert.equal(doc.documentElement.lang, 'zh-Hant');
  assert.equal(doc.documentElement.dir, 'ltr');
});

test('Traditional Chinese readouts preserve unit case, coordinates and natural relative dates', () => {
  const previous = getLocale();
  try {
    setLocale('zh-Hant');
    assert.equal(hudQuantity(2069, 'km', 1), '2069.0 km');
    assert.equal(formatCockpitDistance(14000), '14\u00a0km');
    assert.equal(
      LOCALIZED_LOCALITY.sector({ latDeg: 21.33, lonDeg: -77.5 }),
      '扇區 21.33N 77.50W',
    );
    assert.equal(READOUT_WORDS.daysAgo(9), '9 天前');
    assert.equal(READOUT_WORDS.daysAgo(0), '今天');
    assert.equal(cctvSourceStatusLabel('ok'), '正常');
    assert.equal(t('SAVE KEYS'), '保存密鑰');
    assert.equal(
      tn(2, 'Click {count} more point.', 'Click {count} more points.'),
      '再點擊 2 個點。',
    );
  } finally {
    setLocale(previous);
  }
});
