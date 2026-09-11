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
import { validatePinokioSharing } from '../scripts/pinokio-preflight.mjs';

test('Pinokio stays local by default', () => {
  assert.deepEqual(
    validatePinokioSharing({ PINOKIO_SHARE_VAR: '__gev_sharing_disabled__' }),
    { cloudflare: false, local: false, protected: false },
  );
});

test('Pinokio refuses Cloudflare sharing on the current supported release', () => {
  assert.throws(
    () => validatePinokioSharing({ PINOKIO_SHARE_CLOUDFLARE: 'true' }),
    /logs successful tunnel-login passcodes/,
  );
});

test('Pinokio refuses its post-ready LAN sharing path too', () => {
  assert.throws(
    () => validatePinokioSharing({
      PINOKIO_SHARE_LOCAL: 'true',
      PINOKIO_SHARE_VAR: '__gev_sharing_disabled__',
    }),
    /PINOKIO_SHARE_LOCAL=false/,
  );
});

test('Pinokio requires its share-trigger variable to remain isolated from the Open URL', () => {
  assert.throws(
    () => validatePinokioSharing({ PINOKIO_SHARE_VAR: 'url' }),
    /PINOKIO_SHARE_VAR=__gev_sharing_disabled__/,
  );
});

test('Pinokio matches the platform truthiness contract after trimming', () => {
  assert.throws(
    () => validatePinokioSharing({ PINOKIO_SHARE_CLOUDFLARE: ' true ' }),
    /logs successful tunnel-login passcodes/,
  );
  assert.deepEqual(
    validatePinokioSharing({
      PINOKIO_SHARE_CLOUDFLARE: 'yes',
      PINOKIO_SHARE_VAR: '__gev_sharing_disabled__',
    }),
    { cloudflare: false, local: false, protected: false },
  );
});

test('a strong passcode cannot bypass the current sharing refusal', () => {
  assert.throws(
    () => validatePinokioSharing({
      PINOKIO_SHARE_CLOUDFLARE: 'true',
      PINOKIO_SHARE_PASSCODE: 'correct-horse-battery',
    }),
    /logs successful tunnel-login passcodes/,
  );
});
