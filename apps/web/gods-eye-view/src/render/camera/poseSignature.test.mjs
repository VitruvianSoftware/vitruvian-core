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

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { cameraPoseSignature } from '../cesium/iconOrientation.js';
import { poseSignature } from './poseSignature.js';

const pose = {
  position: { x: 3_975_123.4, y: 289_456.7, z: 4_998_765.1 },
  heading: 1.23456,
  pitch: -0.7071,
  roll: 0.0004,
};

test('the pose key holds the eye to 10 m and its angles to a milliradian', () => {
  assert.equal(poseSignature(pose), '397512:28946:499877:1.235:-0.707:0.000');
  const near = {
    ...pose,
    position: { ...pose.position, x: pose.position.x + 1 },
    heading: pose.heading + 0.0003,
  };
  assert.equal(poseSignature(near), poseSignature(pose), 'too small to move');
  assert.notEqual(
    poseSignature({ ...pose, pitch: pose.pitch + 0.002 }),
    poseSignature(pose),
  );
});

test('a Cesium camera keys the same as the pose it reads', () => {
  const camera = {
    positionWC: pose.position,
    heading: pose.heading,
    pitch: pose.pitch,
    roll: pose.roll,
  };
  assert.equal(cameraPoseSignature(camera), poseSignature(pose));
});

test('the pose key imports no renderer', () => {
  const source = readFileSync(
    new URL('./poseSignature.js', import.meta.url),
    'utf8',
  );
  assert.doesNotMatch(source, /from 'cesium'/);
});
