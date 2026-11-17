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

import { creditFromMarkup } from '../../render/creditMarkup.js';
import { findCredits } from '../../render/rendererOf.js';

/**
 * One on-map credit per active provider, through the renderer's credits
 * port: CC BY-SA imagery needs visible attribution that goes away with the
 * imagery. A provider's credit is markup with one link, read as the
 * port's plain data.
 */
export function createCredits() {
  /** @type {Map<string, () => void>} provider id → the credit's Off */
  const shown = new Map();

  function show(viewer, def) {
    if (shown.has(def.id)) return;
    const credits = findCredits(viewer);
    if (!credits) return;
    shown.set(
      def.id,
      credits.addStatic({ ...creditFromMarkup(def.credit.html), inline: true }),
    );
  }

  function hide(_viewer, def) {
    const off = shown.get(def.id);
    if (!off) return;
    shown.delete(def.id);
    off();
  }

  function hideAll(viewer) {
    for (const id of [...shown.keys()]) hide(viewer, { id });
  }

  return { show, hide, hideAll };
}
