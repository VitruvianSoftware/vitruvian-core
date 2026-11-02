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
import { computed, ref } from 'vue';
import { t } from '../../../i18n/index.js';
import { vFocusSafeChildren } from '../../rail/focusSafeChildren.js';
import { useDisplayStore } from '../../stores/display.js';

// DISPLAY ▸ Import: the button, the hidden picker, the imported files and
// the hint. The file import publishes the rows and hint; until it does, the
// list is empty. A pick and the row buttons call its actions. Before the
// row holding keyboard focus goes, focus moves to the next row's same
// button, else the previous row's, else the Import button. The list's
// template is one line: templates keep whitespace.
const display = useDisplayStore();
const { geoImport } = storeToRefs(display);
const rows = computed(() => geoImport.value?.rows ?? []);
// No `>` in the template: the catalog reads its tags with a regex.
const listed = computed(() => rows.value.length > 0);
const importButton = ref(null);
const picker = ref(null);
const ROW_ACTIONS = {
  toggle: 'toggleGeoImport',
  fly: 'flyToGeoImport',
  remove: 'removeGeoImport',
};

// The picker opens once the file import has presented itself, so a pick
// always has somewhere to go.
function openPicker() {
  if (geoImport.value) picker.value.click();
}

function pick() {
  const files = [...(picker.value.files || [])];
  // Clear the selection so choosing the same file again fires `change`.
  picker.value.value = '';
  if (files.length) display.act('importGeoFiles', files);
}

function leave() {
  const active = document.activeElement;
  const row = active?.closest('[data-import-id]');
  const action = active?.dataset.action;
  const others = [];
  for (let next = row?.nextElementSibling; next; next = next.nextElementSibling)
    others.push(next);
  for (let prev = row?.previousElementSibling; prev; prev = prev.previousElementSibling)
    others.push(prev);
  for (const other of others) {
    const target =
      other.querySelector(`button[data-action="${action}"]`) ||
      other.querySelector('button');
    if (target) return target.focus();
  }
  importButton.value?.focus();
}
</script>

<template>
  <div class="pp-toggle-group" id="geo-import-group">
    <button ref="importButton" class="pp-toggle-btn" id="geo-import-button" type="button" @click="openPicker" :title="t('Show your own GeoJSON, KML, KMZ or GPX files on the globe (or drop them onto it). File bytes stay on this device; overlays can appear in map screenshots shared with voice.')">
      <span class="pp-icon material-symbols-outlined" aria-hidden="true">upload_file</span>
      <span class="pp-label">{{ t('Import') }}</span>
    </button>
    <input ref="picker" type="file" id="geo-import-input" accept=".geojson,.json,.kml,.kmz,.gpx" multiple hidden @change="pick" :aria-label="t('Choose GeoJSON, KML, KMZ or GPX files')">
    <ul class="geo-import-list" :class="{ visible: listed }" id="geo-import-list" v-focus-safe-children="leave" :aria-label="t('Imported files')"><li v-for="row in rows" :key="row.id" class="geo-import-row" :data-import-id="row.id"><span :class="['geo-import-swatch', { 'own-styles': row.ownStyles }]" :style="row.ownStyles ? null : { background: row.color }"></span><span class="geo-import-name" :title="row.title">{{ row.name }}</span><button v-for="item in row.actions" :key="item.action" type="button" class="geo-import-action" :data-action="item.action" :title="item.label" :aria-label="item.label" :aria-pressed="item.pressed" @click="display.act(ROW_ACTIONS[item.action], row.id)"><span class="material-symbols-outlined" aria-hidden="true">{{ item.icon }}</span></button></li></ul>
    <span class="draw-hint geo-import-hint" id="geo-import-hint" aria-live="polite">{{ geoImport?.hint ?? '' }}</span>
  </div>
</template>
