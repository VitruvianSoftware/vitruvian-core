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
import UiButton from '../kit/UiButton.vue';
import UiIcon from '../kit/UiIcon.vue';

// Keyed chips shared by rail cards; the owner decides what a click does.
// An `icon` chip shows a Material Symbol (named in index.html's `icon_names`
// subset) with its label as the accessible name and tip; an `action` chip
// (Zoom, Remove) is a plain button, not an on/off toggle.
defineProps({
  chips: { type: Array, default: () => [] },
  onSelect: { type: Function, default: () => {} },
});

const chipClass = (chip) =>
  `data-toggle-chip chip-${chip.state || (chip.active ? 'active' : 'idle')}${chip.icon ? ' chip-icon' : ''}`;
</script>

<template>
  <UiButton
    v-for="chip in chips"
    :key="chip.id"
    :data-chip-id="chip.id"
    :class="chipClass(chip)"
    :pressed="chip.action ? undefined : Boolean(chip.active)"
    pressed-class="active"
    :style="chip.color ? `--chip-color: ${chip.color}` : undefined"
    :data-chip-color="chip.color || undefined"
    :label="chip.icon ? chip.label : undefined"
    :title="chip.title || (chip.icon ? chip.label : undefined)"
    :disabled="Boolean(chip.disabled)"
    :aria-busy="String(Boolean(chip.busy))"
    @click="onSelect(chip)"
    ><UiIcon v-if="chip.icon" :name="chip.icon" :size="null" /><template
      v-else
      >{{ chip.label }}</template
    ></UiButton
  >
</template>
