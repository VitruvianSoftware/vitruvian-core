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
import UiButton from './UiButton.vue';
import UiIcon from './UiIcon.vue';

// Core's close, dismiss and clear button: a UiButton with a fixed glyph and
// a required accessible name. `glyph` is `times` (the × character) or `icon`
// (the Material `close` symbol, sized by the caller's stylesheet). Attributes
// and classes pass through to the button, so each site keeps its id, its
// feature class and its look; a `title` passed in is its tip, and without
// one it has none. The kit class `ui-close-button` (close-button.css) is
// Core's common look, a bare glyph: no padding, border or background of its
// own, and a pointer. Its rule selects one class and loads before the
// feature stylesheets, so a feature rule still sets the size, colour, hover
// and any surface. `bare` leaves the kit look off, for a button whose own
// skin sets its padding and border.
const props = defineProps({
  /** The accessible name (aria-label). */
  label: { type: String, required: true },
  glyph: {
    type: String,
    default: 'times',
    validator: (value) => ['times', 'icon'].includes(value),
  },
  bare: { type: Boolean, default: false },
});
const emit = defineEmits(['click']);
</script>

<template>
  <UiButton
    :class="{ 'ui-close-button': !props.bare }"
    :label="props.label"
    :native-title="false"
    @click="emit('click', $event)"
    ><UiIcon v-if="props.glyph === 'icon'" name="close" :size="null" /><template
      v-else
      >×</template
    ></UiButton
  >
</template>
