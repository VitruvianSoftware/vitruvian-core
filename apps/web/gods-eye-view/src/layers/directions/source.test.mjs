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
import { createDirectionsSource } from './source.js';

const query = { mode: 'foot', a: { lon: 1, lat: 2 }, b: { lon: 3, lat: 4 } };

test('route acquisition uses only the supplied transport and endpoint', async () => {
  const controller = new AbortController();
  const payload = { ok: true, geometry: [[1, 2], [3, 4]] };
  const calls = [];
  const source = createDirectionsSource({
    endpoint: 'https://routes.example/route',
    fetchImpl: async (...args) => { calls.push(args); return Response.json(payload); },
  });
  assert.deepEqual(await source.getRoute(query, { signal: controller.signal }), payload);
  assert.equal(calls.length, 1);
  const [url, init] = calls[0];
  assert.equal(new URL(url).origin, 'https://routes.example');
  assert.equal(new URL(url).searchParams.get('coords'), '1.000000,2.000000;3.000000,4.000000');
  assert.equal(new URL(url).searchParams.get('profile'), 'foot');
  assert.equal(init.signal, controller.signal);
  assert.equal(init.headers.Accept, 'application/json');
});

test('aborting during route parsing discards the result', async () => {
  const controller = new AbortController();
  const source = createDirectionsSource({ fetchImpl: async () => ({
    ok: true, json: async () => { controller.abort(); return { ok: true }; },
  }) });
  await assert.rejects(source.getRoute(query, { signal: controller.signal }), { name: 'AbortError' });
});

test('route failures are surfaced without fallback requests', async () => {
  for (const status of [429, 503]) {
    let calls = 0;
    const source = createDirectionsSource({ fetchImpl: async () => {
      calls++;
      return Response.json({}, { status });
    } });
    await assert.rejects(source.getRoute(query), status === 429 ? /rate limited/ : /HTTP 503/);
    assert.equal(calls, 1);
  }
});
