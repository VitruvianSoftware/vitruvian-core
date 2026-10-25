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

import test from 'node:test';
import assert from 'node:assert/strict';
import { createAnimation } from './animation.js';

test('traffic render demand follows animated population and jam lines across empty, disable and re-enable', () => {
  const calls = [];
  const state = { _enabled: true, _dots: [], _motion: { rebuilds: 0 } };
  const animation = createAnimation({
    state,
    services: {
      render: {
        holdContinuousRender: (id) => calls.push(['hold', id]),
        releaseContinuousRender: (id) => calls.push(['release', id]),
      },
    },
    parts: {
      retention: { clear() {} },
      rendering: {
        removeHeatLines() {
          state._heatJamPrim = null;
        },
      },
    },
  });
  animation.syncRenderDemand();
  assert.deepEqual(calls, []);
  state._dots.push({});
  animation.syncRenderDemand();
  animation.syncRenderDemand();
  assert.deepEqual(calls, [['hold', 'traffic']]);
  animation.clearDots();
  assert.deepEqual(calls.at(-1), ['release', 'traffic']);
  state._heatJamPrim = {};
  animation.syncRenderDemand();
  assert.deepEqual(calls.at(-1), ['hold', 'traffic']);
  state._enabled = false;
  animation.syncRenderDemand();
  assert.deepEqual(calls.at(-1), ['release', 'traffic']);
  state._enabled = true;
  animation.clearDots();
  assert.equal(state._renderHeld, false);
  state._dots.push({});
  animation.syncRenderDemand();
  assert.equal(state._renderHeld, true);
});
