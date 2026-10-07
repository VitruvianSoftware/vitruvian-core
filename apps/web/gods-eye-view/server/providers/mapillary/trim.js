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

import { PbfReader, PbfWriter } from 'pbf';

/** Field number of `layers` in a Mapbox Vector Tile, and of `name` in a layer. */
const TILE_LAYER_FIELD = 3;
const LAYER_NAME_FIELD = 1;

/** Read a layer's name without touching its features. */
function layerName(layerBytes) {
  const pbf = new PbfReader(layerBytes);
  let name = '';
  pbf.readFields((tag, _result, reader) => {
    if (tag !== LAYER_NAME_FIELD) return;
    name = reader.readString();
    reader.pos = reader.length; // the name is all we need
  }, null);
  return name;
}

/**
 * Drop whole layers from a vector tile without decoding kept layers, so a
 * 12 MB tile trims in milliseconds. Returns the input when nothing was dropped.
 * @param {Buffer|Uint8Array} bytes
 * @param {Iterable<string>} dropNames
 */
export function stripTileLayers(bytes, dropNames) {
  const drop = new Set(dropNames || []);
  if (!bytes?.length || !drop.size) return bytes;
  const reader = new PbfReader(bytes);
  const writer = new PbfWriter();
  let dropped = false;
  reader.readFields((tag, _result, pbf) => {
    if (tag !== TILE_LAYER_FIELD) return;
    const end = pbf.readVarint() + pbf.pos;
    const layerBytes = bytes.subarray(pbf.pos, end);
    pbf.pos = end;
    if (drop.has(layerName(layerBytes))) {
      dropped = true;
      return;
    }
    writer.writeBytesField(TILE_LAYER_FIELD, layerBytes);
  }, null);
  return dropped ? Buffer.from(writer.finish()) : bytes;
}

/** Names of the layers inside a vector tile, in order. */
export function listTileLayers(bytes) {
  const names = [];
  if (!bytes?.length) return names;
  new PbfReader(bytes).readFields((tag, _result, pbf) => {
    if (tag !== TILE_LAYER_FIELD) return;
    const end = pbf.readVarint() + pbf.pos;
    names.push(layerName(bytes.subarray(pbf.pos, end)));
    pbf.pos = end;
  }, null);
  return names;
}
