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
import { createWildlifeBillboardModel } from '../layers/wildlifeSightings/billboardModel.js';
import { buildWildlifeIconModel } from '../layers/wildlifeSightings/model.js';

export const WILDLIFE_BENCHMARK_REFRESHES = 10;
const ICONICS = ['Aves', 'Mammalia', 'Reptilia', 'Plantae', 'Unknown'];

export function syntheticRows(n) {
  return Array.from({ length: n }, (_, i) => ({
    stableId: `synthetic:${i}`,
    lat: -60 + (i % 1000) * 0.12,
    lon: -179 + (i % 2000) * 0.179,
    iconic: ICONICS[i % ICONICS.length],
    quality: 'research',
    count: null,
    obscured: false,
    cell: null,
  }));
}

export function harness() {
  const points = new Set();
  const counters = { created: 0, destroyed: 0, writes: 0, positions: 0 };
  const collection = {
    add(options) {
      const point = new Proxy(
        { show: true, ...options },
        {
          set(target, key, value) {
            counters.writes += 1;
            target[key] = value;
            return true;
          },
        },
      );
      points.add(point);
      counters.created += 1;
      return point;
    },
    remove(point) {
      assert.equal(points.delete(point), true);
      counters.destroyed += 1;
    },
    removeAll() {
      throw new Error('A refresh must never clear the billboard collection');
    },
  };
  const appearance = new Map(
    ICONICS.map((iconic) => [
      iconic,
      {
        image: `cached:${iconic}`,
        color: iconic,
        scale: 1,
      },
    ]),
  );
  const pointById = new Map();
  const model = createWildlifeBillboardModel({
    collection,
    pointById,
    positions: new Map(),
    positionForRow(row) {
      counters.positions += 1;
      return { x: row.lon, y: row.lat };
    },
    appearanceForGroup: (group) => appearance.get(group),
  });
  const apply = (rows) => {
    const population = buildWildlifeIconModel({ rows });
    return model.update(population.rows);
  };
  return { apply, counters, model, pointById, points };
}

export function changePositions(rows, refresh) {
  return rows.map((row, i) =>
    i % 10 === 0
      ? { ...row, lat: row.lat + (refresh % 2 ? 0.001 : -0.001) }
      : row,
  );
}
