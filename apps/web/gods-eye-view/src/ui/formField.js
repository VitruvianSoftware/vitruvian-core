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
 * Build a native numeric field without listeners, parsing or commit policy.
 * Owners retain drafts, validation, input/change timing and disposal. Static
 * selects and number inputs share the gev-field surface in their templates;
 * options remain owned by each feature (no replacement popup or keyboard code).
 * @param {object} options
 * @param {Document} [options.documentRef]
 * @param {string} [options.className] Additional density/layout hooks.
 * @param {number|string} [options.min]
 * @param {number|string} [options.max]
 * @param {number|string} [options.step]
 * @param {number|string} [options.value]
 * @param {boolean} [options.disabled]
 * @param {string} [options.ariaLabel] Already translated accessible name.
 * @returns {HTMLInputElement}
 */
export function createNumberInput({
  documentRef = globalThis.document,
  className = '',
  min,
  max,
  step,
  value,
  disabled = false,
  ariaLabel,
} = {}) {
  const input = documentRef.createElement('input');
  input.type = 'number';
  input.className = `gev-field${className ? ` ${className}` : ''}`;
  for (const [key, setting] of Object.entries({ min, max, step, value })) {
    if (setting !== undefined) input[key] = setting;
  }
  input.disabled = disabled;
  if (ariaLabel !== undefined) input.setAttribute('aria-label', ariaLabel);
  return input;
}
