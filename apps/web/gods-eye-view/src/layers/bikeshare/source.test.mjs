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
import { createBikeshareSource } from './source.js';
test('station source keeps upstream URLs behind the fixed GBFS endpoint', async () => {
  const calls = [];
  const source = createBikeshareSource({
    fetchImpl: async (...args) => {
      calls.push(args);
      return new Response('{"data":{"stations":[]}}');
    },
  });
  for (const url of [
    'file:///etc/passwd',
    'http://example.test/stations',
    'https://user:pass@example.test/stations',
  ])
    await assert.rejects(source.getStations(url), /HTTPS GBFS/);
  assert.equal(calls.length, 0);
  await source.getStations('https://example.test/stations.json');
  const url = new URL(calls[0][0], 'https://app.example');
  assert.equal(url.search, '');
  assert.equal(
    decodeURIComponent(url.pathname.replace(/^\/api\/gbfs\//, '')),
    'https://example.test/stations.json',
  );
});
test('cancelled station parsing never publishes the response', async () => {
  const controller = new AbortController();
  const source = createBikeshareSource({
    fetchImpl: async () => ({
      ok: true,
      json: async () => {
        controller.abort();
        return { data: { stations: [] } };
      },
    }),
  });
  await assert.rejects(
    source.getStations('https://example.test/stations', {
      signal: controller.signal,
    }),
    { name: 'AbortError' },
  );
});
