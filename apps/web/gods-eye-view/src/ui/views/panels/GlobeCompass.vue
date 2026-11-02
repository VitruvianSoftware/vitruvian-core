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
import { t } from '../../../i18n/index.js';
import { useGlobeActionsStore } from '../../stores/globeActions.js';

// The north-up button: its needle and label follow the published heading,
// which changes on every frame a rotating camera draws. Before the camera
// controls first publish, it shows no heading.
defineEmits(['click']);
const { camera } = storeToRefs(useGlobeActionsStore());
const heading = computed(() => camera.value?.heading);
const label = computed(() =>
  heading.value == null
    ? t('Reset map to north up')
    : t('Reset map to north up. Current heading {heading} degrees', {
        heading: heading.value,
      }),
);
</script>

<template>
<button id="north-up-view" type="button" :aria-label="label" :data-north-up="heading == null ? undefined : String(heading === 0)" :style="heading == null ? undefined : { '--camera-heading': `${heading}deg` }" :title="t('Reset map bearing to north')" @click="$emit('click')">
  <span class="camera-compass-n" aria-hidden="true">N</span>
  <span class="camera-compass-needle material-symbols-outlined" aria-hidden="true">navigation</span>
</button>
</template>
