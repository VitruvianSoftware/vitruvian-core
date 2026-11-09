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
import { t } from '../../../i18n/index.js';

// Dock and minimize for an assistant panel (chat or voice). The owner
// (src/voice/panelLayout.js) places the panel; this reports the choice.
const props = defineProps({
  docked: { type: Boolean, default: false },
  minimized: { type: Boolean, default: false },
});
defineEmits(['dock', 'minimize']);
</script>

<template>
  <div class="gev-panel-layout" role="group" :aria-label="t('Panel position')">
    <button type="button" data-layout-dock :aria-pressed="String(props.docked)" :aria-label="props.docked ? t('Move above the dock') : t('Dock to the right')" :title="props.docked ? t('Move above the dock') : t('Dock to the right')" @click="$emit('dock')"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path :d="props.docked ? 'M4 5h16v14H4ZM4 14h16' : 'M4 5h16v14H4ZM14 5v14'"></path></svg></button>
    <button type="button" data-layout-minimize :aria-label="props.minimized ? t('Expand panel') : t('Minimize panel')" :title="props.minimized ? t('Expand panel') : t('Minimize panel')" @click="$emit('minimize')"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path :d="props.minimized ? 'M6 6h12v12H6Z' : 'M6 12h12'"></path></svg></button>
  </div>
</template>
