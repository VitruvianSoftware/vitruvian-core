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

// Flights / Military feed failure texts reach the DATA LAYERS row in the
// UI language; the feeds keep them in English.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LayerPanel } from './layerPanel.js';
import { setLocale } from '../i18n/index.js';
import { httpError, LiveSourceError } from '../sources/live/contract.js';

const panel = LayerPanel.prototype;

function flightsRow(error) {
  return panel._buildMetaText({
    id: 'flights',
    enabled: true,
    stats: {
      count: 0,
      stale: true,
      error,
      status: 429,
      retryInSec: 45,
      source: 'OpenSky',
      lastUpdate: Date.now(),
    },
  });
}

const cases = [
  ['OpenSky 429 anonymous', 'OpenSky rate limited (anonymous)'],
  ['OpenSky auth', 'OpenSky auth required'],
  ['generic 429', httpError({ status: 429 }, 'Flights').message],
  ['HTTP 503', httpError({ status: 503 }, 'Military aircraft').message],
  [
    'network error',
    new LiveSourceError('unavailable', 'Flights network error').message,
  ],
  ['stale snapshot', 'Source snapshot 7 min old'],
  ['snapshot time unknown', 'Source snapshot time unavailable'],
  ['non-LiveSourceError', 'Live data unavailable'],
  ['malformed', 'Malformed OpenSky response'],
  ['malformed rows', 'Malformed adsb.lol aircraft rows'],
];

test('en: feed failure texts stay English', () => {
  setLocale('en');
  for (const [, message] of cases)
    assert.equal(
      flightsRow(message),
      `STALE · OpenSky · ${message} · retry 45s`,
    );
});

for (const locale of ['es', 'ru']) {
  test(`${locale}: feed failure texts are translated in the layer row`, () => {
    setLocale(locale);
    try {
      for (const [name, message] of cases) {
        const row = flightsRow(message);
        assert.ok(
          !row.includes(message),
          `${locale} ${name}: row still contains English detail: ${row}`,
        );
      }
      assert.match(flightsRow('Source snapshot 7 min old'), /\b7\b/);
      assert.match(flightsRow('Flights HTTP 503'), /\b503\b/);
    } finally {
      setLocale('en');
    }
  });
}
