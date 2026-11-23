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
import { readFileSync } from 'node:fs';

const source = (layer) =>
  readFileSync(new URL(`../${layer}/tracking.js`, import.meta.url), 'utf8');

for (const layer of ['military', 'flights']) {
  test(`${layer}: a tracked ground station's mast is never turned`, () => {
    // The tracked billboard's rotation answers 0 for a station before any
    // course is projected on screen.
    const rotation = /rotation: \(\) => \{[\s\S]*?courseScreenRotation\(/.exec(
      source(layer),
    )?.[0];
    assert.ok(rotation, 'the tracked billboard turns by a rotation callback');
    assert.match(
      rotation,
      /if \(tracked\.klass === 'station'\) return 0;\s*const projected = courseScreenRotation\(/,
    );
  });
}
