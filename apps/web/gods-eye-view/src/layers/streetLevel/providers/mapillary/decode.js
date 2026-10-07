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
import { tileLocalToLonLat } from '../../tileMath.js';

/**
 * Decode a `mly1_public` coverage tile into sequences and (z0–5) overview
 * points. The z14 `image` layer, which can hold >150k points, is skipped.
 * @param {Uint8Array} bytes
 * @param {{x:number,y:number,z:number}} address
 */
export function decodeCoverageTile(bytes, address) {
  const result = { sequences: [], overview: [] };
  if (!bytes || !bytes.length) return result;
  const tile = new VectorTile(new PbfReader(bytes));
  const { x, y, z } = address;
  const sequenceLayer = tile.layers.sequence;
  if (sequenceLayer) {
    for (let i = 0; i < sequenceLayer.length; i++) {
      const feature = sequenceLayer.feature(i);
      const props = feature.properties || {};
      // A sequence with a capture gap is a multi-line: keep each part as its
      // own line, so no straight segment is drawn across the gap.
      const parts = [];
      for (const line of feature.loadGeometry()) {
        const part = line.map((point) =>
          tileLocalToLonLat(point.x, point.y, sequenceLayer.extent, x, y, z),
        );
        if (part.length >= 2) parts.push(part);
      }
      if (!parts.length) continue;
      result.sequences.push({
        id: String(props.id ?? feature.id ?? `${x}/${y}/${i}`),
        imageId: props.image_id != null ? String(props.image_id) : null,
        capturedAt: Number(props.captured_at) || 0,
        isPano: props.is_pano === true,
        onFoot: props.foot === true,
        quality: Number.isFinite(props.quality_score)
          ? props.quality_score
          : null,
        parts,
      });
    }
  }
  const overviewLayer = tile.layers.overview;
  if (overviewLayer) {
    for (let i = 0; i < overviewLayer.length; i++) {
      const feature = overviewLayer.feature(i);
      const props = feature.properties || {};
      const point = feature.loadGeometry()?.[0]?.[0];
      if (!point) continue;
      const [lon, lat] = tileLocalToLonLat(
        point.x,
        point.y,
        overviewLayer.extent,
        x,
        y,
        z,
      );
      result.overview.push({
        id: String(props.id ?? feature.id ?? i),
        lon,
        lat,
        capturedAt: Number(props.captured_at) || 0,
        isPano: props.is_pano === true,
        sequenceId: props.sequence_id ? String(props.sequence_id) : null,
      });
    }
  }
  return result;
}
