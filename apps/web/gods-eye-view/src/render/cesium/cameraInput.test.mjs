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
import { acquireCameraInput } from './cameraInput.js';

test('users of one scene share its holds', () => {
  const controller = { enableInputs: true };
  const scene = { screenSpaceCameraController: controller };
  const a = acquireCameraInput(scene);
  const b = acquireCameraInput(scene);
  const drag = a.suspend('drag');
  assert.equal(controller.enableInputs, false);
  assert.equal(b.enabled, false, 'b sees a’s hold');
  assert.deepEqual(b.reasons(), ['drag']);
  const flight = b.suspend(7);
  assert.deepEqual(a.reasons(), ['drag', '7']);
  drag();
  assert.equal(controller.enableInputs, false, 'b’s hold is still out');
  a.release();
  assert.equal(controller.enableInputs, false, 'b still holds');
  flight();
  assert.equal(controller.enableInputs, true);
});

test('releasing a user gives back its holds, and the property with the last', () => {
  const controller = { enableInputs: true };
  const scene = { screenSpaceCameraController: controller };
  const a = acquireCameraInput(scene);
  const b = acquireCameraInput(scene);
  a.suspend('drag');
  b.suspend('cockpit');
  a.release();
  assert.deepEqual(b.reasons(), ['cockpit']);
  assert.equal(
    typeof Object.getOwnPropertyDescriptor(controller, 'enableInputs').get,
    'function',
    'still owned while b is a user',
  );
  b.release();
  assert.deepEqual(
    Object.getOwnPropertyDescriptor(controller, 'enableInputs'),
    {
      value: true,
      writable: true,
      enumerable: true,
      configurable: true,
    },
  );
  assert.deepEqual(
    a.suspend('late')(),
    undefined,
    'a released user holds nothing',
  );
  const c = acquireCameraInput(scene);
  assert.equal(c.enabled, true, 'a new user starts afresh');
  c.release();
});
