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

/** Bundled OpenStreetMap infrastructure: datacenters and dams. */

import { suggestView } from '../views.js';
import { defineTool } from '../catalog.js';
import {
  AREA_SCHEMA,
  areaCenter,
  areaContains,
  distanceKm,
  resolveArea,
} from '../area.js';
import { LIMIT_SCHEMA, capRows, countNoun } from '../results.js';

const KINDS = {
  datacenters: { layerId: 'local-datacenters', noun: 'datacenter' },
  dams: { layerId: 'local-dams', noun: 'dam' },
};
const ATTRIBUTION = {
  datacenters: '© OpenStreetMap contributors (ODbL 1.0)',
  dams: '© OpenStreetMap contributors (ODbL 1.0), via Open Infrastructure Map',
};

const round = (value, digits) =>
  Number.isFinite(value) ? Number(value.toFixed(digits)) : null;

export const findInfrastructure = defineTool({
  name: 'find_infrastructure',
  title: 'Datacenters and dams',
  description:
    'Datacenters (with operator and capacity) or dams (with river and power ' +
    'output) mapped in OpenStreetMap within an area, nearest the center first.',
  inputSchema: {
    type: 'object',
    properties: {
      kind: { type: 'string', enum: Object.keys(KINDS) },
      area: AREA_SCHEMA,
      limit: LIMIT_SCHEMA,
    },
    required: ['kind', 'area'],
    additionalProperties: false,
  },
  requires: ['infrastructure'],
  async run(args, { services, signal }) {
    const area = await resolveArea(args.area, { services, signal });
    const center = areaCenter(area);
    const { layerId, noun } = KINDS[args.kind];
    const records = await services.infrastructure.getRecords(layerId, {
      signal,
    });
    const rows = records
      .filter((record) => areaContains(area, record))
      .map((record) => ({
        name: record.name,
        operator: record.operator,
        ...(args.kind === 'datacenters'
          ? { capacity: record.capacity }
          : { river: record.river, output: record.output }),
        lat: round(record.lat, 5),
        lon: round(record.lon, 5),
        distance_km: round(distanceKm(center, record), 1),
      }))
      .sort((a, b) => a.distance_km - b.distance_km);
    return {
      summary: `${countNoun(rows.length, `mapped ${noun}`)} in ${area.label}.`,
      data: {
        view: suggestView(services, { area, layers: [layerId] }),
        ...capRows(rows, args.limit),
        attribution: ATTRIBUTION[args.kind],
      },
    };
  },
});
