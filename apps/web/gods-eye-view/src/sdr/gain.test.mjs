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

import {
  R820T_GAIN_STEPS_DB,
  SDR_GAIN_DEFAULTS,
  SDR_GAIN_STORAGE_KEY,
  normalizeSdrGain,
  readSdrGainSettings,
  tunerGainValue,
  writeSdrGainSettings,
} from './gain.js';

function memoryStorage(initial = {}) {
  const values = new Map(Object.entries(initial));
  return {
    values,
    getItem: (key) => (values.has(key) ? values.get(key) : null),
    setItem: (key, value) => values.set(key, String(value)),
  };
}

test('gain steps are the R820T table and ADS-B defaults to manual 28.0 dB', () => {
  assert.equal(R820T_GAIN_STEPS_DB.length, 29);
  assert.equal(R820T_GAIN_STEPS_DB[0], 0);
  assert.equal(R820T_GAIN_STEPS_DB.at(-1), 49.6);
  assert.ok(R820T_GAIN_STEPS_DB.includes(20.7));
  assert.ok(R820T_GAIN_STEPS_DB.includes(28.0));
  assert.deepEqual(SDR_GAIN_DEFAULTS, { fm: 'auto', adsb: 28.0 });
  assert.equal(tunerGainValue('auto'), null, 'AUTO hands gain to tuner AGC');
  assert.equal(tunerGainValue(20.7), 20.7);
});

test('requested gains normalize to AUTO or the nearest listed step', () => {
  assert.equal(normalizeSdrGain('AUTO'), 'auto');
  assert.equal(normalizeSdrGain('36.4'), 36.4);
  assert.equal(normalizeSdrGain(21), 20.7);
  assert.equal(normalizeSdrGain(100), 49.6);
  assert.equal(normalizeSdrGain(-3), 0);
  assert.equal(normalizeSdrGain('loud'), null);
  assert.equal(normalizeSdrGain(null), null);
});

test('per-mode gain persists in storage and survives unavailable storage', () => {
  const storage = memoryStorage();
  assert.deepEqual(readSdrGainSettings(storage), SDR_GAIN_DEFAULTS);
  assert.equal(writeSdrGainSettings(storage, { fm: 28, adsb: 'auto' }), true);
  assert.equal(
    storage.values.get(SDR_GAIN_STORAGE_KEY),
    '{"fm":28,"adsb":"auto"}',
  );
  assert.deepEqual(readSdrGainSettings(storage), { fm: 28, adsb: 'auto' });

  const corrupt = memoryStorage({ [SDR_GAIN_STORAGE_KEY]: '{not json' });
  assert.deepEqual(readSdrGainSettings(corrupt), SDR_GAIN_DEFAULTS);
  const throwing = {
    getItem() {
      throw new Error('blocked');
    },
    setItem() {
      throw new Error('blocked');
    },
  };
  assert.deepEqual(readSdrGainSettings(throwing), SDR_GAIN_DEFAULTS);
  assert.equal(writeSdrGainSettings(throwing, SDR_GAIN_DEFAULTS), false);
  assert.deepEqual(readSdrGainSettings(null), SDR_GAIN_DEFAULTS);
});

test('a stored ADS-B gain wins over the 28.0 dB default', () => {
  const storage = memoryStorage({
    [SDR_GAIN_STORAGE_KEY]: JSON.stringify({ fm: 'auto', adsb: 20.7 }),
  });
  assert.deepEqual(readSdrGainSettings(storage), { fm: 'auto', adsb: 20.7 });
  const onlyFm = memoryStorage({
    [SDR_GAIN_STORAGE_KEY]: JSON.stringify({ fm: 36.4 }),
  });
  assert.deepEqual(readSdrGainSettings(onlyFm), { fm: 36.4, adsb: 28.0 });
});
