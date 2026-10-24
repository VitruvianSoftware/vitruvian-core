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
import { setLocale } from '../../i18n/index.js';
import { createWindLayer } from './index.js';

test('stale wind forecast is marked in the UI language', async () => {
  const rendering = Object.fromEntries(
    ['attach', 'start', 'stop', 'clear', 'destroy', 'setField'].map((n) => [
      n,
      () => {},
    ]),
  );
  rendering.getDiagnostics = () => ({});
  const layer = createWindLayer({
    feed: {
      getSnapshot: async () => ({
        model: 'gfs',
        grid: { nx: 2, ny: 2 },
        cycle: {
          runIso: '2026-09-14T12:00:00Z',
          validIso: '2026-09-14T18:00:00Z',
        },
        stale: true,
        reason: 'Wind upstream unavailable',
      }),
    },
    createRendering: () => rendering,
  });
  layer.init({ container: {} });
  layer.enable();
  await layer.update();
  try {
    assert.match(layer.getRowControls().info, / · STALE(\n|$)/);
    for (const [locale, word] of [
      ['es', 'DESACTUALIZADO'],
      ['ru', 'УСТАРЕЛ'],
    ]) {
      setLocale(locale);
      const info = layer.getRowControls().info;
      assert.doesNotMatch(info, /STALE/);
      assert.match(info, new RegExp(word));
    }
  } finally {
    setLocale('en');
    layer.destroy();
  }
});
