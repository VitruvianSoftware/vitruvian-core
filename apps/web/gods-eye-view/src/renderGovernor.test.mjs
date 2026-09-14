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

import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  installRenderGovernor,
  holdContinuousRender,
  releaseContinuousRender,
  governorRequestRender,
  getRenderGovernorDiagnostics,
  _resetRenderGovernorForTest,
} from './renderGovernor.js';

function makeViewer() {
  const calls = { requestRender: 0 };
  const scene = {
    requestRenderMode: false,
    maximumRenderTimeChange: 0,
    requestRender() { calls.requestRender += 1; },
  };
  return { viewer: { scene }, scene, calls };
}

beforeEach(() => _resetRenderGovernorForTest());

test('install with zero holds enters idle mode and pins maximumRenderTimeChange', () => {
  const { viewer, scene } = makeViewer();
  installRenderGovernor(viewer);
  assert.equal(scene.requestRenderMode, true);
  assert.equal(scene.maximumRenderTimeChange, Infinity);
  assert.equal(getRenderGovernorDiagnostics().mode, 'idle');
});

test('a hold flips to continuous; releasing the last hold returns to idle with a settling frame', () => {
  const { viewer, scene, calls } = makeViewer();
  installRenderGovernor(viewer);
  const settleBaseline = calls.requestRender;
  holdContinuousRender('flights');
  assert.equal(scene.requestRenderMode, false);
  assert.equal(getRenderGovernorDiagnostics().mode, 'continuous');
  releaseContinuousRender('flights');
  assert.equal(scene.requestRenderMode, true);
  // Entering idle renders one settling frame.
  assert.equal(calls.requestRender, settleBaseline + 1);
});

test('holds are identity-keyed: double-hold cannot leak, double-release cannot corrupt', () => {
  const { viewer, scene } = makeViewer();
  installRenderGovernor(viewer);
  holdContinuousRender('traffic');
  holdContinuousRender('traffic');
  releaseContinuousRender('traffic');
  assert.equal(scene.requestRenderMode, true, 'single release clears an idempotent double-hold');
  releaseContinuousRender('traffic');
  releaseContinuousRender('never-held');
  assert.equal(scene.requestRenderMode, true);
});

test('mode stays continuous until the LAST holder releases', () => {
  const { viewer, scene } = makeViewer();
  installRenderGovernor(viewer);
  holdContinuousRender('flights');
  holdContinuousRender('satellites');
  releaseContinuousRender('flights');
  assert.equal(scene.requestRenderMode, false);
  assert.deepEqual(getRenderGovernorDiagnostics().holds, ['satellites']);
  releaseContinuousRender('satellites');
  assert.equal(scene.requestRenderMode, true);
});

test('governorRequestRender forwards to the scene and records reasons only in idle mode', () => {
  const { viewer, calls } = makeViewer();
  installRenderGovernor(viewer);
  const baseline = calls.requestRender;
  governorRequestRender('layer-tick:earthquakes');
  assert.equal(calls.requestRender, baseline + 1);
  assert.equal(getRenderGovernorDiagnostics().recentRequests.at(-1).reason, 'layer-tick:earthquakes');
  holdContinuousRender('flights');
  const idleRequests = getRenderGovernorDiagnostics().recentRequests.length;
  governorRequestRender('slider');
  assert.equal(
    getRenderGovernorDiagnostics().recentRequests.length,
    idleRequests,
    'continuous-mode requests are not recorded as idle diagnostics',
  );
});

test('hold/release/request are safe no-ops before install (test environments without a viewer)', () => {
  holdContinuousRender('flights');
  releaseContinuousRender('flights');
  governorRequestRender('noop');
  assert.equal(getRenderGovernorDiagnostics().installed, false);
});

test('holds registered before install apply at install time', () => {
  holdContinuousRender('flights');
  const { viewer, scene } = makeViewer();
  installRenderGovernor(viewer);
  assert.equal(scene.requestRenderMode, false, 'pre-install hold keeps continuous mode');
  releaseContinuousRender('flights');
  assert.equal(scene.requestRenderMode, true);
});
