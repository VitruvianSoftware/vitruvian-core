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
 * `v-text-data="text"`: the element's text, written into its one text node.
 * A `{{ }}` that is an element's only child is written with `textContent`,
 * which replaces the text node on every change; a readout that changes many
 * times a second keeps its node and changes only the node's data.
 */
function write(el, { value }) {
  const text = value == null ? '' : String(value);
  const node = el.firstChild;
  // An empty readout has no text node, as `textContent = ''` leaves it.
  if (text && node && node.nodeType === 3 && !node.nextSibling) {
    if (node.data !== text) node.data = text;
  } else if (el.textContent !== text) el.textContent = text;
}

export const vTextData = { mounted: write, updated: write };
