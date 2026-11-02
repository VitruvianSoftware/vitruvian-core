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
import UiSelect from '../kit/UiSelect.js';
import { useCctvStore } from '../stores/cctv.js';

// The camera picker: the cameras in view and a closing note for those the
// view leaves out. It renders only when CctvControls publishes a picker,
// which re-applies the active camera, as on every layer notification.
const { picker } = storeToRefs(useCctvStore());

// The selection, applied once the options are in place.
const pick = (el, { value: selection }) => {
  if (!selection) return;
  if ('value' in selection) {
    if (el.value !== selection.value) el.value = selection.value;
  } else if (el.selectedIndex !== selection.index)
    el.selectedIndex = selection.index;
};
const vPick = { mounted: pick, updated: pick };
</script>

<template>
  <UiSelect v-pick="picker?.selection" :disabled="picker?.disabled"
    ><option
      v-for="option in picker?.options"
      :key="option.value"
      :value="option.value"
      >{{ option.label }}</option
    ><option v-if="picker?.note" value="" disabled data-cctv-outside>{{
      picker.note
    }}</option></UiSelect
  >
</template>
