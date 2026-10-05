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
import * as Cesium from 'cesium';
import { createControls } from './controls.js';
import { createSubject } from './subject.js';

test('passive Contacts releases its installation anchor and subject refresh cannot reclaim it', (t) => {
  const prior = globalThis.document;
  globalThis.document = { body: { classList: { contains: () => false } } };
  t.after(() => {
    globalThis.document = prior;
  });
  const anchors = [];
  const position = Cesium.Cartesian3.fromDegrees(-117.14, 32.87);
  const state = {
    enabled: true,
    passive: false,
    subject: {
      id: 'site',
      layerId: 'military-installations',
      label: 'Site',
      position,
    },
    sourceRevision: 'current',
    lastEvaluatedPosition: position,
    results: {},
  };
  const services = {
    installations: { setContextAnchor: (value) => anchors.push(value) },
  };
  let activations = 0;
  const parts = {
    dependencies: { activateOperationalContext: () => activations++ },
    queries: {
      collectSourceStates: () => ({}),
      sourceRevision: () => 'current',
    },
    navigation: { isFlightLayer: () => false },
    model: { awarenessRefreshRequired: () => false },
    rendering: { renderVisual() {}, scheduleDirectionOverlayUpdate() {} },
  };
  const controls = createControls({ state, services, parts }).methods;
  const subject = createSubject({ state, services, parts });
  subject.refreshSelectedSubject();
  assert.equal(anchors.length, 1);
  assert.ok(anchors[0] instanceof Cesium.Cartesian3);
  controls.setParams({ passive: true });
  assert.equal(anchors.at(-1), null);
  const released = anchors.length;
  subject.refreshSelectedSubject();
  subject.refreshSelectedSubject();
  assert.equal(
    anchors.length,
    released,
    'passive refresh must not reclaim the viewport',
  );
  controls.setParams({ passive: false });
  assert.equal(activations, 1);
  subject.refreshSelectedSubject();
  assert.ok(anchors.at(-1) instanceof Cesium.Cartesian3);
});
