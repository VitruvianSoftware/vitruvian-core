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
  cockpitCloudRenderSize,
  cockpitWeatherRefreshDue,
  cockpitWeatherEnabledFromStoredValue,
} from './cockpitCloudEffects.js';

test('cockpit cloud framebuffer stays low resolution on large displays', () => {
  assert.deepEqual(cockpitCloudRenderSize(2048, 1152), { width: 520, height: 293 });
  assert.deepEqual(cockpitCloudRenderSize(1280, 720), { width: 520, height: 293 });
});

test('cockpit cloud framebuffer never upscales or collapses to zero', () => {
  assert.deepEqual(cockpitCloudRenderSize(640, 360), { width: 269, height: 151 });
  assert.deepEqual(cockpitCloudRenderSize(0, Number.NaN), { width: 1, height: 1 });
});

test('cockpit weather defaults off and enables only from an explicit saved opt-in', () => {
  assert.equal(cockpitWeatherEnabledFromStoredValue(null), false);
  assert.equal(cockpitWeatherEnabledFromStoredValue(''), false);
  assert.equal(cockpitWeatherEnabledFromStoredValue('0'), false);
  assert.equal(cockpitWeatherEnabledFromStoredValue('1'), true);
});

test('cockpit weather refreshes after time or meaningful movement', () => {
  const anchor = { latitude: 30, longitude: -97 };
  assert.equal(cockpitWeatherRefreshDue({
    nowMs: 1000,
    fetchedAt: 500,
    anchor,
    point: anchor,
    hasWeather: false,
  }), true);
  assert.equal(cockpitWeatherRefreshDue({
    nowMs: 60_000,
    fetchedAt: 0,
    anchor,
    point: { latitude: 30.01, longitude: -97 },
    hasWeather: true,
  }), false);
  assert.equal(cockpitWeatherRefreshDue({
    nowMs: 5 * 60_000,
    fetchedAt: 0,
    anchor,
    point: anchor,
    hasWeather: true,
  }), true);
  assert.equal(cockpitWeatherRefreshDue({
    nowMs: 60_000,
    fetchedAt: 0,
    anchor,
    point: { latitude: 30.3, longitude: -97 },
    hasWeather: true,
  }), true);
});
