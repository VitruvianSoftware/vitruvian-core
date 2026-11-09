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
import { CCTV_ACTIVATION_RESULT } from '../../cctvFocusRequest.js';
import { createSelection } from './selection.js';

function makeSelection(sourceKind) {
  const camera = { id: 'same-camera', sourceKind };
  const record = { camera };
  const state = {
    _activeCameraId: camera.id,
    _activeCameraReselection: 0,
    _recordById: new Map([[camera.id, record]]),
  };
  let notifications = 0;
  const selection = createSelection({
    state,
    services: {
      activation: { CCTV_ACTIVATION_RESULT },
      picking: { resolvePickId: () => null },
    },
    parts: {
      model: {
        cctvRecordNeedsActivation: () => false,
        isBrowserOverlayCamera: (value) =>
          String(value?.sourceKind || '').startsWith('quebec-'),
      },
      presentation: { notifyListeners: () => notifications++ },
    },
    source: {},
  });
  return { selection, state, notifications: () => notifications };
}

test('same-camera selection does not notify or mutate snapshot-feed state', () => {
  const fixture = makeSelection('tripcheck-odot');

  assert.equal(
    fixture.selection.setActiveCamera('same-camera'),
    CCTV_ACTIVATION_RESULT.UNCHANGED,
  );
  assert.equal(fixture.state._activeCameraReselection, 0);
  assert.equal(fixture.notifications(), 0);
});

test('same-camera selection notifies browser-overlay feeds so playback can retry', () => {
  const fixture = makeSelection('quebec-511-browser');

  assert.equal(
    fixture.selection.setActiveCamera('same-camera'),
    CCTV_ACTIVATION_RESULT.UNCHANGED,
  );
  assert.equal(fixture.state._activeCameraReselection, 1);
  assert.equal(fixture.notifications(), 1);
});
