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
import { readLayerSource } from '../testSupport/readLayerSource.mjs';
import { AIRCRAFT_ENVIRONMENT_MAP_OPTIONS } from './aircraftModelLighting.js';

/**
 * Every aircraft model drawn in the scene skips Cesium's dynamic environment
 * map (a sky render and GPU readback per model). The preload calls only warm
 * the glTF cache and are never added to the scene, so they are left out:
 * drawn models are the calls that set a minimum pixel size.
 */
const SOURCES = [
  {
    name: 'flights',
    source: readLayerSource(new URL('./flights.js', import.meta.url)),
  },
  {
    name: 'militaryFlights',
    source: readLayerSource(new URL('./militaryFlights.js', import.meta.url)),
  },
  {
    name: 'localAdsb',
    source: readFileSync(
      new URL('../layers/localAdsb/models.js', import.meta.url),
      'utf8',
    ),
  },
];

test('the shared option turns the dynamic environment map off', () => {
  assert.deepEqual({ ...AIRCRAFT_ENVIRONMENT_MAP_OPTIONS }, { enabled: false });
  assert.ok(Object.isFrozen(AIRCRAFT_ENVIRONMENT_MAP_OPTIONS));
});

for (const { name, source } of SOURCES) {
  test(`${name}: every drawn aircraft model skips the dynamic environment map`, () => {
    const calls = [
      ...source.matchAll(/(?:fromGltfAsync|loadModel)\(\{([\s\S]*?)\}\)/g),
    ]
      .map((match) => match[1])
      .filter((options) => /\bminimumPixelSize:/.test(options));
    assert.ok(calls.length >= 1, `expected drawn model calls in ${name}`);
    for (const [index, options] of calls.entries())
      assert.match(
        options,
        /\benvironmentMapOptions:\s*AIRCRAFT_ENVIRONMENT_MAP_OPTIONS\b/,
        `${name} model call ${index + 1} must pass AIRCRAFT_ENVIRONMENT_MAP_OPTIONS`,
      );
  });
}
