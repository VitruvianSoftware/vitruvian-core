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
import { DETECTION_THEME_MAP } from './worldOverlayTokens.js';
import { TRANSIT_TIER_KEYS } from '../data/transitPresetStyle.js';

test('every detection theme carries a distinct bracket colour for every transit mode', () => {
  // The detection canvas composites above the post-FX chain, so these are
  // literal screen colours in every preset — the mode signal the sprites
  // lose under NVG and FLIR. A missing key would silently fall back to the
  // theme's line colour and every mode would bracket alike.
  for (const [name, theme] of Object.entries(DETECTION_THEME_MAP)) {
    const seen = new Set();
    for (const key of TRANSIT_TIER_KEYS) {
      const colour = theme.tiers?.[key];
      assert.match(colour || '', /^#[0-9a-f]{6}$/i, `${name} ${key}`);
      if (key !== 'transit_unknown') seen.add(colour.toLowerCase());
    }
    assert.equal(
      seen.size,
      TRANSIT_TIER_KEYS.length - 1,
      `${name}: the five real modes differ`,
    );
  }
});
