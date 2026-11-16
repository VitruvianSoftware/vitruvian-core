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
import { keepPanelRendering } from './panelRendering.js';

const windowWith = () => {
  const handles = { tick: null, frame: null };
  handles.windowRef = {
    requestAnimationFrame: (fn) => ((handles.frame = fn), 1),
    cancelAnimationFrame: () => (handles.frame = null),
    setInterval: (fn) => ((handles.tick = fn), 1),
    clearInterval: () => (handles.tick = null),
  };
  return handles;
};

test('a panel keeps drawing from a timer while animation frames stop', () => {
  let clock = 0;
  const handles = windowWith();
  const drawn = [];
  const renderer = {
    resize: () => drawn.push('resize'),
    frame: {
      renderNow: (options) =>
        drawn.push(options?.ifDue ? 'loop frame' : 'forced frame'),
    },
  };
  const stop = keepPanelRendering(renderer, {
    windowRef: handles.windowRef,
    now: () => clock,
  });
  // Frames arrive: the render loop draws, so the timer does nothing.
  clock = 100;
  handles.frame();
  handles.tick();
  assert.deepEqual(drawn, []);
  // Frames stop, as in a panel its host reports hidden: the timer draws.
  clock = 400;
  handles.tick();
  // A frame of the loop, as the loop's own: the camera moves, input and
  // the clock run, and it draws when due.
  assert.deepEqual(drawn, ['resize', 'loop frame']);
  stop();
  assert.equal(handles.tick, null);
  assert.equal(handles.frame, null);
});

test('a panel reports a failed frame in full and stops drawing', () => {
  const handles = windowWith();
  let renders = 0;
  const renderer = {
    resize() {},
    frame: {
      renderNow() {
        renders += 1;
        // Workers report plain objects.
        throw { name: 'RuntimeError', message: 'worker failed' };
      },
    },
  };
  const logged = [];
  const original = console.error;
  console.error = (...args) => logged.push(args.join(' '));
  try {
    let clock = 0;
    const stop = keepPanelRendering(renderer, {
      windowRef: handles.windowRef,
      now: () => clock,
    });
    clock = 1000;
    handles.tick();
    assert.match(logged[0], /render error: .*"message":"worker failed"/);
    handles.tick();
    assert.equal(renders, 1, 'no frame after the one that failed');
    stop();
  } finally {
    console.error = original;
  }
});

test('a panel waits while its renderer’s loop is stopped after a failed frame, and draws again once it restarts', () => {
  let clock = 0;
  const handles = windowWith();
  let stopped = false;
  let fail = false;
  let renders = 0;
  const renderer = {
    resize() {},
    frame: {
      diagnostics: () => ({ stopped }),
      renderNow() {
        renders += 1;
        if (fail) {
          // The renderer stops its loop as the frame fails.
          stopped = true;
          throw new Error('frame failed');
        }
      },
    },
  };
  const errors = [];
  const error = console.error;
  console.error = (...args) => errors.push(args);
  try {
    const stop = keepPanelRendering(renderer, {
      windowRef: handles.windowRef,
      now: () => clock,
    });
    clock = 1000;
    fail = true;
    handles.tick();
    assert.equal(renders, 1);
    // Stopped: the timer waits, and leaves the error to the notice.
    handles.tick();
    assert.equal(renders, 1);
    assert.deepEqual(errors, []);
    // A retry starts the loop again: the timer draws again.
    stopped = false;
    fail = false;
    handles.tick();
    assert.equal(renders, 2);
    stop();
  } finally {
    console.error = error;
  }
});
