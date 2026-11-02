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
import { getCurrentInstance, watch } from 'vue';
import { useSceneStore } from '../stores/scenes.js';

// The Scene select's options; selecting one stays with SceneControls.
const { scenes, listedSceneId, listedRevision } = storeToRefs(useSceneStore());

// Every option render shows the published scene, as the select did before:
// `selected` alone is written only when it changes, so it would leave a
// person's later pick standing.
const instance = getCurrentInstance();
watch(
  listedRevision,
  () => {
    const select = instance.proxy.$el?.parentNode;
    if (select && listedSceneId.value) select.value = listedSceneId.value;
  },
  { flush: 'post' },
);
</script>

<template>
  <option
    v-for="scene in scenes"
    :key="scene.id"
    :value="scene.id"
    :selected="scene.id === listedSceneId"
    >{{ scene.title }}</option
  >
</template>
