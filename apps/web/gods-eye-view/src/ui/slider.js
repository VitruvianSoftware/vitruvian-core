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
 * Build the shared native slider. Feature owners retain their input/change
 * listeners, formatting and teardown; this component installs no handlers.
 * Static sliders use the same gev-quantitative-slider class in their template.
 * @param {object} options
 * @param {Document} [options.documentRef] Document that owns the input.
 * @param {string} [options.className] Additional feature/layout hooks.
 * @param {number|string} [options.min]
 * @param {number|string} [options.max]
 * @param {number|string} [options.step]
 * @param {number|string} [options.value]
 * @param {string} [options.ariaLabel] Already translated accessible name.
 * @returns {HTMLInputElement}
 */
export function createSlider({
  documentRef = globalThis.document,
  className = '',
  min,
  max,
  step,
  value,
  ariaLabel,
} = {}) {
  const input = documentRef.createElement('input');
  input.type = 'range';
  input.className = `gev-quantitative-slider${className ? ` ${className}` : ''}`;
  for (const [key, setting] of Object.entries({ min, max, step, value })) {
    if (setting !== undefined) input[key] = setting;
  }
  if (ariaLabel !== undefined) input.setAttribute('aria-label', ariaLabel);
  return input;
}
