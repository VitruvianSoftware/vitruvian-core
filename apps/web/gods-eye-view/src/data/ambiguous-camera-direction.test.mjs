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
import { directionToHeading } from './directionText.js';
test('conflicting facing directions cannot manufacture one heading', () => {
  for (const bare of [false, true]) {
    for (const value of ['NB / SB', 'EASTBOUND WESTBOUND', 'NE SW'])
      assert.ok(Number.isNaN(directionToHeading(value, bare)), value);
    assert.equal(directionToHeading('NB northbound', bare), 0);
    assert.equal(directionToHeading('IH-35 SOUTHBOUND AT 15TH', bare), 180);
  }
  assert.ok(Number.isNaN(directionToHeading('North / East', true)));
  assert.equal(directionToHeading('West / SR-24', true), 270);
});

test('travel tokens retain precedence over quadrant streets and bare words', () => {
  for (const [text, heading] of [
    ['I-5 NB at NE 45th St', 0],
    ['SR 520 EB at NE 148th', 90],
    ['US 13 SB @ SW Front St', 180],
  ]) {
    for (const bare of [false, true])
      assert.equal(directionToHeading(text, bare), heading);
  }
  assert.equal(
    directionToHeading('Hwy 401 east of Keele St - Westbound', true),
    270,
  );
  assert.equal(directionToHeading('NE near West St', true), 45);
  assert.ok(Number.isNaN(directionToHeading('NB SB near NE St', true)));
});
