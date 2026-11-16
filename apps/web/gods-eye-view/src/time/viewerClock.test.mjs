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
import { followWorldTime } from './viewerClock.js';

function fakeViewer() {
  const listeners = new Set();
  return {
    clock: { currentTime: {} },
    scene: {
      requestRender() {},
      preUpdate: {
        addEventListener(fn) {
          listeners.add(fn);
          return () => listeners.delete(fn);
        },
      },
    },
  };
}

test('the scene hears when the world time plays on its own, and when it stops', () => {
  let listener = null;
  const subscribe = (fn) => {
    listener = fn;
    return () => (listener = null);
  };
  const heard = [];
  let at = 0;
  const stop = followWorldTime(fakeViewer(), () => at, {
    subscribe,
    requestRender: () => {},
    onPlaying: (playing) => heard.push(playing),
  });
  const state = (fields) => ({
    live: false,
    playing: false,
    stepping: false,
    buffering: false,
    ...fields,
  });
  listener(state({ live: true, playing: true }));
  assert.deepEqual(heard, [], 'live time is not playback');
  listener(state({ playing: true }));
  listener(state({ playing: true }));
  assert.deepEqual(heard, [true], 'heard once');
  listener(state({ playing: true, buffering: true }));
  assert.deepEqual(heard, [true, false], 'waiting for a layer: still');
  listener(state({ playing: true }));
  listener(state({ playing: true, stepping: true }));
  assert.deepEqual(heard, [true, false, true, false], 'a driver steps it');
  listener(state({ playing: true }));
  stop();
  assert.deepEqual(
    heard,
    [true, false, true, false, true, false],
    'stopping releases',
  );
  assert.equal(listener, null);
});
