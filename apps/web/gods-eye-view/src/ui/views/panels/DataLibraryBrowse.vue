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
import { t } from '../../../i18n/index.js';
import UiButton from '../../kit/UiButton.vue';
import { useDataLibraryStore } from '../../stores/dataLibrary.js';
import DataLibraryDialog from './DataLibraryDialog.vue';

// DATA LAYERS ▸ Browse data library: the button at the foot of the panel and
// the dialog it opens, drawn once the library browser (src/ui/libraryBrowser.js)
// publishes. Kept apart from LayerPanelsView so the browser's publishes (the
// stat tiles refresh every second while open) re-render only this.
const { view, controls } = storeToRefs(useDataLibraryStore());
</script>

<template>
  <div class="data-library-footer">
    <UiButton
      id="data-library-browse"
      class="data-library-browse"
      aria-haspopup="dialog"
      aria-controls="data-library"
      :hidden="!view"
      :native-title="false"
      @click="controls?.open()"
      >{{ t('BROWSE DATA LIBRARY') }}</UiButton
    >
  </div>
  <Teleport v-if="view" to="body"><DataLibraryDialog :view="view" /></Teleport>
</template>
