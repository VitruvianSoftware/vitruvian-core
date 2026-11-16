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

import { ref } from 'vue';

// Panels can slide over their rail to the screen edge, one setting per side:
// the left column moves onto the left rail, the right column onto the right
// rail. Each panel header has the switch (UiPanelEdge); the choice is kept
// for the next visit and shows as a body class the stylesheet reads.
const KEY = 'gev.panelEdge';
function read() {
  try {
    const saved = JSON.parse(globalThis.localStorage?.getItem(KEY) || '{}');
    return { left: saved.left === true, right: saved.right === true };
  } catch {
    return { left: false, right: false };
  }
}

export const panelEdge = ref(read());

function apply() {
  const body = globalThis.document?.body;
  if (!body) return;
  body.classList.toggle('panels-edge-left', panelEdge.value.left);
  body.classList.toggle('panels-edge-right', panelEdge.value.right);
}
apply();

/** Which side a panel element sits on, from the column it is in. */
export function panelSide(element) {
  return element?.closest?.('#right-context-rail, #cockpit-utility-controls')
    ? 'right'
    : 'left';
}

export function togglePanelEdge(side) {
  panelEdge.value = { ...panelEdge.value, [side]: !panelEdge.value[side] };
  try {
    globalThis.localStorage?.setItem(KEY, JSON.stringify(panelEdge.value));
  } catch {
    // Without storage the choice lasts for this visit.
  }
  apply();
}
