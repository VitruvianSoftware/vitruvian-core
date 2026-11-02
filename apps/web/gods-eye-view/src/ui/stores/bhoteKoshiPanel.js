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
 * The Bhote Koshi event's reconstruction panel as its view renders it. The
 * event layer (src/data/bhoteKoshiEvent.js) presents each control's state
 * and the field reports; the view sends clicks and slider moves back to the
 * connected controls.
 */
export const useBhoteKoshiPanelStore = defineStore(
  'gev-bhote-koshi-panel',
  () => {
    /**
     * `{owner, sceneBeat, refs, beforeDate, afterDate, reports}`, or null while
     * the event layer is off. Each entry of `refs` holds one control's
     * `textContent`, `hidden`, `disabled`, `value` and `attributes`.
     */
    const panel = shallowRef(null);

    /** @param {?object} next A fresh presentation; every publish re-renders. */
    function publish(next) {
      panel.value = next && markRaw(next);
    }

    /** The controls the panel's buttons, sliders and reports call. */
    const controls = shallowRef(null);

    /** @param {?object} next The controls, or null to disconnect. */
    function connect(next) {
      controls.value = next && markRaw(next);
    }

    return { panel, publish, controls, connect };
  },
);
