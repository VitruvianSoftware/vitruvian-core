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
import { createPanel } from './panel.js';

test('rendering a selected mission resets the nearest theme-appropriate Context scroller', () => {
  for (const cyber of [true, false]) {
    const body = { scrollTop: 180 };
    const inner = { scrollTop: 90 };
    const output = { closest: () => null, removeAttribute() {} };
    const state = {
      _missionPanel: {
        querySelector: () => output,
        closest(selector) {
          assert.equal(selector, ":root[data-ui-theme='cyber'] .cyber-panel-body, .global-context-panel-inner");
          return cyber ? body : inner;
        },
      },
      _selectedLaunchId: 'mission-1',
      _launches: [{ id: 'mission-1', name: 'Example', payloads: [], recoveryStages: [] }],
      _replayTracks: new Map(),
    };
    const panel = createPanel({
      state,
      parts: {
        overlays: { shortMissionLabel: (name) => name },
        policyHelpers: { missionPathPresentation: () => ({}) },
        replay: { syncReplayButton() {} },
      },
    });
    panel.renderMissionPanel();
    assert.equal(body.scrollTop, cyber ? 0 : 180);
    assert.equal(inner.scrollTop, cyber ? 90 : 0);
  }
});
