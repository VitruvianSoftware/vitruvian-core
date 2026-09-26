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
import vm from 'node:vm';
import { detectionBracketAlpha } from './detectionPolicy.js';

// Exercise the actual renderer's admission and paint expressions. A sweep is
// appearance only: it must not reshuffle candidates at the cohort cutoff.
const source = readFileSync(new URL('./detection.js', import.meta.url), 'utf8');
const alphaBlock = source.match(
  /const admissionAlpha = detectionBracketAlpha\([\s\S]*?const bracketAlpha = [^;]+;/,
)?.[0];
const bandAssignment = source.match(/obj\._cohortBand\s*=\s*[^;]+;/)?.[0];

test('Sonar changes paint alpha without changing detection cohort admission', () => {
  assert.ok(alphaBlock, 'renderer separates admission from paint');
  assert.ok(bandAssignment);
  for (const cyberMapActive of [false, true]) {
    for (const type of ['AIR', 'SAT', 'SEA']) {
      for (const keyholeAlpha of [0, 0.01, 0.125, 0.5, 0.999, 1]) {
        const alpha = detectionBracketAlpha(
          type,
          keyholeAlpha,
          0.35,
          cyberMapActive,
        );
        const expectedBand = alpha >= 0.999 ? 8 : Math.floor(alpha * 8);
        for (const sonarFactor of [0.01, 0.12, 0.5, 1]) {
          const state = {
            obj: { type },
            keyholeAlpha,
            keyholeOutsideOpacity: 0.35,
            cyberMapActive,
            sonarFactor,
            detectionBracketAlpha,
          };
          vm.runInNewContext(
            alphaBlock + bandAssignment + '; result = bracketAlpha;',
            state,
          );
          assert.equal(state.obj._cohortBand, expectedBand);
          assert.equal(state.result, alpha * sonarFactor);
        }
      }
    }
  }
});
