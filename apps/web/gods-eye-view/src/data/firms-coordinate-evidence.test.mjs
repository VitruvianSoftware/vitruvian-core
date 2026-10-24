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
import { parseFirmsCsv } from './firmsCsv.js';
import { adaptFirmsRecords } from './firmsAdapt.js';
test('missing positions do not become fire detections at zero coordinates', () => {
  const csv =
    'latitude,longitude,acq_date,acq_time,confidence,frp\n,1,2026-07-16,1200,n,1\n1, ,2026-07-16,1200,n,1\n95,1,2026-07-16,1200,n,1\n1,181,2026-07-16,1200,n,1\n0,0,2026-07-16,1200,n,1\n-90,-180,2026-07-16,1200,n,1';
  assert.deepEqual(
    parseFirmsCsv(csv).map((r) => [r.lat, r.lon]),
    [
      [0, 0],
      [-90, -180],
    ],
  );
  const records = [
    { lat: null, lon: 1 },
    { lat: '', lon: 1 },
    { lat: false, lon: 1 },
    { lat: 95, lon: 1 },
    { lat: 1, lon: 181 },
    { lat: '0', lon: 0 },
    { lat: -90, lon: -180 },
  ];
  assert.deepEqual(
    adaptFirmsRecords(records).map((r) => [r.index, r.lat, r.lon]),
    [
      [0, 0, 0],
      [1, -90, -180],
    ],
  );
});

test('both axes keep their exact bounds and drop values just past them', () => {
  const row = (lat, lon) => `${lat},${lon},2026-07-16,1200,n,1`;
  const csv = [
    'latitude,longitude,acq_date,acq_time,confidence,frp',
    row(90, 180),
    row(-90, -180),
    row(90.000001, 0),
    row(-90.000001, 0),
    row(0, 180.000001),
    row(0, -180.000001),
    row(' ', 5),
    row(5, '\t'),
  ].join('\n');
  assert.deepEqual(
    parseFirmsCsv(csv).map((r) => [r.lat, r.lon]),
    [
      [90, 180],
      [-90, -180],
    ],
  );
  const kept = adaptFirmsRecords([
    { lat: 90, lon: 180 },
    { lat: '-90', lon: '-180' },
    { lat: -90.000001, lon: 0 },
    { lat: 0, lon: -180.000001 },
    { lat: 5, lon: ' ' },
    { lat: 5, lon: undefined },
    { lat: [5], lon: 5 },
  ]);
  assert.deepEqual(
    kept.map((r) => [r.lat, r.lon]),
    [
      [90, 180],
      [-90, -180],
    ],
  );
});
