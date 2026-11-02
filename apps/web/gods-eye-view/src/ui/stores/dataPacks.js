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
 * The loaded data packs' attribution cards as their view renders them. Each
 * set of data-pack presentations (src/scenes/dataPacks/presentation.js)
 * presents its own panel, with a card for each pack and its media player
 * when the pack is media.
 */
export const useDataPacksStore = defineStore('gev-data-packs', () => {
  /**
   * `[{owner, key, container, cards: [{key, id, title, url, media}]}]`, one
   * per owner showing cards. `container` is the element the panel sits in;
   * `media` is `{kind: 'video'|'audio', src}` or null.
   */
  const panels = shallowRef([]);

  /**
   * @param {object} owner The presentations publishing.
   * @param {?object} panel Their fresh panel, or null to remove it.
   */
  function publish(owner, panel) {
    const index = panels.value.findIndex((item) => item.owner === owner);
    const next = panels.value.slice();
    if (!panel) {
      if (index < 0) return;
      next.splice(index, 1);
    } else if (index < 0) next.push(markRaw({ ...panel, owner }));
    else next[index] = markRaw({ ...panel, owner });
    panels.value = next;
  }

  return { panels, publish };
});
