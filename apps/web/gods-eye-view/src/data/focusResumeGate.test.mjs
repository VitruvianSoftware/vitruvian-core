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

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyVesselFocusDeemphasis } from './aisLiveVessels.js';
import { applyCctvFocusDeemphasis } from './cctv.js';
import { applySatellitePointFocusDeemphasis } from './satellites.js';
import { DEFAULT_FOCUS_DEEMPHASIS_PARAMS } from './focusDeemphasis.js';

const params = { ...DEFAULT_FOCUS_DEEMPHASIS_PARAMS, paddingPx: 0 };
const target = {
  screenRect: { left: 40, top: 40, right: 60, bottom: 60 },
  paddingPx: 0,
  cameraDistance: 1000,
};

function color(alpha = 1, rgb = 'base') {
  return {
    alpha,
    rgb,
    withAlpha(nextAlpha) {
      return color(nextAlpha, rgb);
    },
  };
}

function assertResumeGate(name, makePass) {
  test(`${name} gate restores a settled dim contact after untrack`, () => {
    const { pass, readAlpha } = makePass();
    let activeCount = 0;
    const tick = (nowMs, focusTarget) => {
      const result = pass({ nowMs, target: focusTarget, previousActiveCount: activeCount });
      activeCount = result.activeCount;
      return result;
    };

    assert.equal(tick(0, target).ran, true);
    const settled = tick(params.attackMs + 1, target);
    assert.equal(settled.activeCount, 1);
    assert.equal(readAlpha(), params.dimFloor);

    const releaseStart = tick(params.attackMs + 1, null);
    assert.equal(releaseStart.ran, true, 'active count keeps the no-target release pass alive');
    assert.equal(releaseStart.activeCount, 1);

    const restored = tick(params.attackMs + params.releaseMs + 2, null);
    assert.equal(restored.ran, true);
    assert.equal(restored.activeCount, 0);
    assert.equal(readAlpha(), 1);

    assert.equal(tick(params.attackMs + params.releaseMs + 82, null).ran, false);
  });
}

assertResumeGate('vessel', () => {
  const billboard = {
    position: { x: 1, y: 2, z: 3 },
    show: true,
    width: 32,
    height: 32,
    scale: 1,
    color: color(),
  };
  return {
    pass: ({ nowMs, target: focusTarget, previousActiveCount }) => (
      applyVesselFocusDeemphasis({
        records: [{ billboard }],
        target: focusTarget,
        previousActiveCount,
        nowMs,
        screenPositionFor: () => ({ x: 50, y: 50 }),
        cameraDistanceFor: () => 1200,
        params,
      })
    ),
    readAlpha: () => billboard.color.alpha,
  };
});

assertResumeGate('CCTV', () => {
  const billboard = {
    position: { x: 1, y: 2, z: 3 },
    show: true,
    width: 24,
    height: 24,
    scale: 1,
    color: color(),
  };
  const record = { camera: { id: 'cam-1' }, billboard };
  return {
    pass: ({ nowMs, target: focusTarget, previousActiveCount }) => (
      applyCctvFocusDeemphasis({
        records: [record],
        target: focusTarget,
        previousActiveCount,
        nowMs,
        screenPositionFor: () => ({ x: 50, y: 50 }),
        cameraDistanceFor: () => 1200,
        baseColorFor: () => color(),
        params,
      })
    ),
    readAlpha: () => billboard.color.alpha,
  };
});

assertResumeGate('satellite', () => {
  const point = {
    position: { x: 1, y: 2, z: 3 },
    show: true,
    pixelSize: 6,
    color: color(),
  };
  return {
    pass: ({ nowMs, target: focusTarget, previousActiveCount }) => (
      applySatellitePointFocusDeemphasis({
        points: new Map([[42, point]]),
        trackedId: null,
        target: focusTarget,
        previousActiveCount,
        nowMs,
        screenPositionFor: () => ({ x: 50, y: 50 }),
        cameraDistanceFor: () => 1200,
        baseColorFor: () => color(),
        params,
      })
    ),
    readAlpha: () => point.color.alpha,
  };
});
