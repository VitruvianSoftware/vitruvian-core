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
import UiSegmented from '../kit/UiSegmented.vue';

// A row's one-of-many switch (e.g. Active Fires confidence). Options carry
// the same fields as chips, so the owner resolves a choice the way it
// resolves a chip; `label` is an optional caption beside the group.
defineProps({
  segmented: { type: Object, required: true },
  onSelect: { type: Function, default: () => {} },
});

const options = (segmented) =>
  (segmented.options || []).map((option) => ({
    value: option.id,
    label: option.label,
    disabled: Boolean(option.disabled),
    attrs: { 'data-chip-id': option.id, title: option.title || undefined },
  }));
const activeId = (segmented) =>
  (segmented.options || []).find((option) => option.active)?.id;
</script>

<template>
  <span
    v-if="segmented.label"
    class="data-toggle-segmented-label"
    :data-segmented-caption-for="segmented.id"
    >{{ segmented.label }}</span
  ><UiSegmented
    class="data-toggle-segmented"
    :data-segmented-id="segmented.id"
    :model-value="activeId(segmented)"
    :options="options(segmented)"
    :label="segmented.ariaLabel || segmented.label || ''"
    item-class="data-toggle-segment"
    @update:model-value="onSelect"
  />
</template>
