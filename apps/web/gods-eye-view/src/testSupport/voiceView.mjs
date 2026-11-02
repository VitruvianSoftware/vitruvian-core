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

import { createApp, h, nextTick } from 'vue';
import { createPinia, storeToRefs } from 'pinia';
import { useVoiceStore } from '../ui/stores/voice.js';
import VoiceControl from '../ui/views/panels/VoiceControl.vue';

/**
 * Render whichever voice control the store presents, as the command dock
 * does, into the current document. Import registerDom.mjs first.
 * @param {import('node:test').TestContext} t
 * @returns {{pinia: import('pinia').Pinia, settle: () => Promise<void>}}
 */
export function mountVoiceView(t) {
  const doc = globalThis.document;
  // happy-dom lacks the browser's `[hidden]` rule, which visibility checks
  // and focus moves rely on.
  if (!doc.getElementById('test-ua-hidden')) {
    const style = doc.head.appendChild(doc.createElement('style'));
    style.id = 'test-ua-hidden';
    style.textContent = '[hidden] { display: none; }';
  }
  doc.body.replaceChildren();
  const host = doc.body.appendChild(doc.createElement('div'));
  const pinia = createPinia();
  const { view } = storeToRefs(useVoiceStore(pinia));
  const app = createApp({
    render: () =>
      view.value
        ? h(VoiceControl, { key: view.value.id, view: view.value })
        : null,
  }).use(pinia);
  app.mount(host);
  t.after(() => app.unmount());
  // Renders, then any focus the owners asked for after it.
  const settle = async () => {
    await nextTick();
    await nextTick();
  };
  return { pinia, settle };
}
