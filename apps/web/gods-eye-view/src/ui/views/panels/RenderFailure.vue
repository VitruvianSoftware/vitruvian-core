<!--
 Copyright (c) 2026 VitruvianSoftware

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
-->

<script setup>
import { nextTick, ref, watch } from 'vue';
import { storeToRefs } from 'pinia';
import { msg, t } from '../../../i18n/index.js';
import { useStatusStore } from '../../stores/status.js';
import UiButton from '../../kit/UiButton.vue';

// Published by installRenderFailureNotice() (src/render/cesium/renderFailure.js).
const { renderFailure: failure } = storeToRefs(useStatusStore());
const panel = ref(null);
const MESSAGES = {
  'context-lost': msg(
    "The browser took back the globe's 3D graphics. Layers and controls still work, but the map cannot draw until the page reloads.",
  ),
  'render-error': msg(
    'Rendering stopped after an error. Layers and controls still work, but the map is not updating.',
  ),
};
// Focus goes to the first action when the notice appears. When the globe
// draws again, it goes back, or to the map, unless the user moved it.
let focusBefore;
watch(
  () => Boolean(failure.value),
  async (shown) => {
    if (shown) {
      focusBefore = document.activeElement;
      await nextTick();
      panel.value?.querySelector('button')?.focus();
      return;
    }
    if (focusBefore === undefined) return;
    const previous = focusBefore;
    focusBefore = undefined;
    await nextTick();
    const active = document.activeElement;
    if (active && active !== document.body) return;
    if (previous?.isConnected && previous !== document.body) {
      previous.focus({ preventScroll: true });
      // A control disabled, hidden or made inert meanwhile does not take it.
      if (document.activeElement === previous) return;
    }
    focusMap();
  },
  { immediate: true },
);

// The map's keys (Enter to finish a drawing, Space to talk) read the canvas
// as the map. It stays focusable only until focus leaves or the globe is
// pressed; a press leaves focus on the page, as in Cesium.
function focusMap() {
  const canvas = document.querySelector(
    '#cesiumContainer .cesium-widget canvas',
  );
  if (!canvas) return;
  if (!canvas.hasAttribute('tabindex')) {
    canvas.tabIndex = -1;
    const done = new AbortController();
    const release = () => {
      done.abort();
      canvas.removeAttribute('tabindex');
    };
    canvas.addEventListener('blur', release, { signal: done.signal });
    canvas.addEventListener(
      'pointerdown',
      () => {
        release();
        canvas.blur();
      },
      { capture: true, signal: done.signal },
    );
  }
  canvas.focus({ preventScroll: true });
}
</script>

<template>
  <div v-if="failure" id="render-failure" ref="panel" role="alertdialog" aria-labelledby="render-failure-title" aria-describedby="render-failure-message">
    <h2 id="render-failure-title">{{ t('The globe stopped drawing') }}</h2>
    <p id="render-failure-message">{{ t(MESSAGES[failure.reason] ?? MESSAGES['render-error']) }}</p>
    <p v-if="failure.detail" class="render-failure-detail" translate="no">{{ failure.detail }}</p>
    <p v-if="failure.reset" class="render-failure-hint">{{ t('Reset view reloads the app without the view restored from the address bar.') }}</p>
    <div v-if="failure.retry || failure.reset" class="render-failure-actions">
      <UiButton v-if="failure.retry" class="gev-action-button render-failure-retry" :onClick="failure.retry">{{ failure.reason === 'context-lost' ? t('Reload') : t('Retry') }}</UiButton>
      <UiButton v-if="failure.reset" class="gev-action-button render-failure-reset" :onClick="failure.reset">{{ t('Reset view') }}</UiButton>
    </div>
  </div>
</template>
