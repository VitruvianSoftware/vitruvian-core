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
import { setLocale } from '../i18n/index.js';
import { formatQuantity, formatScaleLabel, unitLabel } from './unitLabels.js';

test('English readings and scales read exactly as the unit ids', () => {
  setLocale('en');
  assert.equal(unitLabel('km/h'), 'km/h');
  assert.equal(unitLabel('°C'), '°C');
  assert.equal(unitLabel('dBZ'), 'dBZ');
  assert.equal(unitLabel(''), '');
  assert.equal(formatQuantity(95, 'kt'), '95 kt');
  assert.equal(formatQuantity(1006, 'hPa'), '1006 hPa');
  assert.equal(
    formatQuantity(22, 'km/h', {
      minimumFractionDigits: 1,
      maximumFractionDigits: 1,
    }),
    '22.0 km/h',
  );
  assert.deepEqual(
    ['0.1', '-40', '1050+', '300+', 'Calm'].map(formatScaleLabel),
    ['0.1', '-40', '1050+', '300+', 'Calm'],
  );
});

test('other languages get their decimal separator and no digit grouping', () => {
  try {
    setLocale('ru');
    assert.match(
      formatQuantity(22, 'km/h', {
        minimumFractionDigits: 1,
        maximumFractionDigits: 1,
      }),
      /^22,0 \S+$/,
    );
    assert.match(formatQuantity(1050, 'hPa'), /^1050 /);
    assert.deepEqual(['0.1', '-40', '1050+'].map(formatScaleLabel), [
      '0,1',
      '-40',
      '1050+',
    ]);
  } finally {
    setLocale('en');
  }
});
