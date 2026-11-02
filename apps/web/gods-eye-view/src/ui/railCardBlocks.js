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

import { h, render } from 'vue';
import RailCardBlocks from './rail/RailCardBlocks.vue';

/**
 * Optional, ordered blocks without disclosure state. All controls are keyed.
 * Renders the RailCardBlocks component into `container`, which it owns, and
 * patches it synchronously on every update.
 */
export function createRailCardBlocks({ container, cardId, onParams }) {
  let destroyed = false;
  return {
    update(blocks = []) {
      if (destroyed) return;
      render(h(RailCardBlocks, { blocks, cardId, onParams }), container);
    },
    destroy() {
      if (destroyed) return;
      destroyed = true;
      render(null, container);
    },
  };
}
