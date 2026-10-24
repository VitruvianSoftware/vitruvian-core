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

// The DATA LAYERS row shows the English status texts that GNSS, Transit,
// CelesTrak and AQHI produce in the UI language.
import assert from 'node:assert/strict';
import test from 'node:test';
import { setLocale } from '../i18n/index.js';
import { LayerPanel } from './layerPanel.js';

const row = (id, stats) =>
  LayerPanel.prototype._buildMetaText({ id, enabled: true, stats });
const now = Date.now();

// [layer id, stats, English fragment that must not reach the row]
const cases = [
  [
    'gnss-integrity',
    {
      count: 0,
      error: 'GNSS feed rate limited (HTTP 429)',
      source: 'GNSS',
      lastUpdate: now,
    },
    'rate limited',
  ],
  [
    'gnss-integrity',
    {
      count: 0,
      error: 'GNSS feed unavailable (HTTP 503)',
      source: 'GNSS',
      lastUpdate: now,
    },
    'feed unavailable',
  ],
  [
    'transit',
    {
      count: 0,
      error: 'GO Transit feed unavailable',
      source: 'GTFS-RT',
      lastUpdate: now,
    },
    'feed unavailable',
  ],
  [
    'transit',
    {
      count: 0,
      loading: true,
      loadingLabel: 'Loading GO Transit, Metro Transit',
      source: 'GTFS-RT',
    },
    'Loading',
  ],
  [
    'satellites',
    {
      count: 10,
      error: '1 CelesTrak group unavailable',
      source: 'CelesTrak',
      lastUpdate: now,
    },
    'group unavailable',
  ],
  [
    'air-quality',
    {
      count: 0,
      error: 'ECCC request timed out',
      source: 'ECCC',
      lastUpdate: now,
    },
    'request timed out',
  ],
];

for (const locale of ['es', 'ru']) {
  test(`${locale}: layer status texts are translated in the row`, () => {
    setLocale(locale);
    try {
      const english = cases
        .map(([id, stats, marker]) => [id, row(id, stats), marker])
        .filter(([, text, marker]) => text.includes(marker))
        .map(([id, text]) => `${id}: ${text}`);
      assert.deepEqual(english, []);
    } finally {
      setLocale('en');
    }
  });
}
