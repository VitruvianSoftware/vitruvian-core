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
import { VOICE_VISUALIZER_BARS } from '../../../voice/control.js';
import { useVoiceStore } from '../../stores/voice.js';

// The dock waveform. Its bars change every animation frame while voice is
// live, so they render here alone, not with the rest of the control.
const { bars } = storeToRefs(useVoiceStore());
const barStyle = (index) => ({
  '--bar': index,
  ...(bars.value?.[index] && {
    '--audio-level': bars.value[index].level,
    '--audio-opacity': bars.value[index].opacity,
  }),
});
</script>

<template>
  <div class="gev-voice-visualizer" aria-hidden="true">
        <span v-for="index in VOICE_VISUALIZER_BARS" :key="index" :style="barStyle(index - 1)"></span>
      </div>
</template>
