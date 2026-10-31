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
import config, { googleServerApiKey, googlePlacesContextProxy } from '../vite.config.js';
// The Street View tool's key precedence (per-variable .env overrides, server
// key first) is tested with the tool itself, now Rust:
// streetview_headings::tests in scripts/src/streetview_headings.rs.

/** Run fn with the two Google key env vars set to the given values, then restore. */
function withKeys({ server, browser }, fn) {
  const previous = {
    GOOGLE_MAPS_SERVER_API_KEY: process.env.GOOGLE_MAPS_SERVER_API_KEY,
    GOOGLE_MAPS_API_KEY: process.env.GOOGLE_MAPS_API_KEY,
  };
  const apply = (name, value) => {
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  };
  apply('GOOGLE_MAPS_SERVER_API_KEY', server);
  apply('GOOGLE_MAPS_API_KEY', browser);
  try {
    return fn();
  } finally {
    for (const [name, value] of Object.entries(previous)) apply(name, value);
  }
}

test('server-side Google calls prefer the server-only key', () => {
  withKeys({ server: 'server-key', browser: 'browser-key' }, () => {
    assert.equal(googleServerApiKey(), 'server-key');
  });
});

test('unsplit setups still work: falls back to the browser key', () => {
  // The whole point of #33 being opt-in — one shared GOOGLE_MAPS_API_KEY must
  // keep serving Places/Street View exactly as before.
  withKeys({ server: undefined, browser: 'browser-key' }, () => {
    assert.equal(googleServerApiKey(), 'browser-key');
  });
  withKeys({ server: '', browser: 'browser-key' }, () => {
    assert.equal(googleServerApiKey(), 'browser-key');
  });
});

test('keyless stays keyless', () => {
  withKeys({ server: undefined, browser: undefined }, () => {
    assert.ok(!googleServerApiKey());
  });
});

test('every Google route selects the intended key and keeps it out of responses', async (t) => {
  const original = { server: process.env.GOOGLE_MAPS_SERVER_API_KEY, browser: process.env.GOOGLE_MAPS_API_KEY, limit: process.env.GEV_RATELIMIT_GOOGLE_PER_MIN };
  const calls = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    // Places sends the key as a header; Geocoding's web service takes it as a
    // query parameter. Either way it must be the server key, and never the
    // browser's copy of it.
    calls.push({
      url,
      key:
        options?.headers?.['X-Goog-Api-Key'] ??
        new URL(String(url)).searchParams.get('key'),
    });
    return Response.json({ places: [] });
  });
  try {
    process.env.GEV_RATELIMIT_GOOGLE_PER_MIN = '';
    for (const [server, browser, expected] of [
      ['server-secret', 'browser-public', 'server-secret'],
      ['server-secret', '', 'server-secret'],
      ['', 'browser-public', 'browser-public'],
      ['   ', 'browser-public', 'browser-public'],
      ['', '', null],
    ]) {
      process.env.GOOGLE_MAPS_SERVER_API_KEY = server;
      process.env.GOOGLE_MAPS_API_KEY = browser;
      for (const install of ['configureServer', 'configurePreviewServer']) {
        const routes = new Map();
        googlePlacesContextProxy()[install]({ middlewares: { use: (name, handler) => routes.set(name, handler) } });
        assert.equal(routes.size, 4);
        for (const handler of routes.values()) {
          const before = calls.length;
          let body;
          const res = { setHeader() {}, end(value) { body = value; } };
          await handler({ method: 'GET', url: '/?lat=30&lon=-97&q=capitol&address=capitol', headers: {}, socket: { remoteAddress: '127.0.0.1' } }, res);
          assert.equal(res.statusCode, 200);
          assert.ok(!body.includes('server-secret'));
          if (expected) {
            assert.equal(calls.length, before + 1);
            assert.equal(calls.at(-1).key, expected);
          } else {
            assert.equal(calls.length, before);
            assert.equal(JSON.parse(body).configured, false);
          }
        }
      }
    }
  } finally {
    for (const [name, value] of Object.entries({ GOOGLE_MAPS_SERVER_API_KEY: original.server, GOOGLE_MAPS_API_KEY: original.browser, GEV_RATELIMIT_GOOGLE_PER_MIN: original.limit })) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  }
});

test('browser defines contain the browser key and exclude the server key', () => {
  withKeys({ server: 'server-secret', browser: 'browser-public' }, () => {
    const defines = config({ mode: 'test' }).define;
    assert.equal(defines['import.meta.env.GOOGLE_MAPS_API_KEY'], '"browser-public"');
    assert.ok(!JSON.stringify(defines).includes('server-secret'));
    assert.ok(!Object.keys(defines).some((key) => key.includes('SERVER_API_KEY')));
  });
});
