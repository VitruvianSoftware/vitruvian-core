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
 * Every aircraft model drawn in the scene skips the renderer's dynamic
 * environment map (a sky render and GPU readback per model).
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
];

test('the shared option turns the dynamic environment map off', () => {
  assert.deepEqual({ ...AIRCRAFT_ENVIRONMENT_MAP_OPTIONS }, { enabled: false });
  assert.ok(Object.isFrozen(AIRCRAFT_ENVIRONMENT_MAP_OPTIONS));
});

for (const { name, source } of SOURCES) {
  test(`${name}: every drawn aircraft model skips the dynamic environment map`, () => {
    // Its models are draw-port items; every item it builds (fleet and
    // tracked) carries the shared option.
    assert.doesNotMatch(source, /fromGltfAsync|loadModel\(/);
    const items = [...source.matchAll(/\burl: record\.url,/g)];
    assert.ok(items.length >= 1, `expected model items in ${name}`);
    const flags = [
      ...source.matchAll(/\benvironmentMap:\s*AIRCRAFT_ENVIRONMENT_MAP_OPTIONS\.enabled\b/g),
    ];
    assert.equal(flags.length, items.length, `${name} model items must pass AIRCRAFT_ENVIRONMENT_MAP_OPTIONS`);
  });
}

test('localAdsb: its draw-port models skip the dynamic environment map', () => {
  const source = readFileSync(
    new URL('../layers/localAdsb/models.js', import.meta.url),
    'utf8',
  );
  assert.match(
    source,
    /\benvironmentMap:\s*AIRCRAFT_ENVIRONMENT_MAP_OPTIONS\.enabled\b/,
  );
});
