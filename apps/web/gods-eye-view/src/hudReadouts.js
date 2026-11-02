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

/**
 * Readouts other owners show in the Intel HUD. The vessel layer presents the
 * selected vessel here and the HUD subscribes, so neither reaches into the
 * other's markup.
 */

/** @type {?{text: string}} The selected vessel's lines, or null for none. */
let selectedVessel = null;
const vesselListeners = new Set();

/**
 * Show the selected vessel's readout, or clear it.
 * @param {?{text: string}} readout Its lines joined by newlines, or null.
 */
export function presentSelectedVessel(readout) {
  selectedVessel = readout ? Object.freeze({ text: readout.text }) : null;
  for (const listener of vesselListeners) listener(selectedVessel);
}

/**
 * Follow the selected vessel's readout; the current one is replayed at once.
 * @param {(readout: ?{text: string}) => void} listener
 * @returns {() => void} Stop following.
 */
export function subscribeSelectedVessel(listener) {
  vesselListeners.add(listener);
  listener(selectedVessel);
  return () => vesselListeners.delete(listener);
}
