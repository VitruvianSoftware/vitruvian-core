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
import { ShellFacade } from './shellFacade.js';

// A shell assembled without its navigation owner (as unit tests build one
// from the prototype) has no handoffs to report, like the facade's other
// optional owners; the voice runner subscribes as it is created.
test('camera handoffs without a navigation owner subscribe to nothing', () => {
  const shell = Object.create(ShellFacade.prototype);
  assert.equal(
    shell.subscribeCameraHandoff(() => {}),
    undefined,
  );
});

test('camera handoffs reach listeners through the navigation owner', () => {
  const listeners = new Set();
  const shell = Object.create(ShellFacade.prototype);
  shell._navigation = {
    subscribeCameraHandoff(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
  let handoffs = 0;
  const unsubscribe = shell.subscribeCameraHandoff(() => {
    handoffs += 1;
  });
  for (const listener of listeners) listener();
  assert.equal(handoffs, 1);
  unsubscribe();
  assert.equal(listeners.size, 0);
});
