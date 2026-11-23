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
import { createInteraction } from './interaction.js';
import * as picking from '../../data/pickRegistry.js';

/** The cable click handler, with its click and overlay seams faked. */
function harness({ overlayTop = null } = {}) {
  let onClick = null;
  const picked = [];
  let top = overlayTop;
  const interaction = createInteraction({
    state: { _enabled: true, _clickSubscription: null },
    parts: {
      rendering: {
        pickInfo: (hit) => {
          picked.push(hit);
          return null;
        },
      },
    },
    inputFor: () => ({
      onClick: (fn) => {
        onClick = fn;
        return () => (onClick = null);
      },
    }),
    overlayHost: { hitTest: () => top },
    // The card on top at a click, as the registry answers from the host.
    picking: { clickCard: () => top },
  });
  interaction.beginInteraction({});
  return {
    picked,
    setTop: (next) => {
      top = next;
    },
    click: () =>
      onClick({
        screenPosition: { x: 5, y: 5 },
        drawHit: { set: 'c', id: 'x' },
      }),
  };
}

// Cable labels are not interactive: an overlay entry under the pointer is
// another layer's card or label painted over the cable (a quake card), and
// that layer takes the click, so the cable does not also fly the camera.
test('a card painted over a cable keeps its click; with none the cable reads the pick', () => {
  const h = harness({
    overlayTop: { sourceId: 'earthquake-card', entryId: 'earthquake-card:ak1' },
  });
  h.click();
  assert.equal(h.picked.length, 0, 'the cable stands aside');
  h.setTop(null);
  h.click();
  assert.equal(
    h.picked.length,
    1,
    'with no card on top, the cable reads its pick',
  );
});
