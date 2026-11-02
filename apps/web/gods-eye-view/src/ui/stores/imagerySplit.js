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
 * The before/after imagery dividers on the page, as their view renders them.
 * Each split (src/ui/imagerySplit.js) publishes its line under its own key
 * and withdraws it when destroyed; the view sends pointer and keyboard input
 * back to that split's controls.
 */
export const useImagerySplitStore = defineStore('gev-imagery-split', () => {
  /** The dividers in creation order: `{key, view, controls}`. */
  const splits = shallowRef([]);

  /**
   * Show or update one divider.
   * @param {number} key The split's own key.
   * @param {object} view A fresh presentation of its line.
   * @param {object} controls What the view calls for its input.
   */
  function publish(key, view, controls) {
    const entry = markRaw({ key, view, controls });
    const index = splits.value.findIndex((split) => split.key === key);
    splits.value =
      index < 0
        ? [...splits.value, entry]
        : splits.value.map((split, at) => (at === index ? entry : split));
  }

  /** @param {number} key The split to remove. */
  function withdraw(key) {
    splits.value = splits.value.filter((split) => split.key !== key);
  }

  return { splits, publish, withdraw };
});
