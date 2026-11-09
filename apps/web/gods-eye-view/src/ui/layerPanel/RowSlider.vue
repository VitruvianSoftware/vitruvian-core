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
import UiSlider from '../kit/UiSlider.js';

// A row's quantitative slider (e.g. the Active Fires minimum-FRP filter).
// `track` is a CSS background painting the runnable track, so a color ramp
// doubles as the legend; each tick sits at `at` (0..1) along it. The input
// holds its position while focused, so a refresh from its own tick never
// moves the thumb under the pointer.
defineProps({
  slider: { type: Object, required: true },
  onInput: { type: Function, default: () => {} },
});
</script>

<template>
  <div class="data-toggle-slider" :data-slider-id="slider.id"
    ><div class="data-toggle-slider-head"
      ><span class="data-toggle-slider-label">{{ slider.label }}</span
      ><span class="data-toggle-slider-value gev-slider-value">{{
        slider.valueText
      }}</span></div
    ><UiSlider
      class="data-toggle-slider-input"
      :data-slider-id="slider.id"
      :min="slider.min"
      :max="slider.max"
      :step="slider.step ?? 1"
      :model-value="slider.value"
      hold
      :aria-label="slider.ariaLabel || undefined"
      :aria-valuetext="slider.valueText || undefined"
      :style="slider.track ? { '--slider-track': slider.track } : undefined"
      @update:model-value="onInput"
    /><div class="data-toggle-slider-ticks"
      ><span
        v-for="tick in slider.ticks || []"
        :key="tick.at"
        class="data-toggle-slider-tick"
        :style="{ '--at': `${(tick.at * 100).toFixed(2)}%` }"
        >{{ tick.label }}</span
      ></div
    ></div
  >
</template>
