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
import * as Cesium from 'cesium';
import '../testSupport/stubMgrs.mjs';
import { installVueDom } from '../testSupport/vueDom.mjs';
import { MAXIMUM_ZOOM_DISTANCE_M } from './zoomOutGuard.js';

const { createApplicationControls } = await import('./controls.js');

let uninstallDom;
before(() => {
  uninstallDom = installVueDom();
});
after(() => uninstallDom());

test('application controls install the zoom-out guard and remove it on teardown', () => {
  const canvas = document.createElement('canvas');
  const controller = { maximumZoomDistance: Infinity };
  const scene = {
    mode: Cesium.SceneMode.SCENE3D,
    screenSpaceCameraController: controller,
    preRender: new Cesium.Event(),
    postUpdate: new Cesium.Event(),
  };
  const camera = {
    position: Cesium.Cartesian3.fromDegrees(0, 0, 1_000_000),
    positionCartographic: { height: 1_000_000 },
  };
  const viewer = { scene, camera, canvas };
  const handoffs = new Set();
  class Controls {
    hasShareState = true;
    orbitController = { stop() {} };
    hud = { destroy() {} };
    dispose() {}
    subscribeCameraHandoff(listener) {
      handoffs.add(listener);
      return () => handoffs.delete(listener);
    }
  }
  const cleanups = [];
  createApplicationControls({
    scene: {
      viewer,
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

  assert.equal(controller.maximumZoomDistance, MAXIMUM_ZOOM_DISTANCE_M);
  assert.equal(scene.preRender.numberOfListeners, 1);
  assert.equal(scene.postUpdate.numberOfListeners, 1);
  assert.equal(handoffs.size, 1);

  for (const cleanup of cleanups.reverse()) cleanup();
  assert.equal(controller.maximumZoomDistance, Infinity);
  assert.equal(scene.preRender.numberOfListeners, 0);
  assert.equal(scene.postUpdate.numberOfListeners, 0);
  assert.equal(handoffs.size, 0);
});
