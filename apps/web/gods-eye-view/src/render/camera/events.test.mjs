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
import test from 'node:test';
import { createCameraEvents, MOVE_END_WAIT_MS } from './events.js';
import { geodesicAt, horizonFrom } from '../../geo/index.js';

const view = (x) => ({
  position: { x, y: 0, z: 0 },
  direction: { x: -1, y: 0, z: 0 },
  up: { x: 0, y: 0, z: 1 },
});

test('moveStart on a change, moveEnd once nothing moved for 500 ms', () => {
  let eye = view(7e6);
  const seen = [];
  const events = createCameraEvents({
    pose: () => eye,
    world: () => eye,
    report: (error) => assert.fail(error),
  });
  events.on('moveStart', () => seen.push('start'));
  events.on('moveEnd', () => seen.push('end'));
  events.stepMoveDetection(0);
  eye = view(7e6 + 1);
  events.stepMoveDetection(16);
  assert.deepEqual(seen, ['start']);
  events.stepMoveDetection(16 + MOVE_END_WAIT_MS - 1);
  assert.deepEqual(seen, ['start']);
  // A later change starts the wait again, and moveStart is not repeated.
  eye = view(7e6 + 2);
  events.stepMoveDetection(400);
  events.stepMoveDetection(16 + MOVE_END_WAIT_MS);
  assert.deepEqual(seen, ['start']);
  events.stepMoveDetection(400 + MOVE_END_WAIT_MS - 1);
  assert.deepEqual(seen, ['start']);
  events.stepMoveDetection(400 + MOVE_END_WAIT_MS);
  assert.deepEqual(seen, ['start', 'end']);
});

test('command hooks run before each command, each registration on its own', () => {
  const events = createCameraEvents({ pose: () => view(1), report() {} });
  const seen = [];
  const hook = (c) => seen.push(c.kind);
  const offFirst = events.onCommand(hook);
  events.onCommand(hook);
  events.command('setView');
  assert.deepEqual(seen, ['setView', 'setView']);
  offFirst();
  offFirst();
  events.command('flyTo');
  assert.deepEqual(seen, ['setView', 'setView', 'flyTo'], 'one twin is left');
  // A hook removed by an earlier one in the same delivery does not run.
  const order = [];
  const removing = createCameraEvents({ pose: () => view(1), report() {} });
  let offSecond = null;
  removing.onCommand(() => {
    order.push('first');
    offSecond();
  });
  offSecond = removing.onCommand(() => order.push('second'));
  removing.command('setView');
  removing.command('setView');
  assert.deepEqual(order, ['first', 'first']);
  const reported = [];
  const throwing = createCameraEvents({
    pose: () => view(1),
    report: (error) => reported.push(error.message),
  });
  throwing.onCommand(() => {
    throw new Error('boom');
  });
  throwing.onCommand(() => seen.push('after'));
  throwing.command('flyTo');
  assert.deepEqual(reported, ['boom']);
  assert.equal(seen.at(-1), 'after');
});

test('the geo export has the geodesic point and the horizon test', () => {
  const half = geodesicAt(0, 0, Math.PI / 2, 0, 0.5);
  assert.ok(Math.abs(half.lon - Math.PI / 4) < 1e-12);
  assert.ok(Math.abs(half.lat) < 1e-12);
  const horizon = horizonFrom({ x: 7e6, y: 0, z: 0 });
  assert.equal(horizon.isPointVisible({ x: 6378137, y: 0, z: 0 }), true);
  assert.equal(horizon.isPointVisible({ x: -6378137, y: 0, z: 0 }), false);
});
