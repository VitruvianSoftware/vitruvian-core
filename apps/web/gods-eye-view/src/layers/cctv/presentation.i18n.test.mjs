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

// The CCTV HUD summary shows the CAL badge, source kind and view band in the
// UI language; English keeps its codes, and unknown source codes stay codes.
import test from 'node:test';
import assert from 'node:assert/strict';
import { setLocale } from '../../i18n/index.js';
import { createPresentation } from './presentation.js';

function summary(sourceKind) {
  const camera = {
    id: 'c1',
    city: 'Austin',
    name: 'Cam',
    rangeM: 100,
    fovDeg: 60,
    feedType: 'image',
  };
  const record = { camera };
  const presentation = createPresentation({
    state: {
      _records: [record],
      _healthById: new Map(sourceKind ? [['c1', { sourceKind }]] : []),
      _showProjection: false,
      _coverageMode: 'sector',
    },
    services: {},
    parts: {
      selection: { getActiveRecord: () => record },
      model: {
        sectorAreaKm2: () => 1,
        currentViewContext: () => 'street:1:2',
      },
      geometry: { coverageNeighborCount: () => 0 },
      calibration: { deriveCalBadge: () => 'raw-prior' },
    },
    source: {},
  });
  return presentation.buildSummaryText();
}

test('en: CAL, SRC and CONTEXT keep their English codes', () => {
  setLocale('en');
  assert.match(summary('upstream'), /CAL RAW PRIOR · SRC UPSTREAM/);
  assert.match(summary(null), /SRC IMAGE · STREET CONTEXT/);
  assert.match(summary('upstream-image'), /SRC UPSTREAM-IMAGE/);
});

test('fr: CAL, SRC and CONTEXT values are translated', () => {
  setLocale('fr');
  try {
    assert.match(
      summary('upstream'),
      /CAL ESTIM\. INITIALE · SRC AMONT · CONTEXTE RUE/,
    );
    assert.match(summary('upstream-image'), /SRC UPSTREAM-IMAGE/);
  } finally {
    setLocale('en');
  }
});
