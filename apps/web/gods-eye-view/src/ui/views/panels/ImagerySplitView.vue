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
import { useImagerySplitStore } from '../../stores/imagerySplit.js';

// The before/after imagery dividers, as their splits (src/ui/imagerySplit.js)
// present them. Each line is a direct child of the body, above the rails; its
// handle reports pointer and keyboard input back to its split.
const { splits } = storeToRefs(useImagerySplitStore());
const optional = (value) => value ?? undefined;
</script>

<template>
  <Teleport to="body">
    <div v-for="split in splits" :key="split.key" :id="optional(split.view.id)" :hidden="split.view.hidden"><span class="before" :title="optional(split.view.beforeTitle)">{{ split.view.beforeLabel }}</span><button type="button" :class="optional(split.view.handleClass)" role="slider" :aria-label="optional(split.view.ariaLabel)" aria-valuemin="0" aria-valuemax="100" aria-orientation="horizontal" :aria-valuenow="split.view.valueNow" :aria-valuetext="split.view.valueText" @pointerdown="split.controls.pointerdown($event)" @pointermove="split.controls.pointermove($event)" @pointerup="split.controls.pointerup($event)" @pointercancel="split.controls.pointerup($event)" @keydown="split.controls.keydown($event)">↔</button><span class="after" :title="optional(split.view.afterTitle)">{{ split.view.afterLabel }}</span></div>
  </Teleport>
</template>
