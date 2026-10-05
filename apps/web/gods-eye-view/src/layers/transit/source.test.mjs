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
import { createTransitSource } from './source.js';

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

test('the feed catalog is read from the public catalog route', async () => {
  const requested = [];
  const feeds = [
    {
      id: 'mbta',
      name: 'MBTA',
      center: { lat: 42.36, lon: -71.06 },
      loadRadiusKm: 60,
    },
  ];
  const source = createTransitSource({
    fetchImpl: async (url) => {
      requested.push(url);
      return json({ feeds });
    },
  });
  assert.deepEqual(await source.getFeeds(), feeds);
  assert.deepEqual(requested, ['/api/transit/feeds']);
});

test('feed catalog failures are reported', async () => {
  const failing = createTransitSource({ fetchImpl: async () => json({}, 503) });
  await assert.rejects(failing.getFeeds(), /Transit feeds HTTP 503/);
  const malformed = createTransitSource({
    fetchImpl: async () => json({ feeds: {} }),
  });
  await assert.rejects(malformed.getFeeds(), /Malformed transit feed catalog/);
  const aborted = new AbortController();
  aborted.abort();
  await assert.rejects(
    createTransitSource({
      fetchImpl: async () => json({ feeds: [] }),
    }).getFeeds({ signal: aborted.signal }),
    (error) => error.name === 'AbortError',
  );
});
