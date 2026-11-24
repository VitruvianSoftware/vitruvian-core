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
import { t } from '../../../i18n/index.js';
import { useStoriesStore } from '../../stores/stories.js';
import UiButton from '../../kit/UiButton.vue';

/**
 * The right rail over the story map (prototype `.ov-rail`): Open in GEV (it
 * opens the scene in GEV's Scenes panel) and Share.
 */
const store = useStoriesStore();
// A scene saved on this device only: a link to it opens nothing elsewhere.
const localOnly = computed(() => !!store.byId(store.storyId)?.mine);

async function share() {
  const url = store.controller.shareLink();
  try {
    await navigator.clipboard.writeText(url);
    store.flashHint(t('Story link copied'), 1800);
  } catch {
    store.flashHint(url, 2600);
  }
}
</script>

<template>
  <div id="ovRail" class="ov ov-rail">
    <!-- The scene opens in GEV's Scenes panel. -->
    <UiButton
      id="railGev"
      class="rail-btn rail-gev"
      :aria-label="t('Open this moment in GEV')"
      @click="store.controller.openInGev()"
    >
      <span class="ic"
        ><svg class="eye" viewBox="0 0 775 520" aria-hidden="true">
          <use href="#gevLogo" /></svg></span
      >{{ t('Open') }}
    </UiButton>
    <UiButton
      v-if="!localOnly"
      id="railShare"
      class="rail-btn"
      :aria-label="t('Share this story')"
      @click="share"
    >
      <span class="ic"
        ><span class="share-icon" aria-hidden="true">&#x1F517;</span></span
      >{{ t('Share') }}
    </UiButton>
  </div>
</template>
