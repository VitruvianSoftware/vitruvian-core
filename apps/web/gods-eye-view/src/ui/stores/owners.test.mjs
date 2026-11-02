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

// src/ui/stores/owners.test.mjs — the newest connected owner with an action
// answers it; detaching hands the action back to the one before.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createOwners } from './owners.js';

test('the newest owner with an action answers it, and detach hands it back', () => {
  const { connect, detach, act } = createOwners();
  const calls = [];
  const first = connect({
    play: (n) => calls.push(['first.play', n]),
    stop: () => calls.push(['first.stop']),
  });
  const second = connect({ play: (n) => calls.push(['second.play', n]) });
  act('play', 1);
  act('stop');
  act('missing');
  detach(second);
  act('play', 2);
  detach(second);
  detach(first);
  act('play', 3);
  assert.deepEqual(calls, [
    ['second.play', 1],
    ['first.stop'],
    ['first.play', 2],
  ]);
});

test('act returns what the answering action returned', () => {
  const { connect, act } = createOwners();
  connect({ pick: (tag) => `kept ${tag}` });
  assert.equal(act('pick', 'jazz'), 'kept jazz');
  assert.equal(act('missing'), undefined);
});

test('owns names the owner that answers an action', () => {
  const { connect, detach, owns } = createOwners();
  const older = connect({ tilt() {}, share() {} });
  const newer = connect({ tilt() {} });
  assert.equal(owns(newer, 'tilt'), true);
  assert.equal(owns(older, 'tilt'), false);
  assert.equal(owns(older, 'share'), true);
  assert.equal(owns(newer, 'missing'), false);
  assert.equal(owns(null, 'tilt'), false);
  detach(newer);
  assert.equal(owns(older, 'tilt'), true);
});

test('ownerOf names the token that answers an action', () => {
  const { connect, ownerOf } = createOwners();
  const older = connect({ clear() {}, share() {} });
  const newer = connect({ clear() {} });
  assert.equal(ownerOf('clear'), newer);
  assert.equal(ownerOf('share'), older);
  assert.equal(ownerOf('missing'), undefined);
});
