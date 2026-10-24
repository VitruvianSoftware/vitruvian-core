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

// Wind source failures are English data (src/layers/wind/source.js) and
// are shown in the UI language; the HTTP line keeps its status number.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createWindLayer } from './index.js';
import { setLocale } from '../../i18n/index.js';

function harness(problem) {
  const rendering = Object.fromEntries(
    [
      'attach',
      'start',
      'stop',
      'clear',
      'destroy',
      'setField',
      'setOptions',
    ].map((name) => [name, () => {}]),
  );
  rendering.getDiagnostics = () => ({});
  const layer = createWindLayer({
    feed: {
      getSnapshot: async () => {
        throw new Error(problem);
      },
    },
    createRendering: () => rendering,
  });
  layer.init({ container: {} });
  layer.enable();
  return layer;
}

async function statusFor(problem) {
  const layer = harness(problem);
  await layer.update();
  return layer.getRowControls().summary.status;
}

test('en: wind source failures read as before', async () => {
  assert.equal(await statusFor('Wind HTTP 503'), 'Wind HTTP 503');
  assert.equal(
    await statusFor('Wind request timed out'),
    'Wind request timed out',
  );
});

for (const locale of ['es', 'ru']) {
  test(`${locale}: wind source failures are shown in the UI language`, async () => {
    setLocale(locale);
    try {
      const http = await statusFor('Wind HTTP 503');
      assert.notEqual(http, 'Wind HTTP 503');
      assert.match(http, /503/);
      for (const problem of [
        'Wind request timed out',
        'Malformed wind manifest',
        'Malformed wind grid',
      ])
        assert.notEqual(await statusFor(problem), problem);
    } finally {
      setLocale('en');
    }
  });
}
