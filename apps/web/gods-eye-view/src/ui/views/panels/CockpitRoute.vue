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
import { createRouteState } from '../../cockpitInstrumentState.js';
import { useCockpitStore } from '../../stores/cockpit.js';

// The Cockpit flight plan card. The Cockpit controller presents the route's
// endpoints and whether a destination direction exists; until it does, the
// card stays hidden.
const { route } = storeToRefs(useCockpitStore());
const initial = createRouteState();
const r = computed(() => route.value ?? initial);
</script>

<template>
  <section id="cockpit-route" class="cockpit-route-card" :aria-label="r.kind === 'vessel' ? t('Reported voyage') : t('Estimated flight plan')" :hidden="!r.visible">
    <div class="cockpit-route-heading">
      <span class="cockpit-route-kicker">{{ r.kind === 'vessel' ? t('REPORTED VOYAGE') : t('ESTIMATED FLIGHT PLAN') }}</span>
      <small id="cockpit-route-status">{{ r.status }}</small>
    </div>
    <div class="cockpit-route-endpoints">
      <div v-if="r.kind !== 'vessel'" class="cockpit-route-airport">
        <span>{{ t('FROM') }}</span>
        <strong id="cockpit-route-from">{{ r.from }}</strong>
      </div>
      <span v-if="r.kind !== 'vessel'" class="cockpit-route-arrow material-symbols-outlined" aria-hidden="true">east</span>
      <div class="cockpit-route-airport">
        <span>{{ t('TO') }}</span>
        <strong id="cockpit-route-to">{{ r.to }}</strong>
      </div>
    </div>
  </section>
</template>
