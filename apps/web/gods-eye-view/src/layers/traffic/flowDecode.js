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

import { PbfReader } from 'pbf';
import { VectorTile } from '@mapbox/vector-tile';

/**
 * @file TomTom traffic-flow vector-tile client: fetch + MVT decode.
 *
 * Fetches flow tiles from the local `/api/tomtom/flow/{z}/{x}/{y}.pbf` proxy
 * (the TomTom key never reaches the browser) and decodes the Mapbox Vector
 * Tile layer "Traffic flow" into plain lon/lat polylines with congestion
 * attributes. Consumed by the traffic layer's live mode
 * (`src/data/traffic.js` → `src/data/flowMatch.js`).
 *
 * Segment shape: `{coords: [[lon,lat],…], trafficLevel: 0..1, roadType: string,
 * closure: boolean}` — `trafficLevel` is TomTom's current/free-flow speed
 * ratio (1 = free flow). Features with a missing/non-finite `traffic_level`
 * are skipped unless `road_closure` is true (closures decode with level 0).
 *
 * Deps: `pbf@5` (PbfReader) + `@mapbox/vector-tile@3` — both tiny and
 * tree-shakeable; decoding happens client-side so the proxy stays a dumb
 * binary cache.
 *
 * @module data/flowTiles
 */

const FLOW_LAYER_NAME = 'Traffic flow';
export function decodeFlowTile(data, z, x, y) {
  let layer;
  try {
    const bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : data;
    const tile = new VectorTile(new PbfReader(bytes));
    layer = tile.layers[FLOW_LAYER_NAME];
  } catch {
    return [];
  }
  if (!layer) return [];

  const segments = [];
  for (let i = 0; i < layer.length; i++) {
    let feature;
    let geometry;
    try {
      feature = layer.feature(i);
      geometry = feature.toGeoJSON(x, y, z).geometry;
    } catch {
      continue; // one malformed feature must not drop the tile
    }
    const props = feature.properties || {};
    const closure =
      props.road_closure === true || props.road_closure === 'true';
    const rawLevel = props.traffic_level;
    const hasLevel = typeof rawLevel === 'number' && Number.isFinite(rawLevel);
    // Skip features we can't color — unless closed (closures render dot-free
    // regardless of level, so they stay useful without one).
    if (!hasLevel && !closure) continue;
    const trafficLevel = hasLevel ? Math.min(1, Math.max(0, rawLevel)) : 0;
    const roadType = typeof props.road_type === 'string' ? props.road_type : '';

    const lines =
      geometry.type === 'LineString'
        ? [geometry.coordinates]
        : geometry.type === 'MultiLineString'
          ? geometry.coordinates
          : [];
    for (const coords of lines) {
      if (!Array.isArray(coords) || coords.length < 2) continue;
      segments.push({ coords, trafficLevel, roadType, closure });
    }
  }
  return segments;
}
