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

// src/layers/installations/labelBoxClick.test.mjs — a click on a mapped
// installation's label box finds the site, read from the box the overlay
// painted for it, unless another layer's card or label that takes clicks is
// painted there.
import assert from 'node:assert/strict';
import test from 'node:test';
import { createControls } from './controls.js';

const RECORD = Object.freeze({
  id: 'base',
  kind: 'installation',
  name: 'Base',
  class: 'base',
  latitude: 10,
  longitude: 20,
});

const inside = (box, { x, y }) =>
  x >= box.x && x <= box.x + box.w && y >= box.y && y <= box.y + box.h;

/**
 * The installations controls over a fake overlay: `cards` are the hit rects
 * of entries that take clicks (other layers'), `labels` the boxes painted
 * for this layer's labels, which are not cards.
 */
function controlsWith({ cards = [], labels = {} }) {
  const overlayHost = {
    // As the world overlay does: the last painted card under the point wins.
    hitTest(x, y) {
      for (let i = cards.length - 1; i >= 0; i--)
        if (inside(cards[i], { x, y }))
          return { sourceId: cards[i].sourceId, entryId: cards[i].entryId };
      return null;
    },
  };
  const namedMarkers = {
    labelAt: (position) =>
      Object.keys(labels).find((id) => inside(labels[id], position)) ?? null,
  };
  const controls = createControls({
    state: {
      enabled: true,
      records: [RECORD],
      recordById: new Map([[RECORD.id, RECORD]]),
    },
    services: {},
    parts: {
      rendering: { installationSurfaceHeightM: () => 0 },
      namedMarkers,
    },
    source: {},
    overlayHost,
  });
  return controls.methods;
}

const BASE_LABEL = { x: 100, y: 100, w: 80, h: 20 };

test("a click on the site's own label box finds the site", () => {
  const methods = controlsWith({ labels: { base: BASE_LABEL } });
  assert.equal(methods.findAt({ x: 120, y: 110 })?.id, 'base');
  assert.equal(methods.findAt({ x: 10, y: 10 }), null, 'outside every box');
  assert.equal(methods.findAt(null), null);
});

test("another layer's card painted over the site's label keeps the click", () => {
  const methods = controlsWith({
    labels: { base: BASE_LABEL },
    cards: [
      { sourceId: 'flights', entryId: 'abc123', x: 110, y: 105, w: 40, h: 12 },
    ],
  });
  assert.equal(
    methods.findAt({ x: 120, y: 110 }),
    null,
    'the flight card is on top',
  );
  assert.equal(
    methods.findAt({ x: 170, y: 110 })?.id,
    'base',
    'past the card, the site is found',
  );
});
