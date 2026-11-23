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
import { bindRenderer } from '../../render/rendererOf.js';
import { fromDegrees, toLonLatH } from '../../geo/ellipsoid.js';
import {
  addCellCamera,
  createCameraCell,
  mergeCountCells,
} from '../../data/cctvCellCounts.js';
import { createNavigation } from './navigation.js';

const M = 111_320;

// A count of 40 cameras 40 km north of an eye 800 m up takes in a lone camera
// 10 km north that is drawn just below it. The click must not land on the lone
// camera alone: at least one of the 40 counted cameras must be in the frame.
test('a count click does not fly to a lone camera that joined the count', () => {
  const viewer = {};
  const flights = [];
  const fovy = Math.PI / 3;
  const aspectRatio = 800 / 600;
  const unbind = bindRenderer(viewer, {
    camera: {
      pose: () => ({ fovy, aspectRatio, position: fromDegrees(0, 0, 800) }),
      flyToBounds: (bounds, options) => flights.push({ bounds, options }),
    },
    canvas: { clientHeight: 600, clientWidth: 800 },
  });
  try {
    const crowd = createCameraCell('crowd');
    const counted = [];
    for (let i = 0; i < 40; i++) {
      const lat = (40_000 + i / 4) / M;
      addCellCamera(crowd, { lat, lon: 0, absoluteHeightM: 8 });
      counted.push(lat);
    }
    const lone = createCameraCell('lone');
    addCellCamera(lone, { lat: 10_000 / M, lon: 0, absoluteHeightM: 8 });
    const screens = [
      { x: 400, y: 300 },
      { x: 400, y: 330 },
    ];
    const groups = mergeCountCells(
      [crowd, lone],
      () => screens.shift(),
      (count) =>
        count > 1 ? { width: 40, height: 40 } : { width: 24, height: 24 },
      2,
    );
    assert.equal(groups.length, 1);
    assert.equal(groups[0].count, 41);
    createNavigation({ state: { _viewer: viewer }, parts: {} }).zoomToCell(
      groups[0],
    );
    assert.equal(flights.length, 1);
    const { range } = flights[0].options.offset;
    const center = toLonLatH(flights[0].bounds.center);
    const halfY = range * Math.tan(fovy / 2);
    const inFrame = counted.filter(
      (lat) => Math.abs((lat - center.lat) * M) <= halfY,
    );
    assert.ok(
      inFrame.length > 0,
      `none of the 40 counted cameras is in the frame (range ${Math.round(range)} m, centre ${Math.round(center.lat * M)} m north)`,
    );
  } finally {
    unbind();
  }
});
