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

import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import '../testSupport/stubMgrs.mjs';
import { installVueDom } from '../testSupport/vueDom.mjs';
import { bindFakeCesiumCamera } from '../testSupport/fakeCameraPort.mjs';

const { createApplicationControls } = await import('./controls.js');

let uninstallDom;
before(() => {
  uninstallDom = installVueDom();
});
after(() => uninstallDom());

test('the application controls start and stop', () => {
  class Controls {
    hasShareState = true;
    orbitController = { stop() {} };
    hud = { destroy() {} };
    dispose() {}
  }
  const cleanups = [];
  createApplicationControls({
    scene: {
      viewer: bindFakeCesiumCamera({
        isDestroyed: () => false,
        camera: { setView() {} },
      }),
      mapStackController: {},
      operations: {
        surface: { controlServices: {} },
        searchAndFlyTo() {},
        requests: { regional: {}, weather: {} },
      },
    },
    loaderStatus: {},
    Controls,
    catalog: { get: (id) => ({ id }) },
    defer: (cleanup) => cleanups.push(cleanup),
  });
  for (const cleanup of cleanups.reverse()) cleanup();
});
