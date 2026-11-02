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
import UiPanelToggle from '../kit/UiPanelToggle.vue';
import { usePanelChromeStore } from '../stores/panelChrome.js';

// The collapse button of a panel not built on UiPanel: it follows the panel's
// state in the panel chrome store, and a click asks PanelChrome to toggle it.
// Until PanelChrome presents the panel it follows the markup's state.
const props = defineProps({
  target: { type: String, required: true },
  /** The panel's name in "Expand {name}", already translated. */
  name: { type: String, default: undefined },
  sideways: { type: Boolean, default: false },
  /** Whether the panel's markup starts collapsed. */
  startCollapsed: { type: Boolean, default: false },
});

const chrome = usePanelChromeStore();
const { panels } = storeToRefs(chrome);
const collapsedNow = computed(
  () => panels.value[props.target]?.collapsed ?? props.startCollapsed,
);
</script>

<template>
  <UiPanelToggle
    :target="target"
    :name="name"
    :sideways="sideways"
    :collapsed="collapsedNow"
    @update:collapsed="chrome.act('toggle', target)"
  />
</template>
