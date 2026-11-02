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
import { shallowRef } from 'vue';

/**
 * The Global Context compass and contact direction overlay as its view
 * renders it. The awareness layer presents it through
 * `subscribeDirectionOverlay()` and the application shell publishes it here.
 */
export const useAwarenessDirectionStore = defineStore(
  'gev-awareness-direction',
  () => {
    /**
     * `{container, hidden, ring, heading, labels, markers}`, or null while
     * the layer has no overlay. `container` is the element it sits in.
     */
    const overlay = shallowRef(null);

    /**
     * @param {?object} next A fresh presentation, frozen by the layer; every
     *   publish re-renders.
     */
    function publish(next) {
      overlay.value = next;
    }

    return { overlay, publish };
  },
);
