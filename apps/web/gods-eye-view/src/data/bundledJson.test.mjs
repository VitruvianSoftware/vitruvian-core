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

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadBundledJson } from './bundledJson.js';

const MARINE = new URL('./local_data/natural_earth/marine.json', import.meta.url);
const importMarine = () =>
  import('./local_data/natural_earth/marine.json', { with: { type: 'json' } });

test('bundled JSON: a file URL uses the JSON import under Node', async (t) => {
  const fetchMock = t.mock.method(globalThis, 'fetch');
  const pack = await loadBundledJson(MARINE, importMarine);
  assert.ok(pack.features.some((ft) => ft.name === 'Gulf of Mexico'));
  assert.equal(fetchMock.mock.callCount(), 0);
});

test('bundled JSON: a served URL is fetched as plain JSON', async (t) => {
  const requests = [];
  t.mock.method(globalThis, 'fetch', async (url) => {
    requests.push(String(url));
    return new Response('{"features":[]}', {
      headers: { 'content-type': 'application/json' },
    });
  });
  const url = new URL('http://localhost/src/data/local_data/natural_earth/marine.json');
  const importJson = () => assert.fail('the browser path must not import JSON');
  assert.deepEqual(await loadBundledJson(url, importJson), { features: [] });
  assert.deepEqual(requests, [url.href]);
});

test('bundled JSON: an HTTP error rejects so the retryable loader can retry', async (t) => {
  t.mock.method(globalThis, 'fetch', async () => new Response('', { status: 404 }));
  await assert.rejects(
    loadBundledJson(new URL('http://localhost/missing.json'), importMarine),
    /HTTP 404/,
  );
});
