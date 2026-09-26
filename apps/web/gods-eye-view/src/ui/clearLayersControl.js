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

/** Keep the clear action focusable while busy; the caller owns its transaction. */
export function bindClearLayersControl(button, clear) {
  let destroyed = false;
  const click = () => {
    if (!destroyed) void clear();
  };
  button?.addEventListener('click', click);
  return {
    setBusy(busy) {
      if (destroyed || !button) return;
      button.setAttribute('aria-disabled', String(busy));
      button.setAttribute('aria-busy', String(busy));
      button.setAttribute(
        'aria-label',
        busy ? 'Clearing selected data layers' : 'Clear selected data layers',
      );
    },
    destroy() {
      destroyed = true;
      button?.removeEventListener('click', click);
    },
  };
}
