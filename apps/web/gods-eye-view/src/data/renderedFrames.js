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

/**
 * @module data/renderedFrames
 * @description How many frames a viewer's renderer has drawn: a key that
 * changes once per drawn frame, after it is drawn, for per-frame caches.
 * Everything that reads a cache keyed by it in one tick (the follow camera,
 * the frame's `preUpdate` and `preRender` work, the readouts in its
 * `postRender`) sees one value; a tick that draws nothing keeps the key, as
 * the default renderer's own frame number does.
 */
import { findFrame } from '../render/rendererOf.js';

/** Per frame port: `{count}`, counted on its `postRender`. */
const counters = new WeakMap();

/**
 * The number of frames drawn so far on `viewer`'s frame port, or -1 when it
 * has none. Counting starts on the first call.
 * @param {object|null|undefined} viewer
 * @returns {number}
 */
export function renderedFrames(viewer) {
  const frame = viewer ? findFrame(viewer) : null;
  if (!frame) return -1;
  let counter = counters.get(frame);
  if (!counter) {
    counter = { count: 0 };
    counters.set(frame, counter);
    frame.on('postRender', () => {
      counter.count += 1;
    });
  }
  return counter.count;
}
