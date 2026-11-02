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
 * The scene's status chips as their views render them. ShellFeedback
 * (src/ui/shellFeedback.js) publishes the top-center loading status and the
 * road network chip, CctvControls the camera grid chip; the toast shows
 * what any owner's createToast() (src/ui/toast.js) publishes, and the title
 * bar the FPS readout createFrameRateMonitor() publishes. Each label keeps its
 * last text while hidden, so the next change flaps from what was shown.
 */
export const useStatusStore = defineStore('gev-status', () => {
  /**
   * `{hidden, state, label, detail, stopped}`; null until first published.
   * `stopped` rests a label for good once its owner is destroyed.
   */
  const loading = shallowRef(null);
  /** `{visible, label, immediate, progress, stopped}`, or null. */
  const traffic = shallowRef(null);
  /** `{visible, label, immediate, progress, stopped}`, or null. */
  const cctv = shallowRef(null);

  /**
   * The page toast, `{text, visible, shown}`; null until the first one.
   * `shown` changes with every show, which rewrites the text.
   */
  const toast = shallowRef(null);

  /**
   * The title bar's FPS readout, `{visible, text}`; null while no monitor
   * counts frames.
   */
  const fps = shallowRef(null);

  /** @param {?object} next A fresh presentation of the loading status. */
  function publishLoading(next) {
    loading.value = next && markRaw(next);
  }

  /** @param {?object} next A fresh presentation of the road network chip. */
  function publishTraffic(next) {
    traffic.value = next && markRaw(next);
  }

  /** @param {?object} next A fresh presentation of the camera grid chip. */
  function publishCctv(next) {
    cctv.value = next && markRaw(next);
  }

  /** @param {?{text: string, visible: boolean, shown: number}} next */
  function publishToast(next) {
    toast.value = next && markRaw(next);
  }

  /** @param {?{visible: boolean, text: string}} next */
  function publishFps(next) {
    fps.value = next && markRaw(next);
  }

  return {
    fps,
    publishFps,
    toast,
    publishToast,
    loading,
    publishLoading,
    traffic,
    publishTraffic,
    cctv,
    publishCctv,
  };
});
