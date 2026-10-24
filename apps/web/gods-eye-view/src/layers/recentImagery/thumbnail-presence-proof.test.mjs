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
import { createThumbnailLoader } from './thumbnails.js';
test('missing or malformed presence evidence cannot prove thumbnail pixels', async () => {
  for (const header of [null, 'unknown', '', 'true', 'false']) {
    let decodes = 0;
    const loader = createThumbnailLoader({
      requestThumbnail: async () => ({
        ok: true,
        headers: { get: (key) => (key === 'Data-Present' ? header : null) },
        blob: async () => {
          decodes++;
          return new Blob(['fixture']);
        },
      }),
      createObjectUrl: () => 'blob:fixture',
    });
    loader.request(
      { key: 'fixture', product: 'S30', day: '2026-09-18' },
      { west: 0, east: 1, south: 0, north: 1 },
    );
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(
      loader.get('fixture').status,
      header === 'true' ? 'present' : header === 'false' ? 'empty' : 'error',
    );
    assert.equal(decodes, header === 'true' ? 1 : 0);
    loader.destroy();
  }
});
