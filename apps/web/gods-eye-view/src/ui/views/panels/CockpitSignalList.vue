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
import { vFocusSafeChildren } from '../../rail/focusSafeChildren.js';
import { useCockpitStore } from '../../stores/cockpit.js';

// The Cockpit's live signal rows. The Cockpit controller presents them;
// until it does, the list is empty. Rows reorder several times a second,
// so the list keeps keyboard focus on its row while the others move, and
// moves focus to `leave` before the focused row goes. Selection stays with
// the controller's click listener. The template is one line: templates keep
// whitespace.
defineProps({
  leave: { type: Function, required: true },
});
const { signals } = storeToRefs(useCockpitStore());
const rows = computed(() => signals.value ?? []);
</script>

<template>
  <ol id="cockpit-signal-list" v-focus-safe-children="leave" class="cockpit-signal-list" aria-live="polite"><li v-for="row in rows" :key="row.key" :class="row.className" :data-signal-key="row.key"><time>{{ row.time }}</time><div><button v-if="row.target" type="button" class="cockpit-signal-target" :data-signal-layer="row.target.layerId" :data-signal-id="row.target.id" :aria-label="row.target.label"><span class="cockpit-signal-target-label">{{ row.title }}</span><span class="cockpit-signal-target-rule" aria-hidden="true"></span><span class="material-symbols-outlined cockpit-signal-target-chevron" aria-hidden="true">chevron_right</span></button><strong v-else>{{ row.title }}</strong><span>{{ row.detail }}</span></div></li></ol>
</template>
