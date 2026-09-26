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
import { createFrameRateMonitor } from './frameRateMonitor.js';

function fixture(t) {
  const keys = new Set();
  const frames = new Set();
  let readout;
  const documentRef = {
    hidden: false,
    getElementById: () => ({
      appendChild: (node) => {
        readout = node;
      },
    }),
    createElement: () => ({
      remove() {
        this.removed = true;
      },
    }),
    addEventListener: (name, handler) => keys.add(handler),
    removeEventListener: (name, handler) => keys.delete(handler),
  };
  const viewer = {
    scene: {
      postRender: {
        addEventListener(handler) {
          frames.add(handler);
          return () => frames.delete(handler);
        },
      },
    },
  };
  const monitor = createFrameRateMonitor({ viewer, documentRef });
  t.after(() => monitor.destroy());
  return {
    monitor,
    documentRef,
    frames,
    keys,
    readout: () => readout,
    press(options = {}) {
      const event = {
        key: '`',
        preventDefault() {
          this.defaultPrevented = true;
        },
        ...options,
      };
      for (const handler of keys) handler(event);
      return event;
    },
  };
}

test('FPS measures rendered frames only while shown and releases its resources', (t) => {
  t.mock.timers.enable({ apis: ['setInterval'] });
  let now = 0;
  t.mock.method(performance, 'now', () => now);
  const f = fixture(t);
  assert.equal(f.readout().hidden, true);
  assert.equal(f.frames.size, 0);
  assert.equal(f.press().defaultPrevented, true);
  assert.equal(f.frames.size, 1);
  for (let frame = 0; frame < 30; frame++)
    for (const render of f.frames) render();
  now = 1000;
  t.mock.timers.tick(1000);
  assert.equal(f.readout().textContent, 'FPS 30');
  now = 2000;
  t.mock.timers.tick(1000);
  assert.equal(
    f.readout().textContent,
    'FPS 0',
    'idle rendering is not reported as display refresh rate',
  );
  f.press();
  assert.equal(f.readout().hidden, true);
  assert.equal(f.frames.size, 0);
  now = 3000;
  t.mock.timers.tick(1000);
  f.press();
  assert.equal(f.readout().textContent, 'FPS —');
  f.monitor.destroy();
  f.monitor.destroy();
  assert.equal(f.frames.size, 0);
  assert.equal(f.keys.size, 0);
  assert.equal(f.readout().removed, true);
});

test('typing, modified keys, composition and repeated presses do not toggle FPS', (t) => {
  const f = fixture(t);
  for (const options of [
    { target: { closest: () => ({}) } },
    { target: { isContentEditable: true } },
    { ctrlKey: true },
    { altKey: true },
    { metaKey: true },
    { shiftKey: true },
    { repeat: true },
    { isComposing: true },
    { defaultPrevented: true },
    { key: 'a' },
  ]) {
    f.press(options);
    assert.equal(f.readout().hidden, true);
    assert.equal(f.frames.size, 0);
  }
});
