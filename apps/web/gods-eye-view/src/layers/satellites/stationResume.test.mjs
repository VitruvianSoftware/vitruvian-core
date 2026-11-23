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

// src/layers/satellites/stationResume.test.mjs — handing a station's moving
// parts back from the STATION section's Manual: every joint posed by hand
// leaves its manual angle, the ones the illustrative sway does not move
// included, and the ISS's Automatic lets telemetry back in.
import assert from 'node:assert/strict';
import test from 'node:test';
import { createIssArticulation, ISS_ARM_JOINTS } from './issArticulation.js';
import { issStationDescription } from './issStation.js';
import { createNodePoses } from './stationModel.js';
import {
  createTiangongArticulation,
  TIANGONG_ARMS,
} from './tiangongArticulation.js';

/** A station on its usual axes, in sunlight, as the model part places it. */
const AT = { x: 6_780_000, y: 0, z: 0 };
const AXES = { x: [0, 1, 0], y: [0, 0, 1], z: [1, 0, 0] };
const DATE = new Date(Date.UTC(2026, 10, 16, 12, 0, 0));

test('ISS: Resume gives the Canadarm2 joints the sway does not move their filed pose back', () => {
  const articulation = createIssArticulation();
  const nodes = createNodePoses();
  articulation.update(nodes, DATE, AT, AXES, 1_000);
  const held = ISS_ARM_JOINTS.filter((joint) => !joint.sway);
  const swaying = ISS_ARM_JOINTS.find((joint) => joint.sway);
  assert.ok(held.length > 0 && swaying);
  for (const joint of [...held, swaying])
    articulation.setJoint(joint.node, joint.pivot, joint.axis, Math.PI / 2);
  for (const joint of held) assert.ok(nodes.poses[joint.node], joint.node);
  articulation.resumeArm();
  for (const joint of held)
    assert.equal(
      nodes.poses[joint.node],
      undefined,
      `${joint.node} back to its filed pose`,
    );
  // A swaying joint is posed by the sway again on the next update.
  articulation.update(nodes, DATE, AT, AXES, 2_000);
  assert.ok(nodes.poses[swaying.node]);
});

test('Tiangong: resuming an arm gives its held joints their folded pose back, and only that arm', () => {
  const articulation = createTiangongArticulation();
  const nodes = createNodePoses();
  articulation.update(nodes, DATE, AT, AXES, 1_000);
  const heldOf = (key) =>
    TIANGONG_ARMS[key].filter((joint) => !joint.sway && !joint.centre);
  for (const key of ['cmm', 'emm'])
    for (const joint of heldOf(key))
      articulation.setJoint(joint.node, joint.pivot, joint.axis, 1);
  articulation.resumeArm('cmm');
  for (const joint of heldOf('cmm'))
    assert.equal(nodes.poses[joint.node], undefined, joint.node);
  for (const joint of heldOf('emm'))
    assert.ok(nodes.poses[joint.node], `${joint.node} still by hand`);
  articulation.resumeArm();
  for (const joint of heldOf('emm'))
    assert.equal(nodes.poses[joint.node], undefined, joint.node);
});

test('a node given no matrix leaves the item’s nodes, as a model node goes back to its authored pose', () => {
  const nodes = createNodePoses();
  const identity = new Float64Array(16);
  identity[0] = identity[5] = identity[10] = identity[15] = 1;
  nodes.getNode('JOINT').matrix = identity;
  assert.ok(nodes.poses.JOINT);
  nodes.getNode('JOINT').matrix = undefined;
  assert.equal('JOINT' in nodes.poses, false);
});

test("the ISS's Automatic lets telemetry back in and hands every part back", () => {
  const calls = [];
  const recorder = new Proxy(
    {},
    {
      get:
        (_, name) =>
        (...args) =>
          calls.push([name, ...args]),
    },
  );
  const station = issStationDescription({ state: {}, parts: {} });
  station.automatic(recorder);
  const names = calls.map(([name]) => name);
  assert.deepEqual(
    calls.find(([name]) => name === 'setTelemetryAllowed'),
    ['setTelemetryAllowed', true],
  );
  for (const name of [
    'setOverride',
    'setDishOverride',
    'setDeploy',
    'setRadiatorDeploy',
    'resumeArm',
  ])
    assert.ok(names.includes(name), name);
});
