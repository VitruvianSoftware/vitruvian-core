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
 * The Street Level photo viewer (KartaView, Panoramax) as its view renders
 * it. The street-level layer presents it through `subscribePhotoViewer()`
 * and the application shell publishes each presentation here.
 */
export const useStreetLevelPhotoStore = defineStore(
  'gev-street-level-photo',
  () => {
    /**
     * `{host, mountKey, providerId, label, alt, kind, src, fit, canvasKey,
     * dragging, prevLabel, prevDisabled, nextLabel, nextDisabled, actions}`,
     * or null while no photo viewer is mounted. Of the viewers mounting in
     * the host, only the one mounted last (the largest `mountKey`) is
     * published; `actions.supersede()` tells the others they are not drawn
     * (see `ViewerAdapter.subscribeView` in src/layers/streetLevel/registry.js).
     */
    const photo = shallowRef(null);

    /** @param {?object} next A fresh presentation; every publish re-renders. */
    function publish(next) {
      photo.value = next && markRaw(next);
    }

    return { photo, publish };
  },
);
