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
 * @module ui/creditLineHeight
 * @description Keeps `--credit-line-height` on the page's root at the
 * height of the attribution line at the bottom of the screen, so what sits
 * above it (the HUD's bottom corners) clears it when it wraps onto more
 * lines. The line is the application's own (`#gev-credits`) or the one a
 * renderer draws inside `#cesium-credits`.
 */

const LINES = ['#gev-credits', '#cesium-credits .cesium-widget-credits'];

/**
 * Follow the attribution line's height in `--credit-line-height`.
 * @param {Document} [doc]
 * @returns {() => void} Stops following it and clears the property.
 */
export function trackCreditLineHeight(doc = globalThis.document) {
  const Observer = doc?.defaultView?.ResizeObserver;
  if (!doc?.documentElement || typeof Observer !== 'function') return () => {};
  const root = doc.documentElement;
  const lines = LINES.map((selector) => doc.querySelector(selector)).filter(
    Boolean,
  );
  if (!lines.length) return () => {};
  const update = () => {
    const height = Math.max(
      0,
      ...lines.map((line) => line.getBoundingClientRect().height),
    );
    if (height > 0)
      root.style.setProperty('--credit-line-height', `${Math.ceil(height)}px`);
    else root.style.removeProperty('--credit-line-height');
  };
  const observer = new Observer(update);
  for (const line of lines) observer.observe(line);
  update();
  return () => {
    observer.disconnect();
    root.style.removeProperty('--credit-line-height');
  };
}
