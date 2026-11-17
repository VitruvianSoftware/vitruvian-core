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
 * @module render/input/wheel
 * @description A DOM wheel event as the input port's `wheel` delta: lines
 * scrolled, counted as the reference renderer counts them, so a camera
 * controller that turns lines back into pixels at `WHEEL_PX_PER_LINE`
 * zooms exactly as the reference does in every browser.
 *
 * The reference takes a pixel-mode wheel as its pixels, a line-mode one at
 * 40 px a line and a page-mode one at 120 px a page. Lines are those
 * pixels over 40: a line-mode wheel is its own lines, a page is 3 lines,
 * and a pixel-mode wheel (Chrome's notch is 100 px) is its pixels over 40
 * (2.5 lines a notch).
 */

/** Pixels a wheel line stands for: the reference renderer's own count. */
export const WHEEL_PX_PER_LINE = 40;
/** Lines a wheel page stands for: the reference's 120 px a page. */
export const WHEEL_LINES_PER_PAGE = 3;

/**
 * Lines scrolled by a DOM wheel event, down positive (as `deltaY`).
 * @param {{deltaY: number, deltaMode?: number}} event
 * @returns {number}
 */
export function wheelLines({ deltaY, deltaMode = 0 }) {
  if (deltaMode === 1) return deltaY;
  if (deltaMode === 2) return deltaY * WHEEL_LINES_PER_PAGE;
  return deltaY / WHEEL_PX_PER_LINE;
}
