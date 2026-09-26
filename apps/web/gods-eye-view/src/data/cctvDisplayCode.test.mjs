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
import {
  CAMERA_CODE_MAX_CHARS,
  cameraDisplayCode,
  normalizeSourceItem,
} from '../../server/providers/cctv/normalize.js';

test('cameraDisplayCode trims long names with an ellipsis and collapses whitespace', () => {
  assert.equal(
    cameraDisplayCode(' IH 35   at Cesar Chavez '),
    'IH 35 at Cesar Chavez',
  );
  const long = 'City of Windsor – Goyeau Street and Park Street';
  const code = cameraDisplayCode(long);
  assert.equal(code.length, CAMERA_CODE_MAX_CHARS);
  assert.ok(code.endsWith('…'));
  assert.equal(cameraDisplayCode(''), '');
});

test('every pack labels by its feed name; explicit codes win; the id is the last resort', () => {
  const base = { lat: 1, lon: 1, url: 'https://x.test/a.jpg' };
  assert.equal(
    normalizeSourceItem({
      ...base,
      id: '354',
      name: '5TH ST / CONGRESS AVE',
      sourceKind: 'austin-open-data',
    }).code,
    '5TH ST / CONGRESS AVE',
  );
  assert.equal(
    normalizeSourceItem({
      ...base,
      id: 'on-860',
      name: 'Goyeau Street and Park Street',
      sourceKind: 'ontario-511-open-data',
    }).code,
    'GOYEAU STREET AND PARK STRE…',
  );
  assert.equal(
    normalizeSourceItem({
      ...base,
      id: 'nsw-46fa631a',
      name: 'Erskine Street looking west',
      sourceKind: 'nsw-livetraffic',
      code: 'ERSKINE ST (SYDNEY)',
    }).code,
    'ERSKINE ST (SYDNEY)',
  );
  assert.equal(
    normalizeSourceItem({
      ...base,
      id: 'fi-c1455101',
      name: '',
      sourceKind: 'fintraffic-open-data',
    }).code,
    'fi-c1455101',
    'a missing name falls back to the id',
  );
});
