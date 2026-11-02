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
import { t } from '../../i18n/index.js';
import RailCards from '../rail/RailCards.vue';
import RailTimeline from '../rail/RailTimeline.vue';

// Active weather: forecast and event cards, then the observed products with
// their shared history timeline. The owner computes every value shown.
defineProps({
  view: { type: Object, required: true },
  onParams: { type: Function, default: () => {} },
  onOpen: { type: Function, default: () => {} },
  transport: { type: Object, required: true },
});
</script>

<template>
  <section
    class="weather-readout"
    :hidden="view.hidden"
    :aria-label="t('Active weather')"
    ><div class="weather-cards"
      ><RailCards
        :cards="view.cards"
        card-class-name="weather-card"
        badge-class-name="weather-coverage"
        :on-params="onParams"
        :on-open="onOpen" /></div
    ><section
      class="weather-observed-group"
      :hidden="!view.observed"
      :aria-label="t('Observed history')"
      ><h3 class="panel-title">{{ t('Observed history') }}</h3
      ><div class="weather-observed-scope">{{ view.scope }}</div
      ><div class="weather-timeline-block" :hidden="!view.observed"
        ><RailTimeline
          :state="view.timeline"
          slider-class-name="weather-timeline"
          :heading="false"
          :on-commit="transport.onCommit"
          :on-preview="transport.onPreview"
          :on-step="transport.onStep"
          :on-latest="transport.onLatest"
          :on-play="transport.onPlay" /></div
      ><div class="weather-cards"
        ><RailCards
          :cards="view.observedCards"
          card-class-name="weather-card"
          badge-class-name="weather-coverage"
          :on-params="onParams"
          :on-open="onOpen" /></div></section
  ></section>
</template>
