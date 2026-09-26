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

import { selectModelEligible } from './modelEligibility.js';

const ADD_SQ = 100 * 100;

test('visible contacts win the cap before off-screen retained models', () => {
  // Nearest first: an off-screen retained model, then two on-screen contacts.
  const candidates = [
    ['off-kept', 10, false],
    ['on-new', 20, true],
    ['on-kept', 30, true],
  ];
  const modeled = new Set(['off-kept', 'on-kept']);
  const eligible = selectModelEligible(candidates, {
    cap: 2,
    addDistSq: ADD_SQ,
    isModeled: (id) => modeled.has(id),
  });
  assert.deepEqual([...eligible], ['on-kept', 'on-new']);
});

test('retained models keep their slot beyond the add radius; new ones do not', () => {
  const candidates = [
    ['near-new', 50, true],
    ['far-kept', ADD_SQ + 1, true],
    ['far-new', ADD_SQ + 2, true],
    ['off-new', 60, false],
  ];
  const eligible = selectModelEligible(candidates, {
    cap: 10,
    addDistSq: ADD_SQ,
    isModeled: (id) => id === 'far-kept',
  });
  assert.deepEqual([...eligible], ['far-kept', 'near-new', 'off-new']);
});

test('an empty cap admits nothing', () => {
  assert.equal(
    selectModelEligible([['a', 1, true]], {
      cap: 0,
      addDistSq: ADD_SQ,
      isModeled: () => true,
    }).size,
    0,
  );
});
