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
import { createStandaloneLayerSources } from './layerSources.js';

test('traffic and installations own separate local OpenFreeMap lifetimes', () => {
  const mapTiles = [];
  const mapTileOptions = [];
  const sources = createStandaloneLayerSources(
    {},
    {
      createMapTiles(options) {
        mapTileOptions.push(options);
        const source = {
          clears: 0,
          clear() {
            this.clears++;
          },
          getMetadata: async () => ({
            template:
              'https://tiles.openfreemap.org/planet/test/{z}/{x}/{y}.pbf',
          }),
          fetchBounds: async () => ({ tiles: [], loadedTiles: [] }),
        };
        mapTiles.push(source);
        return source;
      },
    },
  );

  assert.equal(mapTiles.length, 2);
  assert.notEqual(mapTiles[0], mapTiles[1]);
  const decoded = { roads: ['road'], military: ['site'] };
  assert.deepEqual(mapTileOptions[0].selectDecoded(decoded), {
    roads: ['road'],
  });
  assert.deepEqual(mapTileOptions[1].selectDecoded(decoded), {
    military: ['site'],
  });
  sources.traffic.resetFlowTileCache();
  assert.deepEqual(
    mapTiles.map((source) => source.clears),
    [1, 0],
    'traffic reset cannot clear installation work',
  );
  sources.installations.destroy();
  assert.deepEqual(
    mapTiles.map((source) => source.clears),
    [1, 1],
    'installation destroy cannot clear traffic work',
  );
});
