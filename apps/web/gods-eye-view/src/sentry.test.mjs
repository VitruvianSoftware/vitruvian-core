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
  initClientSentry,
  captureClientException,
  triggerClientTestException,
  isClientSentryInitialized,
  attachVueApp,
  onDiagnosticsChange,
} from './sentry.js';

test('client sentry gracefully no-ops without VITE_SENTRY_DSN or runtime config', async () => {
  const originalDsn = import.meta.env?.VITE_SENTRY_DSN;
  try {
    if (import.meta.env) {
      delete import.meta.env.VITE_SENTRY_DSN;
    }
    const initialized = await initClientSentry();
    assert.equal(initialized, false);
    assert.equal(isClientSentryInitialized(), false);
  } finally {
    if (originalDsn !== undefined && import.meta.env) {
      import.meta.env.VITE_SENTRY_DSN = originalDsn;
    }
  }
});

test('captureClientException is safe when uninitialized', () => {
  assert.equal(captureClientException(new Error('test uninitialized')), undefined);
  assert.doesNotThrow(() => {
    captureClientException('string error', { tag: 'unit-test' });
  });
});

test('triggerClientTestException does not throw when uninitialized', () => {
  assert.doesNotThrow(() => {
    const result = triggerClientTestException();
    assert.equal(result, undefined);
  });
});

test('attachVueApp configures error handler on Vue app', () => {
  let handled = false;
  const fakeApp = {
    config: {
      errorHandler: null,
    },
  };
  attachVueApp(fakeApp);
  assert.equal(typeof fakeApp.config.errorHandler, 'function');
  fakeApp.config.errorHandler(new Error('test vue error'), { $options: { name: 'TestView' } }, 'mounted hook');
});

test('onDiagnosticsChange subscribes and unsubscribes cleanly', () => {
  const events = [];
  const unsub = onDiagnosticsChange((active) => events.push(active));
  assert.equal(typeof unsub, 'function');
  unsub();
});
