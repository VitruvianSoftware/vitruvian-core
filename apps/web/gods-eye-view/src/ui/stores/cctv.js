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
 * The CCTV panel as its view renders it. CctvControls presents the buttons,
 * CAL chip, meta line and calibration readout (`presentCctvPanel()`), runs
 * the frame preview, source badge and typed summary, and publishes them
 * here, with the camera picker's options; it keeps its listeners on the
 * panel's controls.
 */
export const useCctvStore = defineStore('gev-cctv', () => {
  /** The presented panel; null until the controls first render. */
  const view = shallowRef(null);

  /**
   * The pose value being typed: `{field, label, ariaLabel, step, value,
   * finish(commit, typedText)}`, or null.
   */
  const calEdit = shallowRef(null);

  /** The preview: requested and shown frame, loading and error state. */
  const frame = shallowRef(null);
  /** Whether the live video surface replaces the still frame. */
  const live = shallowRef(false);
  /** `{label, state}` for the source badge; null until first synced. */
  const sourceBadge = shallowRef(null);
  /**
   * The camera picker: `{options: [{value, label}], note, disabled,
   * selection: {value}|{index}|null}`; null until first rendered.
   */
  const picker = shallowRef(null);
  /** The scene summary as typed so far; null until the first one. */
  const summary = shallowRef(null);

  /** @param {object} next A fresh presentation; every publish re-renders. */
  function publish(next) {
    view.value = markRaw(next);
  }

  let editCount = 0;

  /** @param {object|null} edit Each edit gets its own `id`, and input. */
  function setCalEdit(edit) {
    calEdit.value = edit ? markRaw({ ...edit, id: ++editCount }) : null;
  }

  /** @param {object} next */
  function setFrame(next) {
    frame.value = markRaw(next);
  }

  /** @param {boolean} on */
  function setLive(on) {
    live.value = Boolean(on);
  }

  /** @param {{label: string, state: string}} next */
  function setSourceBadge(next) {
    sourceBadge.value = markRaw(next);
  }

  /** @param {object} next */
  function setPicker(next) {
    picker.value = markRaw(next);
  }

  /** @param {string} text */
  function setSummary(text) {
    summary.value = text;
  }

  return {
    view,
    calEdit,
    frame,
    live,
    sourceBadge,
    summary,
    picker,
    publish,
    setCalEdit,
    setFrame,
    setLive,
    setSourceBadge,
    setSummary,
    setPicker,
  };
});
