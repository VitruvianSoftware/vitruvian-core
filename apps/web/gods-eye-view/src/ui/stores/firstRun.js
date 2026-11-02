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
 * The first-run mission launcher as the welcome view renders it.
 * initFirstRunExperience presents it and connects the controls its buttons
 * and checkbox call.
 */
export const useFirstRunStore = defineStore('gev-first-run', () => {
  /**
   * `{removed, shown, visible, closing, state, busy, status, description,
   * environmentalTitle, environmentalSub, scrollable}`, or null until the
   * launcher is initialized (the card stays hidden).
   */
  const launcher = shallowRef(null);

  /** @param {?object} next A fresh presentation; every publish re-renders. */
  function publish(next) {
    launcher.value = next && markRaw(next);
  }

  /** `{choose(choice), dismiss(), suppress(wanted) → boolean}`, or null. */
  const controls = shallowRef(null);

  /** @param {?object} next The launcher's controls, or null to disconnect. */
  function connect(next) {
    controls.value = next && markRaw(next);
  }

  return { launcher, publish, controls, connect };
});
