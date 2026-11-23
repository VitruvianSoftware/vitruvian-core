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
import { nextTick, ref, watch } from 'vue';
import { t } from '../../../i18n/index.js';
import RailPanel from '../../rail/RailPanel.vue';
import { useSpaceMissionsStore } from '../../stores/spaceMissions.js';
import MissionDetail from './MissionDetail.vue';
import MissionRoster from './MissionRoster.vue';

const { enabled, mission } = storeToRefs(useSpaceMissionsStore());
const host = ref(null);

watch(
  () => Boolean(mission.value),
  async (selected) => {
    // Keep keyboard focus in the panel when the selected mission replaces the roster.
    if (!host.value?.contains(document.activeElement)) return;
    await nextTick();
    const control = selected
      ? '[data-mission-close]'
      : '[data-mission-roster-id]';
    host.value?.querySelector(control)?.focus();
  },
);
</script>

<template>
  <RailPanel
    id="space-missions-panel"
    :title="t('Space Missions')"
    :hidden="!enabled"
    :glow="false"
    start-collapsed
    sideways
    scroll
    rail-scroller
  >
    <div id="space-mission-panel-host" ref="host">
      <MissionRoster />
      <MissionDetail />
    </div>
  </RailPanel>
</template>
