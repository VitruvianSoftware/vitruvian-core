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
import { MapStackController } from '../mapStackController.js';
import {
  installRenderGovernor,
  uninstallRenderGovernor,
  holdContinuousRender,
  governorRequestRender,
  getRenderGovernorDiagnostics,
} from '../renderGovernor.js';

test('destroy invalidates a pending imagery provider before it can touch the viewer', async () => {
  let resolveProvider;
  let removed = 0;
  const changes = [];
  const controller = new MapStackController(
    {},
    { onChange: (state) => changes.push(state.status) },
  );
  controller._getImageryProvider = () =>
    new Promise((resolve) => {
      resolveProvider = resolve;
    });
  controller._removeImageryErrorListener = () => {
    removed++;
  };
  const switching = controller.setStack('osm');
  controller.destroy();
  resolveProvider({ provider: {} });
  await switching;
  assert.equal(removed, 1);
  assert.deepEqual(changes, ['switching']);
  await controller.setStack('osm');
  controller.destroy();
  assert.equal(removed, 1);
});

test('uninstall only releases the current viewer and makes later render requests inactive', () => {
  let renders = 0;
  const viewer = {
    scene: {
      requestRender: () => {
        renders++;
      },
    },
  };
  installRenderGovernor(viewer);
  holdContinuousRender('fixture');
  uninstallRenderGovernor({});
  assert.equal(getRenderGovernorDiagnostics().installed, true);
  uninstallRenderGovernor(viewer);
  const before = renders;
  governorRequestRender('late');
  assert.equal(renders, before);
  assert.equal(getRenderGovernorDiagnostics().installed, false);
  assert.deepEqual(getRenderGovernorDiagnostics().holds, []);
});
