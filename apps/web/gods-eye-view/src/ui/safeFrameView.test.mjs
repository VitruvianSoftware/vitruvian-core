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

// src/ui/safeFrameView.test.mjs — the recording safe frame renders what
// RecordingControls publishes to the recording store.
import '../testSupport/registerDom.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp, nextTick } from 'vue';
import { createPinia } from 'pinia';
import { useRecordingStore } from './stores/recording.js';
import { RecordingControls } from './recordingControls.js';
import SceneChromeView from './views/SceneChromeView.vue';

test('the safe frame shows while a recording composes in it', async (t) => {
  document.body.replaceChildren();
  const pinia = createPinia();
  const app = createApp(SceneChromeView).use(pinia);
  app.mount(document.body.appendChild(document.createElement('div')));
  t.after(() => app.unmount());
  const store = useRecordingStore(pinia);
  const recording = new RecordingControls({
    syncShareState() {},
    syncHudControls() {},
    publishSafeFrame: (frame) => store.publishSafeFrame(frame),
  });
  recording.hud = {
    getMode: () => 'auto',
    getVariant: () => 'tactical',
    setMode() {},
    setVariant() {},
  };
  t.after(() => recording.destroy());
  const overlay = document.getElementById('safe-frame-overlay');
  const classes = () =>
    ['active', 'ratio-16-9', 'ratio-9-16'].filter((name) =>
      overlay.classList.contains(name),
    );
  recording._initRecordingOverlay();
  await nextTick();
  assert.deepEqual(classes(), []);
  recording.setRecordingMode(true, { safeFrame: '9:16' });
  await nextTick();
  assert.deepEqual(classes(), ['active', 'ratio-9-16']);
  recording.setRecordingMode(true);
  await nextTick();
  assert.deepEqual(classes(), ['active', 'ratio-16-9']);
  recording.setRecordingMode(false);
  await nextTick();
  assert.deepEqual(classes(), []);
  // Any frame but 9:16, even none named, records in 16:9.
  recording.setRecordingMode(true, { safeFrame: null });
  await nextTick();
  assert.deepEqual(classes(), ['active', 'ratio-16-9']);
  recording.setRecordingMode(true, { safeFrame: '4:3' });
  await nextTick();
  assert.deepEqual(classes(), ['active', 'ratio-16-9']);
  // A recording that ends with its controls takes its frame with it.
  recording.destroy();
  await nextTick();
  assert.deepEqual(classes(), []);
});
