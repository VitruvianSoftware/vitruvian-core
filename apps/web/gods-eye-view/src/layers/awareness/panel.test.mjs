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
import { createPanel } from './panel.js';

test('a Contacts row names its provider as the Layers panel does, with its feed state', () => {
  const cohort = (id, source, sourceStatus) => ({
    id,
    label: id,
    source,
    sourceStatus,
    summary: { relationship: 'OBSERVED', count: 1, nearest: [], reason: 'observed' },
  });
  const state = {
    enabled: true,
    results: {
      subject: { label: 'AFR38JF' },
      cohorts: [
        cohort('flights', 'adsb.lol', 'fallback'),
        cohort('military', 'adsb.lol', null),
        cohort('ais-live-vessels', 'Datalastic', 'stale'),
      ],
    },
    cohortPages: new Map(),
    panelListeners: new Set(),
    panelSignature: '',
    navigationIndex: 0,
  };
  const parts = {
    navigation: { canNavigateNext: () => false },
    rendering: { hideDirectionOverlay() {} },
  };
  createPanel({ state, parts }).renderResults();
  assert.deepEqual(
    state.panelView.rows.map((row) => row.detail),
    ['adsb.lol · FALLBACK · observed', 'adsb.lol · observed', 'Datalastic · STALE · observed'],
  );
  state.offPanelLocale?.();
});
