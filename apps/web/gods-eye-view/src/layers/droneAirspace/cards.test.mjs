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
import {
  droneAirspaceAnchorDegrees,
  droneAirspaceAccent,
  buildDroneAirspaceCard,
} from './cards.js';

const square = [
  [-77.2, 38.8],
  [-77.0, 38.8],
  [-77.0, 39.0],
  [-77.2, 39.0],
  [-77.2, 38.8],
];
const tiny = [
  [-76.01, 38.0],
  [-76.0, 38.0],
  [-76.0, 38.01],
  [-76.01, 38.0],
];

test('the card anchors at the centroid of the largest polygon', () => {
  const anchor = droneAirspaceAnchorDegrees([[tiny], [square]]);
  assert.ok(Math.abs(anchor.lon - -77.1) < 1e-9);
  assert.ok(Math.abs(anchor.lat - 38.9) < 1e-9);
});

test('a prohibited zone card names the type, altitudes and the disclaimer', () => {
  const card = buildDroneAirspaceCard({
    stableId: '310',
    name: 'P-56',
    typeCode: 'P',
    type: 'Prohibited',
    lowerAltitude: 'SFC',
    upperAltitude: '18,000 ft MSL',
    timesOfUse: 'CONTINUOUS',
    agency: 'WASHINGTON CENTER',
    city: 'WASHINGTON',
    state: 'DC',
  });
  assert.equal(card.id, 'drone-airspace-card:310');
  assert.equal(card.title, 'PROHIBITED · P-56');
  assert.deepEqual(card.details, [
    'Prohibited · SFC to 18,000 ft MSL · CONTINUOUS',
    'WASHINGTON, DC',
    'WASHINGTON CENTER',
    'Informational only · not for flight planning',
  ]);
  assert.equal(card.accent, droneAirspaceAccent('P'));
  assert.equal(card.interactive, false);
  assert.equal(card.selected, true);
});

test('missing attributes degrade to available facts instead of placeholders', () => {
  const card = buildDroneAirspaceCard({
    stableId: 'x',
    name: null,
    typeCode: 'R',
    type: 'Restricted',
    lowerAltitude: null,
    upperAltitude: null,
    timesOfUse: null,
    agency: null,
    city: null,
    state: null,
  });
  assert.equal(card.title, 'RESTRICTED · Unnamed zone');
  assert.deepEqual(card.details, [
    'Restricted',
    'Informational only · not for flight planning',
  ]);
  assert.equal(card.accent, droneAirspaceAccent('R'));
});
