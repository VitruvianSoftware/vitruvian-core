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
import { msg, t } from '../../../i18n/index.js';
import UiButton from '../../kit/UiButton.vue';
import { useDisplayStore } from '../../stores/display.js';

// The visual presets and map source at the top of the Visual panel. The same
// choices the command dock's tray offers, through the same Display store
// actions, so either surface stays in step with the other.
const display = useDisplayStore();
const { style, mapSource, mapSourceControls } = storeToRefs(display);

const STYLES = [
  {
    name: 'normal',
    icon: '◯',
    label: msg('Normal'),
    key: '1',
    title: msg('Show the globe without a visual filter.'),
  },
  {
    name: 'retro',
    icon: '▦',
    label: msg('CRT'),
    key: '2',
    title: msg('Emulate a green phosphor CRT with scanlines and screen curvature.'),
  },
  {
    name: 'surveillance',
    icon: '🌙',
    label: msg('NVG'),
    key: '3',
    title: msg('Simulate night-vision goggles with green intensification and a tube vignette.'),
  },
  {
    name: 'thermal',
    icon: '🌡️',
    label: msg('FLIR'),
    key: '4',
    title: msg('Simulate FLIR-style thermal contrast. Turn up Ironbow for color.'),
  },
  {
    name: 'anime',
    icon: '✦',
    label: msg('Anime'),
    key: '5',
    title: msg('Apply bright cel-shaded color and illustrated outlines.'),
  },
  {
    name: 'noir',
    icon: '◐',
    label: msg('Noir'),
    key: '6',
    title: msg('Apply high-contrast monochrome film-noir grading.'),
  },
];

function selectMapSource(chip) {
  if (!chip.available) return;
  void mapSourceControls.value?.select(chip.id).catch(() => {});
}
</script>

<template>
  <section class="visual-presets" :aria-label="t('VISUAL PRESETS')">
    <p class="visual-presets__heading">{{ t('Look') }}</p>
    <div class="visual-presets__grid">
      <UiButton
        v-for="preset in STYLES"
        :key="preset.name"
        class="visual-presets__style"
        :pressed="(style?.name ?? 'normal') === preset.name"
        pressed-class="active"
        :data-style="preset.name"
        :title="t(preset.title)"
        @click="display.act('setStyle', preset.name)"
      >
        <span class="visual-presets__icon" aria-hidden="true">{{ preset.icon }}</span>
        <span class="visual-presets__label">{{ t(preset.label) }}</span>
        <kbd class="visual-presets__key">{{ preset.key }}</kbd>
      </UiButton>
    </div>
    <div class="visual-presets__heading visual-presets__heading--row">
      <span>{{ t('MAP SOURCE') }}</span>
      <span class="visual-presets__status" :class="{ warn: !!mapSource?.status.warn }">{{ mapSource ? mapSource.status.text : '3D' }}</span>
    </div>
    <div class="visual-presets__chips" role="group" :aria-label="t('Map source')">
      <UiButton
        v-for="chip in mapSource?.chips"
        :key="chip.id"
        class="visual-presets__chip"
        :class="{ unavailable: !chip.available }"
        :pressed="Boolean(chip.active)"
        pressed-class="active"
        :title="chip.title"
        :aria-disabled="String(!chip.available)"
        :aria-label="chip.ariaLabel"
        @click="selectMapSource(chip)"
        >{{ chip.label }}<small v-if="chip.requirement">{{ chip.requirement }}</small></UiButton
      >
    </div>
  </section>
</template>
