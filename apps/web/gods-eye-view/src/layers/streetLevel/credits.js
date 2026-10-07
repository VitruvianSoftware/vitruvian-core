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

import * as Cesium from 'cesium';

/**
 * One static Cesium credit per active provider: CC BY-SA imagery needs
 * visible attribution that goes away with the imagery.
 */
export function createCredits() {
  /** @type {Map<string, object>} provider id → Cesium.Credit */
  const shown = new Map();

  function show(viewer, def) {
    if (shown.has(def.id) || !viewer?.creditDisplay) return;
    try {
      const credit = new Cesium.Credit(def.credit.html, true);
      viewer.creditDisplay.addStaticCredit(credit);
      shown.set(def.id, credit);
    } catch {
      /* credit display unavailable */
    }
  }

  function hide(viewer, def) {
    const credit = shown.get(def.id);
    if (!credit) return;
    try {
      viewer?.creditDisplay?.removeStaticCredit?.(credit);
    } catch {
      /* credit display already torn down */
    }
    shown.delete(def.id);
  }

  function hideAll(viewer) {
    for (const id of [...shown.keys()]) hide(viewer, { id });
  }

  return { show, hide, hideAll };
}
