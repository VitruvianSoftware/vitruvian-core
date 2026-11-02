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

// src/layers/launches/replayOverlay.test.mjs — the launches layer presents
// its replay vehicle overlay to subscribers, and the scene chrome renders it
// inside the globe container.
import '../../testSupport/registerDom.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp, nextTick } from 'vue';
import { createPinia } from 'pinia';
import { useMissionReplayStore } from '../../ui/stores/missionReplay.js';
import SceneChromeView from '../../ui/views/SceneChromeView.vue';
import { createOverlays } from './overlays.js';

function overlays() {
  const state = {
    _replayVehicleOverlay: null,
    _replayVehicleOverlayListeners: new Set(),
  };
  const parts = createOverlays({ state, services: {}, parts: {}, source: {} });
  return Object.assign(parts, { state });
}

test('subscribers get the overlay as it is created, hidden and removed, never twice the same', () => {
  const parts = overlays();
  const views = [];
  const unsubscribe = parts.subscribeReplayOverlay((view) => views.push(view));
  assert.deepEqual(views, [null], 'a subscriber starts from the current one');
  parts.createReplayVehicleOverlay();
  parts.createReplayVehicleOverlay();
  assert.equal(views.length, 2);
  assert.equal(views[1].visible, false);
  parts.hideReplayVehicleOverlay();
  assert.equal(views.length, 2, 'an unchanged overlay is not sent again');
  parts.destroyReplayVehicleOverlay();
  assert.equal(views.at(-1), null);
  parts.hideReplayVehicleOverlay();
  unsubscribe();
  parts.createReplayVehicleOverlay();
  assert.equal(views.length, 3);
});

test('the scene chrome renders the overlay in the globe container', async (t) => {
  document.body.replaceChildren();
  const pinia = createPinia();
  const app = createApp(SceneChromeView).use(pinia);
  app.mount(document.body.appendChild(document.createElement('div')));
  t.after(() => app.unmount());
  const store = useMissionReplayStore(pinia);
  const node = () => document.querySelector('.mission-replay-vehicle-overlay');
  const parts = overlays();
  parts.subscribeReplayOverlay((view) => store.publish(view));
  await nextTick();
  assert.equal(node(), null);
  parts.createReplayVehicleOverlay();
  await nextTick();
  const element = node();
  assert.equal(element.parentElement.id, 'cesiumContainer');
  assert.equal(element.hidden, true);
  assert.equal(element.getAttribute('aria-hidden'), 'true');
  assert.equal(element.hasAttribute('data-mode'), false);
  assert.equal(
    element.querySelectorAll('.mission-replay-thrust ellipse').length,
    6,
  );
  // A frame as updateReplayVehicleOverlay presents it.
  parts.state._replayVehicleOverlay = {
    ...parts.state._replayVehicleOverlay,
    visible: true,
    mode: 'ascent',
    thrusting: true,
    paused: false,
    transform: 'translate3d(10px, 20px, 0) translate(-50%, -50%)',
    rotation: '12deg',
    iconOpacity: '0.5',
    labelOpacity: '1',
    title: 'ASCENT REPLAY · TEST',
    detail: 'T+00:10',
  };
  store.publish(parts.state._replayVehicleOverlay);
  await nextTick();
  assert.equal(element.hidden, false);
  assert.equal(element.dataset.mode, 'ascent');
  assert.ok(element.classList.contains('is-thrusting'));
  assert.equal(element.classList.contains('is-paused'), false);
  assert.equal(
    element.style.getPropertyValue('--mission-replay-rotation'),
    '12deg',
  );
  assert.match(element.style.transform, /translate3d\(10px, 20px, 0(px)?\)/);
  assert.equal(
    element.querySelector('.mission-replay-flight-symbol').style.opacity,
    '0.5',
  );
  assert.equal(
    element.querySelector('.mission-replay-orbit-dot').style.opacity,
    '0.5',
  );
  assert.equal(
    element.querySelector('.mission-replay-overlay-callout').style.opacity,
    '1',
  );
  assert.equal(
    element.querySelector('[data-replay-overlay-title]').textContent,
    'ASCENT REPLAY · TEST',
  );
  assert.equal(
    element.querySelector('[data-replay-overlay-detail]').textContent,
    'T+00:10',
  );
  parts.hideReplayVehicleOverlay();
  await nextTick();
  assert.equal(element.hidden, true);
  assert.equal(element.classList.contains('is-thrusting'), false);
  assert.equal(
    element.dataset.mode,
    'ascent',
    'hiding keeps the mode, as before',
  );
  parts.destroyReplayVehicleOverlay();
  await nextTick();
  assert.equal(node(), null);
});
