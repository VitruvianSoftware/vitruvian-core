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
import { onBeforeUnmount, ref } from 'vue';

const props = defineProps({
  text: { type: String, required: true },
  /** Which side of the trigger the tip opens on. */
  side: { type: String, default: 'right' },
  disabled: { type: Boolean, default: false },
  /** Milliseconds the pointer rests before the tip shows. */
  delay: { type: Number, default: 0 },
});

const open = ref(false);
let timer = null;

function show() {
  if (props.disabled) return;
  clearTimeout(timer);
  if (props.delay > 0)
    timer = setTimeout(() => (open.value = true), props.delay);
  else open.value = true;
}

function hide() {
  clearTimeout(timer);
  timer = null;
  open.value = false;
}

onBeforeUnmount(hide);
</script>

<template>
  <span
    class="ui-tooltip"
    @pointerenter="show"
    @pointerleave="hide"
    @focusin="show"
    @focusout="hide"
  >
    <slot />
    <span
      v-if="open && !disabled"
      class="ui-tooltip__tip"
      :class="`ui-tooltip__tip--${side}`"
      role="tooltip"
      >{{ text }}</span
    >
  </span>
</template>
