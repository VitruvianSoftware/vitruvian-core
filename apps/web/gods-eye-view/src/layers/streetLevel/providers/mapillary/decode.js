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
 * Decode a `mly1_public` coverage tile (z11–14) into sequences. The z14
 * `image` layer, which can hold >150k points, is skipped.
 * @param {Uint8Array} bytes
 * @param {{x:number,y:number,z:number}} address
 */
export function decodeCoverageTile(bytes, address) {
  const result = { sequences: [] };
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
        capturedAt: Number(props.captured_at) || 0,
        isPano: props.is_pano === true,
        parts,
      });
    }
  }
  return result;
}
