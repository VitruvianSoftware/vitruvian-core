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

// Real sockets: a client that closes its connection while the camera upstream
// is still pending must not get a Street View call outside its own budget.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { cctvProxy } from '../../server/providers/cctv.js';

const CAM = {
  id: 'still-fixture',
  name: 'Still fixture',
  lat: 30.27,
  lon: -97.74,
  feedType: 'image',
  url: 'https://cams.upstream.invalid/still.jpg',
};

test('a client that disconnects mid-fetch stays inside its own Street View budget', async (t) => {
  const saved = { ...process.env };
  process.env.CCTV_SOURCES_JSON = JSON.stringify([CAM]);
  process.env.CCTV_SOURCES_FILE = 'absent-source-file.json';
  process.env.CCTV_FORCE_AUSTIN = '0';
  process.env.GOOGLE_MAPS_SERVER_API_KEY = 'fixture-key';
  delete process.env.GOOGLE_MAPS_API_KEY;
  process.env.GEV_RATELIMIT_GOOGLE_PER_MIN = '1';
  const nativeFetch = globalThis.fetch;
  let streetViewCalls = 0;
  globalThis.fetch = async (url) => {
    if (String(url).startsWith('https://maps.googleapis.com/')) {
      streetViewCalls += 1;
      return new Response('street-view', {
        headers: { 'content-type': 'image/jpeg' },
      });
    }
    await new Promise((r) => setTimeout(r, 400));
    return new Response(null, { status: 503 });
  };
  let handler;
  cctvProxy().configureServer({
    middlewares: { use: (_r, fn) => (handler = fn) },
  });
  const server = http.createServer((req, res) => {
    req.url = req.url.replace(/^\/api\/cctv/, '');
    handler(req, res, () => res.end());
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  t.after(() => {
    server.close();
    globalThis.fetch = nativeFetch;
    for (const k of Object.keys(process.env))
      if (!(k in saved)) delete process.env[k];
    Object.assign(process.env, saved);
  });
  const { port } = server.address();
  const get = (abortAfterMs) =>
    new Promise((resolve) => {
      const req = http.get(
        {
          host: '127.0.0.1',
          port,
          path: `/api/cctv/frame/${CAM.id}`,
          headers: { host: `localhost:${port}` },
          agent: false,
        },
        (res) => {
          res.resume();
          res.on('end', () => resolve(res.headers['x-cctv-source']));
        },
      );
      req.on('error', () => resolve('aborted'));
      if (abortAfterMs)
        setTimeout(() => {
          req.destroy();
          resolve('aborted');
        }, abortAfterMs);
    });

  assert.equal(await get(), 'streetview');
  assert.equal(await get(), 'synthetic', 'the cap of one is spent');
  assert.equal(streetViewCalls, 1);
  await get(50);
  await new Promise((r) => setTimeout(r, 800));
  assert.equal(
    streetViewCalls,
    1,
    'an aborted request spent the key outside its own budget',
  );
});
