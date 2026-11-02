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
import { shallowRef, watch } from 'vue';
import {
  advanceRollingValue,
  createRollingState,
} from '../../cockpitRollingValue.js';

// One Cockpit odometer readout. Every reading the controller publishes is a
// fresh object, so each one restamps the throttle just as the controller's
// own repeated writes did. The view takes the last reading of a tick, so
// the controller publishes one per HUD update. Until the first reading, the
// placeholder shows.
// The template is one line: templates keep whitespace, and a space between
// glyphs would show.
const props = defineProps({
  tag: { type: String, default: 'span' },
  reading: { type: Object, default: null },
  placeholder: { type: String, required: true },
  circularRange: { type: Number, default: null },
});

const state = shallowRef(createRollingState());
watch(
  () => props.reading,
  (reading) => {
    if (!reading) return;
    state.value = advanceRollingValue(state.value, reading.text, reading.value, {
      circularRange: props.circularRange,
      immediate: reading.immediate,
    });
  },
  { immediate: true },
);
</script>

<template>
  <component :is="tag" :aria-label="state.text"><template v-if="!state.tokens">{{ placeholder }}</template><span v-for="(token, index) in state.tokens" :key="`${state.generation}:${index}`" :class="token.className" aria-hidden="true"><span v-if="token.track" class="cockpit-roll-track"><span>{{ token.track[0] }}</span><span>{{ token.track[1] }}</span></span><template v-else>{{ token.text }}</template></span></component>
</template>
