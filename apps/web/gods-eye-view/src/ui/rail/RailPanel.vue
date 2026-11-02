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
import { storeToRefs } from 'pinia';
import { computed } from 'vue';
import UiPanel from '../kit/UiPanel.vue';
import { usePanelChromeStore } from '../stores/panelChrome.js';
import { vPanelState } from './panelState.js';

// A panel PanelChrome owns: a collapsible UiPanel whose state classes
// (vPanelState) and collapse button follow the panel chrome store, with the
// button's clicks forwarded to PanelChrome. Every other prop, attribute and
// slot passes through to UiPanel.
defineOptions({ inheritAttrs: false });
const props = defineProps({
  id: { type: String, required: true },
  /** Whether the markup starts collapsed, until PanelChrome presents it. */
  startCollapsed: { type: Boolean, default: false },
});

const chrome = usePanelChromeStore();
const { panels } = storeToRefs(chrome);
const collapsedNow = computed(
  () => panels.value[props.id]?.collapsed ?? props.startCollapsed,
);
</script>

<template>
  <UiPanel
    v-panel-state="props.id"
    v-bind="$attrs"
    :id="props.id"
    :class="{ collapsed: props.startCollapsed }"
    :data-panel-id="props.id"
    collapsible
    :collapsed="collapsedNow"
    @update:collapsed="chrome.act('toggle', props.id)"
  >
    <template v-for="(_, name) in $slots" #[name]
      ><slot :name="name"
    /></template>
  </UiPanel>
</template>
