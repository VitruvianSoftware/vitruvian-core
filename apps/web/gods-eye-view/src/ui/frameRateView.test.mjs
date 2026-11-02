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

// src/ui/frameRateView.test.mjs — the title bar's FPS readout renders what
// createFrameRateMonitor() publishes and toggles with the backquote key.
import '../testSupport/registerDom.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp, nextTick } from 'vue';
import { createPinia } from 'pinia';
import { useStatusStore } from './stores/status.js';
import { createFrameRateMonitor } from './frameRateMonitor.js';
import SceneChromeView from './views/SceneChromeView.vue';

test('the FPS readout sits in the title bar, hidden until the backquote key', async (t) => {
  document.body.replaceChildren();
  const pinia = createPinia();
  const app = createApp(SceneChromeView).use(pinia);
  app.mount(document.body.appendChild(document.createElement('div')));
  t.after(() => app.unmount());
  const readout = () =>
    document.querySelector('#title-bar .frame-rate-readout');
  assert.equal(readout(), null, 'no readout without a monitor');
  const monitor = createFrameRateMonitor({
    viewer: { scene: { postRender: { addEventListener: () => () => {} } } },
    store: useStatusStore(pinia),
  });
  t.after(() => monitor.destroy());
  await nextTick();
  const element = readout();
  assert.ok(element.previousElementSibling.classList.contains('subtitle'));
  assert.ok(element.classList.contains('scene-text-holdout'));
  assert.equal(element.hidden, true);
  assert.equal(element.textContent, 'FPS —');
  assert.equal(
    element.title,
    'Rendered globe frames per second · toggle with `',
  );
  document.dispatchEvent(
    new KeyboardEvent('keydown', { key: '`', bubbles: true, cancelable: true }),
  );
  await nextTick();
  assert.equal(readout().hidden, false);
  monitor.destroy();
  await nextTick();
  assert.equal(readout(), null);
});
