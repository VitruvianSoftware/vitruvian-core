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

// The blocked-visibility toast reason in the UI language.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setLocale } from '../i18n/index.js';
import {
  _handleContextLayerChange,
  localizeVisibilityBlockReason,
} from './contextLayerChanges.js';

function fakeShell() {
  const toasts = [];
  return {
    destroyed: false,
    _userFacingContextNotificationTokens: new Set(),
    _contextSessionSnapshot: null,
    _contextModeChanging: false,
    _contextMode: null,
    _contextModeEntering: null,
    _syncContextModeButtons() {},
    showToast(message) {
      toasts.push(message);
    },
    toasts,
  };
}

test.afterEach(() => setLocale('en'));

test('en: the toast shows the reason unchanged', () => {
  setLocale('en');
  const shell = fakeShell();
  _handleContextLayerChange.call(shell, {
    type: 'visibility-blocked',
    layerId: 'street-level',
    enabled: true,
    origin: 'user',
    reason: 'Data source unavailable',
  });
  assert.deepEqual(shell.toasts, ['Data source unavailable']);
  assert.equal(
    localizeVisibilityBlockReason('Overpass returned HTTP 503'),
    'Overpass returned HTTP 503',
  );
});

for (const locale of ['es', 'ru']) {
  test(`${locale}: a known lifecycle reason is looked up in the catalog`, () => {
    setLocale(locale);
    const shell = fakeShell();
    shell._contextMode = null;
    _handleContextLayerChange.call(shell, {
      type: 'visibility-blocked',
      layerId: 'street-level',
      enabled: true,
      origin: 'user',
      reason: 'Data source unavailable',
    });
    assert.equal(shell.toasts.length, 1);
    assert.notEqual(shell.toasts[0], 'Data source unavailable');
  });

  test(`${locale}: an unknown provider message passes through verbatim`, () => {
    setLocale(locale);
    assert.equal(
      localizeVisibilityBlockReason('Overpass returned HTTP 503'),
      'Overpass returned HTTP 503',
    );
  });
}
