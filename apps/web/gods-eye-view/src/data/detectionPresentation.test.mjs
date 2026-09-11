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
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import {
  COCKPIT_BRACKET_OPACITY,
  detectionBracketOpacity,
} from './detectionPresentation.js';

test('Cockpit reduces only the bracket presentation multiplier', () => {
  assert.equal(COCKPIT_BRACKET_OPACITY, 0.45);
  assert.equal(detectionBracketOpacity(true), 0.45);
  assert.equal(detectionBracketOpacity(false), 1);
  assert.equal(detectionBracketOpacity(undefined), 1);
});

test('detection owns and releases the Cockpit lifecycle listener', async () => {
  const source = await readFile(new URL('./detection.js', import.meta.url), 'utf8');
  assert.match(source, /addEventListener\('gev:cockpit-mode-changed', _cockpitModeListener\)/);
  assert.match(source, /removeEventListener\('gev:cockpit-mode-changed', _cockpitModeListener\)/);
  assert.match(
    source,
    /fade \* entry\.alpha \* bracketPresentationOpacity/,
    'Cockpit opacity must multiply bracket strokes only',
  );
  assert.doesNotMatch(
    source,
    /_drawCallout\(entry, fade \* bracketPresentationOpacity/,
    'Cockpit bracket de-emphasis must not dim callouts',
  );
});

