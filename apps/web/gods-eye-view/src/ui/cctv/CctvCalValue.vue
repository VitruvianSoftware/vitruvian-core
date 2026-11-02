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
import { t } from '../../i18n/index.js';
import { useCctvStore } from '../stores/cctv.js';

// One click-to-type pose chip. The panel's delegated click starts an edit
// in CctvControls, which publishes it; the chip then holds a number input
// that ends the edit on Enter, blur or Escape.
const props = defineProps({
  field: { type: String, required: true },
  /** Message for the label shown before the first render. */
  label: { type: String, required: true },
});
const { view, calEdit } = storeToRefs(useCctvStore());
const edit = computed(() =>
  calEdit.value?.field === props.field ? calEdit.value : null,
);

// The draft is the user's once the input exists: the starting value is set
// on mount only, since re-renders would otherwise write it back.
const vDraft = {
  mounted(el, { value }) {
    el.value = value;
    el.focus();
    el.select();
  },
};

function onKeydown(event) {
  if (event.key === 'Enter') edit.value?.finish(true, event.target.value);
  else if (event.key === 'Escape') {
    event.preventDefault();
    edit.value?.finish(false);
  }
  event.stopPropagation();
}

function onBlur(event) {
  edit.value?.finish(true, event.target.value);
}
</script>

<template>
  <button
    class="cctv-cal-value"
    :data-cal-field="field"
    :disabled="edit ? false : view?.calibration.disabled"
    ><template v-if="edit"
      >{{ edit.label
      }}<input
        :key="edit.id"
        v-draft="edit.value"
        type="number"
        class="gev-field gev-field--inline cctv-cal-input"
        :step="edit.step"
        :aria-label="edit.ariaLabel"
        @keydown="onKeydown"
        @blur="onBlur"
        @click.stop /></template
    ><template v-else>{{
      view?.calibration.values[field] ?? `${t(label)} --`
    }}</template></button
  >
</template>
