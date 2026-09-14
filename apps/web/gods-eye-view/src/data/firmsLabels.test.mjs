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
import { readFileSync } from 'node:fs';
import {
  accentForSeverity,
  FIRMS_AMBIENT_COHORT_LIMIT,
  FIRMS_OVERLAY_SOURCE_ID,
  satelliteShortName,
} from './firmsLabels.js';

test('FIRMS formatting helpers retain the shipped severity palette', () => {
  assert.equal(accentForSeverity('red'), '224, 82, 82');
  assert.equal(accentForSeverity('orange'), '240, 178, 62');
  assert.equal(accentForSeverity('yellow'), '244, 227, 108');
  assert.equal(accentForSeverity('chartreuse'), accentForSeverity('yellow'));
});

test('FIRMS satellite names retain the three VIIRS abbreviations', () => {
  assert.equal(satelliteShortName('N20'), 'N20');
  assert.equal(satelliteShortName('N21'), 'N21');
  assert.equal(satelliteShortName('N'), 'SNPP');
  assert.equal(satelliteShortName('TERRA-X9'), 'TERRA-');
  assert.equal(satelliteShortName(''), '');
});

test('FIRMS host registration constants pin the shipped source budget', () => {
  assert.equal(FIRMS_OVERLAY_SOURCE_ID, 'firms');
  assert.equal(FIRMS_AMBIENT_COHORT_LIMIT, 18);
});

test('FIRMS helper module cannot resurrect a dedicated canvas renderer', () => {
  const source = readFileSync(new URL('./firmsLabels.js', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /createElement\(['"]canvas['"]\)/);
  assert.doesNotMatch(source, /postRender/);
  assert.doesNotMatch(source, /worldToWindowCoordinates/);
});
