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
import {
  MACOS_CHROME,
  chromeExecutablePath,
  captureQaScreenshot,
} from '../scripts/qa-chrome.mjs';

test('gates keep macOS Chrome where it is installed', () => {
  assert.equal(
    chromeExecutablePath({ env: {}, exists: (p) => p === MACOS_CHROME }),
    MACOS_CHROME,
  );
});

test('gates fall back to Puppeteer’s browser without macOS Chrome', () => {
  assert.equal(
    chromeExecutablePath({ env: {}, exists: () => false }),
    undefined,
  );
});

test('an explicit executable path wins', () => {
  assert.equal(
    chromeExecutablePath({
      env: { PUPPETEER_EXECUTABLE_PATH: 'C:\\Chrome\\chrome.exe' },
      exists: () => true,
    }),
    'C:\\Chrome\\chrome.exe',
  );
});

test('screenshots restore minimized test windows before capture and detach their session', async () => {
  const calls = [];
  const session = {
    send: async (method, params) => {
      calls.push([method, params]);
      return { windowId: 7, bounds: { windowState: 'minimized' } };
    },
    detach: async () => calls.push(['detach']),
  };
  const page = {
    createCDPSession: async () => session,
    bringToFront: async () => calls.push(['front']),
    screenshot: async (options) => {
      calls.push(['capture', options]);
      return 'pixels';
    },
  };
  assert.equal(
    await captureQaScreenshot(page, { path: 'proof.png' }),
    'pixels',
  );
  assert.deepEqual(
    calls.map((c) => c[0]),
    [
      'Browser.getWindowForTarget',
      'Browser.setWindowBounds',
      'front',
      'detach',
      'capture',
    ],
  );
  assert.deepEqual(calls[1][1], {
    windowId: 7,
    bounds: { windowState: 'normal' },
  });
});

test('headless capture does not manipulate a native window', async () => {
  const options = { path: 'proof.png' };
  const page = {
    screenshot: async (supplied) => {
      assert.equal(supplied, options);
      return 'pixels';
    },
  };
  assert.equal(
    await captureQaScreenshot(page, options, { headful: false }),
    'pixels',
  );
});
