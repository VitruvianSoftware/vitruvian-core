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
import { useAwarenessDirectionStore } from '../../stores/awarenessDirection.js';

// The Global Context compass and the nearest contacts' bearings, inside the
// viewer's container, as the awareness layer presents them.
const { overlay } = storeToRefs(useAwarenessDirectionStore());

// A part keeps no inline placement until the layer first places it.
const place = (part) =>
  part.left === null ? undefined : { left: part.left, top: part.top };
</script>

<template>
  <Teleport v-if="overlay" :to="overlay.container">
    <div id="military-awareness-direction-overlay" :hidden="overlay.hidden" aria-hidden="true"><span v-for="label in overlay.labels" :key="label.label" :class="`military-awareness-compass-label cardinal-${label.label.toLowerCase()}`" :data-bearing="String(label.bearing)" :style="place(label)">{{ label.label }}</span><div class="military-awareness-compass-ring" :style="overlay.ring ?? undefined"></div><span class="military-awareness-compass-heading" :style="place(overlay.heading)">{{ overlay.heading.text }}</span><div v-for="(marker, index) in overlay.markers" :key="index" class="military-awareness-direction-marker" :hidden="marker.hidden" :style="marker.style ?? undefined"><span class="military-awareness-direction-arrow" :style="marker.arrow ?? undefined">➜</span><span class="military-awareness-direction-label" :style="marker.caption.style ?? undefined">{{ marker.caption.text }}</span></div></div>
  </Teleport>
</template>
