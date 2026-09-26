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
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  joinGroundHeights,
  loadGroundHeights,
} from '../../server/providers/cctv/groundHeights.js';
import { poseHash } from './cctvFootprint.js';

const source = (over = {}) => ({
  id: 'cam-1',
  lat: 30.2672,
  lon: -97.7431,
  headingDeg: 90,
  pitchDeg: -24,
  fovDeg: 56,
  rangeM: 210,
  mountHeightM: 12,
  ...over,
});

test('a shipped entry attaches only while the nominal pose still matches', () => {
  const s = source();
  const entry = {
    status: 'ok',
    poseHash: poseHash(s),
    mountGroundM: 151.2,
    supports: { bl: 150.1, bm: 149.9, br: 155.5, tl: null, tm: 'x' },
  };
  const [joined] = joinGroundHeights([s], { 'cam-1': entry });
  assert.deepEqual(joined.groundHeights, {
    poseHash: entry.poseHash,
    mountGroundM: 151.2,
    supports: { bl: 150.1, bm: 149.9, br: 155.5 },
  });

  const moved = source({ lat: 30.2673 });
  const [notJoined] = joinGroundHeights([moved], { 'cam-1': entry });
  assert.equal(
    notJoined.groundHeights,
    undefined,
    'a moved camera loses the shipped value',
  );

  const [missed] = joinGroundHeights([source()], {
    'cam-1': { ...entry, status: 'miss', mountGroundM: null },
  });
  assert.equal(missed.groundHeights, undefined, 'a miss ships nothing');
  assert.deepEqual(
    joinGroundHeights([source()], null)[0].groundHeights,
    undefined,
  );
});

test('the sidecar loads from the source root and tolerates a missing or malformed file', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'gev-heights-'));
  fs.mkdirSync(
    path.join(dir, 'src', 'data', 'local_data', 'cctv_ground_heights'),
    {
      recursive: true,
    },
  );
  assert.deepEqual(loadGroundHeights(dir), {}, 'missing file');
  const file = path.join(
    dir,
    'src',
    'data',
    'local_data',
    'cctv_ground_heights',
    'cctv_ground_heights.json',
  );
  fs.writeFileSync(file, '{not json');
  assert.deepEqual(loadGroundHeights(dir), {}, 'malformed file');
  fs.writeFileSync(
    file,
    JSON.stringify({ schemaVersion: 1, cameras: { a: { status: 'ok' } } }),
  );
  assert.deepEqual(loadGroundHeights(dir), { a: { status: 'ok' } });
});
