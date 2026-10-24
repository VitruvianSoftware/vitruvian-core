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
import { isoTime } from './results.js';
import { getBikeShare } from './queries/mobility.js';
test('out-of-range finite timestamps are unknown rather than throwing', async () => {
  for (const value of [1e30, -1e30, NaN, Infinity, null])
    assert.equal(isoTime(value), null);
  assert.equal(isoTime(0), '1970-01-01T00:00:00.000Z');
  assert.equal(isoTime(8640000000000000), '+275760-09-13T00:00:00.000Z');
  assert.equal(isoTime(-8640000000000000), '-271821-04-20T00:00:00.000Z');
  for (const value of [8640000000000001, -8640000000000001, -Infinity])
    assert.equal(isoTime(value), null);
  assert.equal(isoTime(-1), '1969-12-31T23:59:59.999Z');
  const station = {
    station_id: 's1',
    name: 'Fixture',
    lat: 0,
    lon: 0,
    capacity: 4,
  };
  const result = await getBikeShare.run(
    { area: { bbox: [-1, -1, 1, 1] } },
    {
      services: {
        bikeshare: {
          systems: [
            {
              id: 'fixture',
              city: 'Fixture',
              centerLat: 0,
              centerLon: 0,
              loadRadiusKm: 30,
              stationInformationUrl: 'information',
              stationStatusUrl: 'status',
            },
          ],
          async getStations(url) {
            return {
              data: {
                stations:
                  url === 'information'
                    ? [station]
                    : [
                        {
                          station_id: 's1',
                          last_reported: 1e30,
                          num_bikes_available: 2,
                        },
                      ],
              },
            };
          },
        },
      },
    },
  );
  assert.equal(result.data.returned, 1);
  assert.equal(result.data.rows[0].last_reported, null);
});
