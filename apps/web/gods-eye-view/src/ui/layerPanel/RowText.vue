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
import { computed } from 'vue';
import { rowTextRuns } from '../layerRowText.js';

// Row text that wraps well in every language: hyphenated codes and the
// space before a " · " separator never break (see rowTextRuns).
const props = defineProps({
  tag: { type: String, default: 'span' },
  text: { type: String, default: '' },
});
const runs = computed(() => rowTextRuns(props.text));
</script>

<template>
  <component :is="tag"
    ><template v-if="runs"
      ><span
        v-for="(run, index) in runs"
        :key="index"
        v-bind="run.keep ? { class: 'data-keep' } : {}"
        >{{ run.text }}</span
      ></template
    ><template v-else>{{ text }}</template></component
  >
</template>
