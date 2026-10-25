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

// A launch without a Launch Library status gets our 'Unknown'. The record keeps
// it English; the mission panel translates it and shows provider statuses as sent.
import assert from 'node:assert/strict';
import test from 'node:test';
import { setLocale } from '../../i18n/index.js';
import {
  launchStatusAllowsOrbit,
  normalizeRocketLaunches,
} from '../../data/rocketLaunches.js';
import { UNKNOWN_LAUNCH_STATUS } from './model.js';
import { createPanel } from './panel.js';

const NOW = new Date('2026-07-27T00:00:00Z');

function shownStatus(status) {
  const outputs = new Map();
  const state = {
    _missionPanel: {
      querySelector(selector) {
        if (!outputs.has(selector))
          outputs.set(selector, {
            textContent: '',
            closest: () => null,
            removeAttribute() {},
          });
        return outputs.get(selector);
      },
      closest: () => null,
    },
    _selectedLaunchId: 'mission-1',
    _launches: [
      {
        id: 'mission-1',
        name: 'Example',
        status,
        payloads: [],
        recoveryStages: [],
      },
    ],
    _replayTracks: new Map(),
  };
  createPanel({
    state,
    parts: {
      overlays: { shortMissionLabel: (name) => name },
      policyHelpers: { missionPathPresentation: () => ({}) },
      replay: { syncReplayButton() {} },
    },
  }).renderMissionPanel();
  return outputs.get('[data-mission-status]').textContent;
}

test('a launch without a status keeps the English fallback in its record', () => {
  const [launch] = normalizeRocketLaunches(
    {
      results: [
        {
          id: 'no-status',
          name: 'Test Flight',
          net: '2026-07-20T10:00:00Z',
          pad: {
            name: 'Pad A',
            location: { name: 'Test Range', coordinates: '12.5,45.5' },
          },
        },
      ],
    },
    NOW,
  );
  assert.equal(UNKNOWN_LAUNCH_STATUS, 'Unknown');
  assert.equal(launch.status, 'Unknown');
  assert.equal(launchStatusAllowsOrbit(launch.status), true);
});

test('the mission panel translates only the fallback status', (t) => {
  t.after(() => setLocale('en'));
  setLocale('en');
  assert.equal(shownStatus(UNKNOWN_LAUNCH_STATUS), 'Unknown');
  setLocale('ru');
  assert.equal(shownStatus(UNKNOWN_LAUNCH_STATUS), 'Неизвестно');
  assert.equal(shownStatus('Go for Launch'), 'Go for Launch');
  setLocale('es');
  assert.equal(shownStatus(UNKNOWN_LAUNCH_STATUS), 'Desconocido');
  assert.equal(shownStatus('Launch Successful'), 'Launch Successful');
});
