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

// src/testSupport/panelState.mjs — present a panel's state the way the shell
// does (PanelChrome._presentPanel), drawn at once as its root's v-panel-state
// would, for fixtures whose panels are plain objects with a classList.
import { applyPanelState, readPanelState } from '../ui/rail/panelState.js';

/**
 * @param {object|string} panelOrId A panel, or its id in `documentRef`.
 * @param {object} [patch] The state that changes.
 * @param {Document} [documentRef]
 */
export function presentPanelLocally(
  panelOrId,
  patch = {},
  documentRef = globalThis.document,
) {
  const panel =
    typeof panelOrId === 'string'
      ? documentRef?.getElementById(panelOrId)
      : panelOrId;
  if (panel) applyPanelState(panel, { ...readPanelState(panel), ...patch });
}
