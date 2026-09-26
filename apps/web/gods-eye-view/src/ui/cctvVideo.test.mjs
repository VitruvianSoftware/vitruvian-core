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
import { createCctvVideoSurface } from './cctvVideo.js';
test('second surface uses shared decoder, caps draws, clears switch and cancels teardown', () => {
  let callback;
  let draws = 0;
  let clears = 0;
  let cancelled = 0;
  const canvas = {
    width: 1,
    height: 1,
    getContext: () => ({ drawImage: () => draws++, clearRect: () => clears++ }),
  };
  let v = {
    readyState: 2,
    videoWidth: 1920,
    videoHeight: 1080,
    currentTime: 1,
  };
  const surface = createCctvVideoSurface(canvas, () => v, {
    requestFrame: (fn) => {
      callback = fn;
      return 1;
    },
    cancelFrame: () => cancelled++,
  });
  callback(0);
  callback(20);
  callback(80);
  assert.equal(draws, 1);
  assert.equal(canvas.width, 640);
  v = { ...v };
  callback(160);
  assert.equal(draws, 2);
  assert.equal(clears, 2);
  surface.stop();
  callback(200);
  assert.equal(cancelled, 1);
  assert.equal(draws, 2);
});
