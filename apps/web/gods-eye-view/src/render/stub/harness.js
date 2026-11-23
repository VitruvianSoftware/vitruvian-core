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
 * @module render/stub/harness
 * @description The stub as the conformance suite's renderer under test, for
 * the Node test and the browser page alike.
 */
import { DEFAULT_TOLERANCE } from '../conformance/index.js';
import { createStubRenderer, STUB_FAILING_MODEL_SCHEME } from './index.js';
import { toEcef } from './math.js';

/** @returns {import('../conformance/index.js').ConformanceHarness} */
export function createStubHarness(name = 'stub') {
  // Each renderer's container: a stand-in that says its size, which the
  // stub's `resize` follows.
  const containers = new WeakMap();
  return {
    name,
    create: async ({ viewport, capabilities }) => {
      const container = {
        clientWidth: viewport.width,
        clientHeight: viewport.height,
      };
      const r = createStubRenderer({ viewport, capabilities, container });
      containers.set(r, container);
      return r;
    },
    resizeContainer: (r, { width, height }) => {
      const container = containers.get(r);
      if (!container) return;
      container.clientWidth = width;
      container.clientHeight = height;
    },
    frame: (r) => {
      r.testing.tick();
    },
    now: (r) => r.testing.now(),
    toEcef,
    tolerance: DEFAULT_TOLERANCE,
    flightPaths: 'trace',
    // It draws only models into pixels.
    pixels: false,
    pointer: (r, type, x, y, extra) => r.testing.pointer(type, x, y, extra),
    scriptHeights: (r, fn) => r.testing.setHeights(fn),
    wallTime: (r) => r.testing.wallTime(),
    // The stub loads nothing: any url is a model it draws, but one under
    // its failing scheme.
    assets: {
      model: 'stub:model.glb',
      // A stub model is one node, named after its file.
      modelNode: 'model',
      missingModel: `${STUB_FAILING_MODEL_SCHEME}model.glb`,
      // Any bytes: the stub parses none.
      modelBytes: async () => new Uint8Array([0x67, 0x6c, 0x54, 0x46]),
    },
  };
}
