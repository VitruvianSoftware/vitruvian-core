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
import { createState } from './state.js';
import { createReplay } from './replay.js';
import { createPaths } from './paths.js';

const noop = () => {};

function replayRig() {
  const state = createState({
    services: {
      overlays: {
        setOverlayEntries: noop,
        setOverlaySourceVisible: noop,
        clearOverlaySource: noop,
      },
    },
  });
  const parts = { panel: { publishPanel: noop } };
  parts.paths = createPaths({ state, parts });
  return { state, replay: createReplay({ state, parts }) };
}

test('changing replay speed during the countdown keeps its real-time liftoff', (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: 1_000_000 });
  const { state, replay } = replayRig();
  const launch = { launchTime: '2026-07-20T10:00:00Z', timeline: [] };
  state._animationStarts.set('countdown', 1_008_000); // T-8
  state._animationStarts.set('flying', 990_000); // 10 s into the mission

  replay.setReplaySpeed(0.25);

  const startedAt = state._animationStarts.get('countdown');
  assert.equal(startedAt, 1_008_000);
  const countdown = replay.replayState(
    launch,
    startedAt,
    12,
    28,
    5400,
    state._replaySpeed,
    Date.now(),
  );
  assert.equal(countdown.countdownSeconds, 8);
  // Mission time already flown is still preserved across the change.
  assert.equal(state._animationStarts.get('flying'), 960_000);
});
