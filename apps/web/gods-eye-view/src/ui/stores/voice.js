/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import { defineStore } from 'pinia';
import { markRaw, shallowRef } from 'vue';

/**
 * The voice control as the command dock renders it. The voice control
 * presenter (src/voice/control.js) holds the control's state for the session
 * owners and publishes it here; the view sends clicks, keys and form changes
 * back to the connected presenter.
 */
export const useVoiceStore = defineStore('gev-voice', () => {
  /** The presented control; null while no voice session owns one. */
  const view = shallowRef(null);

  /** @param {?object} next A fresh presentation; every publish re-renders. */
  function publish(next) {
    view.value = next && markRaw(next);
  }

  /** The presenter the view calls, or null while none is wired. */
  const controls = shallowRef(null);

  /** @param {?object} next The presenter, or null to disconnect. */
  function connect(next) {
    controls.value = next && markRaw(next);
  }

  /**
   * The waveform's bars, apart from the view: they change every animation
   * frame while voice is live, and only the visualizer renders them.
   */
  const bars = shallowRef(null);

  /** @param {?Array<{level: string, opacity: string}>} next */
  function publishBars(next) {
    bars.value = next && markRaw(next);
  }

  /**
   * The chat conversation, apart from the view: a typed reply reveals frame
   * by frame, and only the message list renders it.
   */
  const chat = shallowRef([]);

  /** @param {Array<{id: number, role: string, text: string}>} next */
  function publishChat(next) {
    chat.value = markRaw(next ?? []);
  }

  return {
    view,
    publish,
    controls,
    connect,
    bars,
    publishBars,
    chat,
    publishChat,
  };
});
