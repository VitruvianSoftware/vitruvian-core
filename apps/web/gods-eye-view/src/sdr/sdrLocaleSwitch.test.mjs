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

// The receiver's messages follow a language switch while anyone listens,
// reach a later listener in the current language, and stop following once
// the controller is destroyed.
import test from 'node:test';
import assert from 'node:assert/strict';
import { setLocale, t } from '../i18n/index.js';
import { SdrController } from './controller.js';

const UNAVAILABLE = 'WebUSB is unavailable in this browser';

test('a listener hears the message worded again after a switch', () => {
  const c = new SdrController({ storage: null, webUsb: null });
  const seen = [];
  const off = c.subscribe((state) => seen.push(state.message));
  try {
    setLocale('es');
    assert.equal(seen.at(-1), t(UNAVAILABLE));
    assert.notEqual(seen.at(-1), UNAVAILABLE);
  } finally {
    off();
    setLocale('en');
  }
});

test('a listener that subscribes after a switch gets the current language', () => {
  const c = new SdrController({ storage: null, webUsb: null });
  c.subscribe(() => {})();
  setLocale('ru');
  try {
    let first;
    const off = c.subscribe((state) => (first ??= state.message));
    off();
    assert.equal(first, t(UNAVAILABLE));
  } finally {
    setLocale('en');
  }
});

test('a destroyed controller no longer follows the language', async () => {
  const c = new SdrController({ storage: null, webUsb: null });
  c.subscribe(() => {});
  await c.destroy();
  let reworded = 0;
  c._reword = () => reworded++;
  setLocale('es');
  setLocale('en');
  assert.equal(reworded, 0);
});
