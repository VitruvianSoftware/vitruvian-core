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
import { fromDegrees } from '../../geo/ellipsoid.js';
import { distance } from '../../geo/vector.js';
import {
  addCellCamera,
  createCameraCell,
  mergeCountCells,
} from '../../data/cctvCellCounts.js';
import { createNavigation } from './navigation.js';

// A count of four merged in a tilted view: two pairs 10 km and 40 km north of
// an eye 800 m up. After the click, at least one member must be in frame.
test('a count click from a tilted view keeps the group members in the frame', () => {
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
    const metresPerDegree = 111_320;
    const members = [];
    const cells = [10_000, 40_000].map((start) => {
      const cell = createCameraCell(String(start));
      for (const northM of [start, start + 10]) {
        const lat = northM / metresPerDegree;
        addCellCamera(cell, { lat, lon: 0, absoluteHeightM: 8 });
        members.push(fromDegrees(0, lat, 8));
      }
      return cell;
    });
    const screens = [
      { x: 400, y: 300 },
      { x: 433, y: 300 },
    ];
    const groups = mergeCountCells(
      cells,
      () => screens.shift(),
      () => ({ width: 40, height: 40 }),
      2,
    );
    assert.equal(groups.length, 1);
    assert.equal(groups[0].count, 4);
    const state = { _viewer: viewer };
    const navigation = createNavigation({ state, parts: {} });
    navigation.zoomToCell(groups[0]);
    assert.equal(flights.length, 1);
    const { range, pitch } = flights[0].options.offset;
    assert.equal(pitch, -Math.PI / 2);
    const { center } = flights[0].bounds;
    const halfSpanM = range * Math.tan(fovy / 2);
    assert.ok(
      members.some((point) => distance(point, center) <= halfSpanM),
      'no member of the group is in the final frame',
    );
    assert.ok(range < distance(fromDegrees(0, 0, 800), center));
  } finally {
    unbind();
  }
});
