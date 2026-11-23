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

import assert from 'node:assert/strict';
import test from 'node:test';
import { hazardsNear } from './spotConditions.js';

test('a wildfire is placed at its card anchor, not its first ring', async (t) => {
  // Two polygons: the larger one, far from the first, carries the anchor.
  const square = (lon, lat, size) => [
    [
      [lon, lat],
      [lon + size, lat],
      [lon + size, lat + size],
      [lon, lat + size],
      [lon, lat],
    ],
  ];
  t.mock.method(globalThis, 'fetch', async (url) =>
    String(url) === '/api/fire-perimeters'
      ? Response.json({
          rows: [
            {
              stableId: 'fire',
              name: 'Fixture Fire',
              acres: 1200,
              containedPct: 30,
              updatedTime: Date.now() - 3600000,
              polygons: [square(-110, 35, 0.01), square(-108, 35, 0.2)],
            },
          ],
        })
      : new Response('down', { status: 503 }),
  );
  const near = await hazardsNear(35.1, -107.9, 30, { force: true });
  const fires = near.filter(({ kind }) => kind === 'wildfire');
  assert.equal(fires.length, 1);
  assert.equal(fires[0].title, 'Fixture Fire');
  assert.ok(fires[0].distanceKm < 5, `${fires[0].distanceKm} km`);
});
