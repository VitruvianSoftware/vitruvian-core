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
import {
  initServerSentry,
  captureServerException,
  isServerSentryInitialized,
  sentryDiagnosticPlugin,
} from './sentry.js';

test('server sentry gracefully no-ops when SENTRY_DSN is unset or empty', () => {
  const originalDsn = process.env.SENTRY_DSN;
  try {
    delete process.env.SENTRY_DSN;
    const result = initServerSentry();
    assert.equal(result, false);
    assert.equal(isServerSentryInitialized(), false);
  } finally {
    if (originalDsn !== undefined) {
      process.env.SENTRY_DSN = originalDsn;
    }
  }
});

test('captureServerException is safe when uninitialized', () => {
  assert.equal(captureServerException(new Error('test uninitialized')), undefined);
  assert.doesNotThrow(() => {
    captureServerException('string error', { extra: 'data' });
  });
});

test('sentryDiagnosticPlugin configures server and previewServer with config and test routes', () => {
  const plugin = sentryDiagnosticPlugin();
  assert.match(plugin.name, /sentry-diagnostics/);
  assert.equal(typeof plugin.configureServer, 'function');
  assert.equal(typeof plugin.configurePreviewServer, 'function');

  const registeredRoutes = [];
  const fakeServer = {
    middlewares: {
      use(route, handler) {
        registeredRoutes.push({ route, handler });
      },
    },
  };

  plugin.configurePreviewServer(fakeServer);
  assert.equal(registeredRoutes.length, 2);
  assert.equal(registeredRoutes[0].route, '/api/diagnostics/sentry-config');
  assert.equal(registeredRoutes[1].route, '/api/diagnostics/sentry-test');
});

test('sentry diagnostic test route returns 404 in production without auth or explicit diagnostics flag', () => {
  const plugin = sentryDiagnosticPlugin();
  const routes = {};
  plugin.configurePreviewServer({
    middlewares: {
      use(route, handler) {
        routes[route] = handler;
      },
    },
  });

  const origEnv = process.env.NODE_ENV;
  const origDiag = process.env.GEV_ENABLE_DIAGNOSTICS;
  const origToken = process.env.GEV_DIAGNOSTICS_TOKEN;
  try {
    process.env.NODE_ENV = 'production';
    delete process.env.GEV_ENABLE_DIAGNOSTICS;
    delete process.env.GEV_DIAGNOSTICS_TOKEN;

    let statusCode = 0;
    let responseBody = '';
    const fakeReq = { method: 'GET', headers: {}, url: '/api/diagnostics/sentry-test' };
    const fakeRes = {
      writeHead(code) { statusCode = code; },
      end(body) { responseBody = body; },
    };

    routes['/api/diagnostics/sentry-test'](fakeReq, fakeRes);
    assert.equal(statusCode, 404);
    assert.deepEqual(JSON.parse(responseBody), { error: 'Not Found' });
  } finally {
    process.env.NODE_ENV = origEnv;
    if (origDiag !== undefined) process.env.GEV_ENABLE_DIAGNOSTICS = origDiag;
    if (origToken !== undefined) process.env.GEV_DIAGNOSTICS_TOKEN = origToken;
  }
});

test('sentry diagnostic test route allows requests carrying valid GEV_DIAGNOSTICS_TOKEN', () => {
  const plugin = sentryDiagnosticPlugin();
  const routes = {};
  plugin.configurePreviewServer({
    middlewares: {
      use(route, handler) {
        routes[route] = handler;
      },
    },
  });

  const origEnv = process.env.NODE_ENV;
  const origToken = process.env.GEV_DIAGNOSTICS_TOKEN;
  try {
    process.env.NODE_ENV = 'production';
    process.env.GEV_DIAGNOSTICS_TOKEN = 'secret-test-token-12345';

    let statusCode = 0;
    let responseBody = '';
    const fakeReq = {
      method: 'GET',
      headers: { authorization: 'Bearer secret-test-token-12345' },
      url: '/api/diagnostics/sentry-test',
    };
    const fakeRes = {
      writeHead(code) { statusCode = code; },
      end(body) { responseBody = body; },
    };

    routes['/api/diagnostics/sentry-test'](fakeReq, fakeRes);
    assert.equal(statusCode, 200);
    const parsed = JSON.parse(responseBody);
    assert.equal(parsed.status, 'ok');
  } finally {
    process.env.NODE_ENV = origEnv;
    if (origToken !== undefined) process.env.GEV_DIAGNOSTICS_TOKEN = origToken;
    else delete process.env.GEV_DIAGNOSTICS_TOKEN;
  }
});
