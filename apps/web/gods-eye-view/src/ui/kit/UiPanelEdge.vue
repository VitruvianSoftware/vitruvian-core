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
import { computed, onMounted, ref } from 'vue';
import { t } from '../../i18n/index.js';
import { panelEdge, panelSide, togglePanelEdge } from '../panelEdge.js';

// A panel header's edge switch: it slides this side's panels over their rail
// to the screen edge, and back. The side comes from the column the panel is in.
const button = ref(null);
const side = ref('left');
const on = computed(() => panelEdge.value[side.value]);
function toggle() {
  side.value = panelSide(button.value);
  togglePanelEdge(side.value);
}
function sync() {
  side.value = panelSide(button.value);
}
// The layout moves some panels to the right column after they mount, so the
// side is read again once that has happened.
onMounted(() => {
  sync();
  globalThis.requestAnimationFrame?.(sync);
});
const icon = computed(() =>
  side.value === 'right' ? 'align_horizontal_right' : 'align_horizontal_left',
);
const label = computed(() =>
  on.value
    ? t('Move panels back beside the rail')
    : t('Move panels over the rail, to the edge'),
);
</script>

<template>
  <button
    ref="button"
    type="button"
    class="ui-panel-edge panel-edge-btn"
    :aria-pressed="String(on)"
    :aria-label="label"
    :title="label"
    @pointerenter="sync"
    @focus="sync"
    @click="toggle"
  >
    <span class="material-symbols-outlined" aria-hidden="true">{{ icon }}</span>
  </button>
</template>
