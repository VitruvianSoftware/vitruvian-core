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
import { t } from '../i18n/index.js';
import UiRail from './kit/UiRail.vue';
import {
  PANEL_RAIL_FALLBACK_ICON,
  PANEL_RAIL_ITEMS,
} from './panelRailCatalog.js';
import { usePanelStore } from './stores/panels.js';

const props = defineProps({
  /** `left` or `right`. */
  side: { type: String, required: true },
  /** Open or close a panel; receives the panel id. */
  onSelect: { type: Function, required: true },
});

const panels = usePanelStore();
const items = computed(() =>
  panels.sides[props.side]
    .filter((panel) => panel.available)
    .map((panel) => {
      const item = PANEL_RAIL_ITEMS[panel.id];
      return {
        id: panel.id,
        icon: item?.icon ?? PANEL_RAIL_FALLBACK_ICON,
        // Static markup is translated at boot, so a host's title already is.
        label: item ? t(item.label) : panel.title,
      };
    }),
);
const active = computed(() => panels.openPanelId(props.side));
const label = computed(() =>
  props.side === 'left' ? t('Left panels') : t('Right panels'),
);
</script>

<template>
  <UiRail
    :items="items"
    :active="active"
    :side="side"
    :label="label"
    :panel-open="active !== null"
    collapsible
    @select="onSelect"
  />
</template>
