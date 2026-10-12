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
import { createApplicationStreetLevel } from './streetLevel.js';
import { fakeStreetLevelProvider } from '../../testSupport/streetLevelFakes.mjs';

test('explicit providers replace the default source and an empty list removes it', () => {
  const sources = { mapillary: {} };
  const provider = fakeStreetLevelProvider({
    id: 'example',
    pickPrefix: 'example:',
  });
  const layer = createApplicationStreetLevel({
    sources,
    providers: [provider],
  });
  assert.deepEqual(layer.providerIds, ['example']);
  assert.deepEqual(
    createApplicationStreetLevel({ sources, providers: [] }).providerIds,
    [],
  );
  assert.throws(
    () => createApplicationStreetLevel({ sources }),
    /Mapillary source/,
  );
  assert.throws(
    () => createApplicationStreetLevel({ providers: null }),
    /array/,
  );
});
