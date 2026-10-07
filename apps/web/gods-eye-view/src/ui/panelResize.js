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

// Pure resize geometry for floating panels; PanelPositionControls wires the DOM.

const EDGE_MARGIN_PX = 6;
export const RESIZE_DIRECTIONS = ['n', 's', 'e', 'w', 'ne', 'nw', 'sw', 'se'];

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

/**
 * Edges named in `dir` follow the pointer (dx, dy since gesture start) and the
 * opposite edge stays put. Minimum size and the viewport margin win.
 */
export function resizeBox(
  box,
  dir,
  dx,
  dy,
  {
    minWidth,
    minHeight,
    viewportWidth = Infinity,
    viewportHeight = Infinity,
    margin = EDGE_MARGIN_PX,
  } = {},
) {
  let { left, top, width, height } = box;
  const right = box.left + box.width;
  const bottom = box.top + box.height;
  if (dir.includes('e'))
    width = clamp(box.width + dx, minWidth, viewportWidth - margin - box.left);
  if (dir.includes('s'))
    height = clamp(
      box.height + dy,
      minHeight,
      viewportHeight - margin - box.top,
    );
  if (dir.includes('w')) {
    width = clamp(box.width - dx, minWidth, right - margin);
    left = right - width;
  }
  if (dir.includes('n')) {
    height = clamp(box.height - dy, minHeight, bottom - margin);
    top = bottom - height;
  }
  return { left, top, width, height };
}
