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
import { formatWindReading, windReadingResult } from './presentation.js';

const sample = { speed: 5, from: 'SW', coordinates: '41.9°N · 87.6°W', model: 'NOAA GFS', validTime: '2026-09-21 12:00 UTC', scalarLabel: 'Air temperature · 2 m', scalarValue: '12 °C', explanation: 'Interpolated model forecast.' };
test('captured reading reformats without changing its sample and produces a portable result block', () => {
  const reading = formatWindReading(sample, 'mph');
  assert.equal(reading.wind, '11.2 mph from SW');
  assert.equal(reading.speed, sample.speed);
  assert.equal(reading.coordinates, sample.coordinates);
  assert.equal(sample.units, undefined);
  const section = windReadingResult(reading);
  assert.equal(section.id, 'reading');
  assert.equal(section.lines.find(({ id }) => id === 'scalar').text, 'Air temperature · 2 m · 12 °C');
  assert.equal(section.lines.find(({ id }) => id === 'wind').text, '11.2 mph from SW');
  assert.equal(section.lines.find(({ id }) => id === 'meta').text, 'NOAA GFS · valid 09-21 12:00 UTC');
  assert.equal(section.label, 'WIND AT 41.9°N 87.6°W');
  assert.deepEqual(section.clear.params, { inspect: false });
  assert.equal(formatWindReading({ ...sample, from: 'Calm' }, 'm/s').wind, '5.0 m/s · calm');
  assert.equal(formatWindReading(null, 'km/h'), null);
  assert.equal(windReadingResult({ coordinates: 'No surface reading', wind: 'Unavailable' }).lines.some(({ id }) => id === 'scalar'), false);
});
