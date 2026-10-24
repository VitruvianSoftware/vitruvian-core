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
import { normalizeRegionalWeather, weatherCodeLabel } from './regionalModel.js';
test('missing weather observations never assert clear conditions', () => {
  for (const value of [null, undefined, '', ' ', false, true]) {
    assert.equal(weatherCodeLabel(value), 'CONDITIONS UNKNOWN');
    assert.equal(
      normalizeRegionalWeather({ current: { temperature_2m: value } }),
      null,
    );
  }
  assert.equal(weatherCodeLabel(0), 'CLEAR');
  assert.equal(weatherCodeLabel('0'), 'CLEAR');
  const record = normalizeRegionalWeather({
    current: { temperature_2m: 0, weather_code: null, wind_speed_10m: false },
  });
  assert.equal(record.temperatureC, 0);
  assert.equal(record.weatherCode, null);
  assert.equal(record.windKph, null);
});
