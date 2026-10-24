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
import { createApplicationRequestServices } from './requests.js';
test('unknown capability replies recover after backoff', async (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: 100_000 });
  for (const first of [
    () => Response.json({ wrong: true }),
    () => new Response('bad', { status: 503 }),
  ]) {
    let probes = 0;
    let queries = 0;
    const services = createApplicationRequestServices({
      boundaryProbe: { timeoutMs: 1000, retryMs: 1000 },
      fetchImpl: async (url) => {
        if (url.endsWith('/status'))
          return ++probes === 1
            ? first()
            : Response.json({ configured: false });
        queries++;
        return Response.json({ elements: [] });
      },
    });
    assert.deepEqual(await services.boundaries.query('fixture'), []);
    assert.deepEqual(await services.boundaries.query('fixture'), []);
    assert.equal(probes, 1, 'unknown reply is not re-probed inside backoff');
    t.mock.timers.tick(1000);
    assert.equal(
      (await services.boundaries.query('fixture')).code,
      'OVERPASS_NOT_CONFIGURED',
    );
    assert.equal(
      (await services.boundaries.query('fixture')).code,
      'OVERPASS_NOT_CONFIGURED',
    );
    assert.equal(probes, 2);
    assert.equal(queries, 2);
  }
});
