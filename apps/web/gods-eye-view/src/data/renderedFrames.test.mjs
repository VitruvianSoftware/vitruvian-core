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
import { bindRenderer } from '../render/rendererOf.js';
import { renderedFrames } from './renderedFrames.js';

test('the key changes once per drawn frame, after it is drawn', () => {
  const viewer = {};
  const listeners = { postRender: new Set() };
  bindRenderer(viewer, {
    frame: {
      on(phase, cb) {
        listeners[phase].add(cb);
        return () => listeners[phase].delete(cb);
      },
    },
  });
  assert.equal(renderedFrames(viewer), 0);
  assert.equal(renderedFrames(viewer), 0, 'reading does not advance it');
  assert.equal(listeners.postRender.size, 1);
  for (const cb of listeners.postRender) cb({});
  assert.equal(renderedFrames(viewer), 1);
  renderedFrames(viewer);
  assert.equal(listeners.postRender.size, 1, 'one listener per frame port');
});

test('without a frame port the key is -1', () => {
  assert.equal(renderedFrames(null), -1);
  assert.equal(renderedFrames({}), -1);
});
