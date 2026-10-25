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
import { imageSize } from './imageSize.js';

const bytes = (...parts) =>
  Uint8Array.from(
    parts.flat().map((v) => (typeof v === 'string' ? v.charCodeAt(0) : v)),
  );
const ascii = (text) => [...text];

test('a JPEG’s size is read from its first frame, past an EXIF segment', () => {
  const exif = [0xff, 0xe1, 0x00, 0x10, ...new Array(14).fill(0)];
  const sof = [0xff, 0xc0, 0x00, 0x11, 0x08, 0x0b, 0xc0, 0x0f, 0xc0];
  const jpeg = bytes([0xff, 0xd8], exif, sof, new Array(20).fill(0));
  assert.deepEqual(imageSize(jpeg), { width: 0x0fc0, height: 0x0bc0 });
  // Progressive (SOF2) too; a DHT (C4) is not a frame.
  const dht = [0xff, 0xc4, 0x00, 0x04, 0, 0];
  const sof2 = [0xff, 0xc2, 0x00, 0x11, 0x08, 0x00, 0x10, 0x00, 0x20];
  assert.deepEqual(
    imageSize(bytes([0xff, 0xd8], dht, sof2, new Array(10).fill(0))),
    {
      width: 32,
      height: 16,
    },
  );
});

test('PNG, WebP (lossy, lossless, extended) and GIF sizes', () => {
  const png = bytes(
    [0x89],
    ascii('PNG'),
    [0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13],
    ascii('IHDR'),
    [0, 0, 0x10, 0, 0, 0, 0x08, 0],
  );
  assert.deepEqual(imageSize(png), { width: 4096, height: 2048 });
  const riff = (chunk, rest) =>
    bytes(ascii('RIFF'), [0, 0, 0, 0], ascii('WEBP'), ascii(chunk), rest);
  const vp8 = riff('VP8 ', [...new Array(10).fill(0), 0x00, 0x08, 0x00, 0x04]);
  assert.deepEqual(imageSize(vp8), { width: 2048, height: 1024 });
  // VP8L: 14-bit width-1 and height-1 packed after the 0x2f signature.
  const w = 99;
  const h = 49;
  const packed = w | (h << 14);
  const vp8l = riff('VP8L', [
    0,
    0,
    0,
    0,
    0x2f,
    packed & 0xff,
    (packed >> 8) & 0xff,
    (packed >> 16) & 0xff,
    (packed >> 24) & 0xff,
    0,
    0,
    0,
    0,
    0,
    0,
  ]);
  assert.deepEqual(imageSize(vp8l), { width: 100, height: 50 });
  const vp8x = riff(
    'VP8X',
    [0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0x0f, 0x00, 0xff, 0x07, 0x00],
  );
  assert.deepEqual(imageSize(vp8x), { width: 4096, height: 2048 });
  const gif = bytes(ascii('GIF89a'), [0x40, 0x01, 0xf0, 0x00], [0, 0]);
  assert.deepEqual(imageSize(gif), { width: 320, height: 240 });
});

test('anything else, or a header cut short, has no size', () => {
  assert.equal(imageSize(null), null);
  assert.equal(imageSize(new Uint8Array(4)), null);
  assert.equal(imageSize(bytes(ascii('<html><body>'))), null);
  assert.equal(
    imageSize(
      bytes([0xff, 0xd8, 0xff, 0xe1, 0xff, 0xff], new Array(8).fill(0)),
    ),
    null,
  );
});
