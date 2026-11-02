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
 * The voice pointer reticles as their view renders them. Each PointerReticle
 * (src/voice/pointerReticle.js) presents where the user pointed while its
 * voice turn is live.
 */
export const usePointerReticleStore = defineStore('gev-pointer-reticle', () => {
  /**
   * `[{owner, visible, left, top, target}]` in client pixels, one per
   * reticle that has shown, `target` being 'entity' or 'ground'.
   */
  const reticles = shallowRef([]);

  /**
   * @param {object} owner The reticle publishing.
   * @param {?object} view Its fresh presentation, or null to remove it.
   */
  function publish(owner, view) {
    const index = reticles.value.findIndex((item) => item.owner === owner);
    const next = reticles.value.slice();
    if (!view) {
      if (index < 0) return;
      next.splice(index, 1);
    } else if (index < 0) next.push(markRaw({ ...view, owner }));
    else next[index] = markRaw({ ...view, owner });
    reticles.value = next;
  }

  return { reticles, publish };
});
