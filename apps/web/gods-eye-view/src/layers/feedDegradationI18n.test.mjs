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

// The AIS degradation chip and the traffic "SIMULATED — <reason>" text read in
// the UI language; English keeps its wording.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setLocale, translateKnown } from '../i18n/index.js';
import { deriveAisFeedError } from '../data/aisLiveVessels.js';
import { createModel } from './traffic/model.js';

test('AIS degraded-feed reasons are localized in es', () => {
  setLocale('es');
  try {
    const cases = [
      [
        { status: 'down', reconnectAttempt: 3 },
        'feed down — retrying slowly (attempt 3)',
      ],
      [{ status: 'missing-key' }, 'AISSTREAM_API_KEY not set'],
      [
        { status: 'stale', silentForMs: 90000 },
        'feed silent 90s — no AIS data',
      ],
      [{ status: 'auth-failed' }, 'API key rejected — check AISSTREAM_API_KEY'],
      [{ status: 'connecting' }, 'connecting to feed…'],
      [{ status: 'closed' }, 'feed disconnected'],
    ];
    for (const [payload, english] of cases) {
      // The layer panel runs stats.error through translateKnown(); emulate it.
      const shown = translateKnown(deriveAisFeedError(payload, 0));
      assert.notEqual(shown, english, `status ${payload.status} still English`);
    }
  } finally {
    setLocale('en');
  }
});

test('traffic "SIMULATED — <reason>" is localized in es', () => {
  setLocale('es');
  try {
    const { trafficFeedPresentation } = createModel({
      state: {},
      services: {},
      parts: {},
      source: {},
    });
    const degraded = trafficFeedPresentation({
      liveMode: true,
      flowError: 'TomTom daily budget reached',
    });
    const shown = translateKnown(degraded.error);
    assert.notEqual(shown, 'SIMULATED — TomTom daily budget reached');
    assert.ok(!shown.startsWith('SIMULATED'), `still English: ${shown}`);
  } finally {
    setLocale('en');
  }
});

test('English degraded-feed wording is unchanged', () => {
  setLocale('en');
  assert.equal(
    deriveAisFeedError({ status: 'down', reconnectAttempt: 3 }, 0),
    'feed down — retrying slowly (attempt 3)',
  );
  assert.equal(
    deriveAisFeedError({ status: 'reconnecting' }, 0),
    'reconnecting to feed…',
  );
  assert.equal(
    deriveAisFeedError({ status: 'missing-key' }, 0),
    'AISSTREAM_API_KEY not set',
  );
  const { trafficFeedPresentation } = createModel({
    state: {},
    services: {},
    parts: {},
    source: {},
  });
  assert.equal(
    trafficFeedPresentation({
      liveMode: true,
      flowError: 'TomTom daily budget reached',
    }).error,
    'SIMULATED — TomTom daily budget reached',
  );
});
