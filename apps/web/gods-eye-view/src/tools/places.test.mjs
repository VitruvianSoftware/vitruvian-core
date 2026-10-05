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
import { createGeocodePlaceService } from './places.js';

const answer = {
  results: [
    {
      formatted_address: 'Tokyo, Japan',
      geometry: { location: { lat: 35.68, lng: 139.76 } },
    },
  ],
};

test('place lookups are cached by name for a while, and failures are not', async () => {
  let clock = 0;
  const requests = [];
  let fail = true;
  const places = createGeocodePlaceService({
    now: () => clock,
    cacheMs: 1000,
    fetchImpl: async (url) => {
      requests.push(url);
      if (fail) return new Response(null, { status: 503 });
      return Response.json(answer);
    },
  });
  await assert.rejects(places.resolve('Tokyo'), /Geocode HTTP 503/);
  fail = false;
  const first = await places.resolve('Tokyo');
  assert.deepEqual(first.point, { lat: 35.68, lon: 139.76 });
  assert.equal(await places.resolve(' tokyo '), first);
  assert.equal(requests.length, 2);
  clock = 2000;
  await places.resolve('Tokyo');
  assert.equal(requests.length, 3);
  const aborted = new AbortController();
  aborted.abort();
  await assert.rejects(places.resolve('Tokyo', { signal: aborted.signal }));
});

test('a lookup every caller abandoned is cancelled and not reused', async () => {
  const signals = [];
  const places = createGeocodePlaceService({
    fetchImpl: (url, { signal }) => {
      signals.push(signal);
      if (signals.length === 1)
        return new Promise((resolve, reject) => {
          if (signal?.aborted) return reject(signal.reason);
          signal.addEventListener('abort', () => reject(signal.reason), { once: true });
        });
      return Promise.resolve(Response.json(answer));
    },
  });
  const caller = new AbortController();
  const first = places.resolve('Tokyo', { signal: caller.signal });
  caller.abort();
  await assert.rejects(first);
  assert.equal(signals[0].aborted, true);
  const again = await places.resolve('Tokyo');
  assert.deepEqual(again.point, { lat: 35.68, lon: 139.76 });
  assert.equal(signals.length, 2);
});

test('a shared lookup outlives one cancelled caller, and times out on its own', async () => {
  let release;
  const signals = [];
  const places = createGeocodePlaceService({
    timeoutMs: 50,
    fetchImpl: (url, { signal }) => {
      signals.push(signal);
      if (url.includes('Slow'))
        return new Promise((resolve, reject) => {
          if (signal?.aborted) return reject(signal.reason);
          const keepAlive = setTimeout(() => {}, 10_000);
          signal.addEventListener(
            'abort',
            () => {
              clearTimeout(keepAlive);
              reject(signal.reason);
            },
            { once: true },
          );
        });
      return new Promise((resolve) => {
        release = () => resolve(Response.json(answer));
      });
    },
  });
  const leaving = new AbortController();
  const gone = places.resolve('Tokyo', { signal: leaving.signal });
  const staying = places.resolve('Tokyo', {
    signal: new AbortController().signal,
  });
  leaving.abort();
  await assert.rejects(gone);
  assert.equal(signals[0].aborted, false);
  release();
  assert.deepEqual((await staying).point, { lat: 35.68, lon: 139.76 });
  await assert.rejects(
    places.resolve('Slow'),
    (error) => error.name === 'TimeoutError',
  );
  await places.resolve('Slow').catch(() => {});
  assert.equal(signals.length, 3, 'a timed-out lookup is not cached');
});
