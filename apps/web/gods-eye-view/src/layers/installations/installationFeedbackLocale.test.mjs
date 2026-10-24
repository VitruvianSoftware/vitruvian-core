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
import { setLocale, translateKnown } from '../../i18n/index.js';
import { createControls } from './controls.js';

function stats(state) {
  const layerState = { records: [], enabled: true, ...state };
  return createControls({
    state: layerState,
    services: {},
    parts: {},
    source: {},
  }).methods.getStats();
}

for (const locale of ['es', 'ru']) {
  test(`${locale}: installation feedback is in the UI language`, () => {
    setLocale(locale);
    const empty = stats({ status: 'empty', lastUpdate: 1 }).statusMessage;
    assert.notEqual(empty, 'No mapped sites in view');
    const found = stats({
      status: 'ready',
      lastUpdate: 1,
      records: [{ kind: 'installation' }, { kind: 'installation' }],
    }).statusMessage;
    assert.notEqual(found, '2 mapped sites in view');
    const tiles = stats({
      status: 'unavailable',
      failureReason: 'tiles_unavailable',
    }).statusMessage;
    assert.notEqual(tiles, 'Map tiles temporarily unavailable');
    const retry = stats({
      status: 'unavailable',
      failureReason: 'names_unavailable',
      retryAt: Date.now() + 5000,
    }).statusMessage;
    assert.doesNotMatch(retry, /^Mapped names temporarily unavailable/);
    for (const text of [
      'Too many mapped sites in view to list them all',
      'Installation context unavailable',
    ]) {
      assert.notEqual(translateKnown(text), text);
    }
  });
}

test('en: installation feedback keeps its English wording', () => {
  setLocale('en');
  assert.equal(
    stats({ status: 'empty', lastUpdate: 1 }).statusMessage,
    'No mapped sites in view',
  );
  assert.equal(
    stats({
      status: 'ready',
      lastUpdate: 1,
      records: [{ kind: 'installation' }],
    }).statusMessage,
    '1 mapped site in view',
  );
  assert.equal(
    stats({
      status: 'ready',
      lastUpdate: 1,
      wide: true,
      coverage: { kind: 'subject', radiusM: 25000 },
      records: [{ kind: 'installation' }, { kind: 'installation' }],
    }).statusMessage,
    '2 mapped sites within 25 km of the contact',
  );
  assert.equal(
    stats({
      status: 'unavailable',
      failureReason: 'names_unavailable',
      retryAt: Date.now() + 5000,
    }).statusMessage,
    'Mapped names temporarily unavailable — retrying in 5s',
  );
});
