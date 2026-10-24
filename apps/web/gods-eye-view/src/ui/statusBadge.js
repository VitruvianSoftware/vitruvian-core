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
 * Ordinary read-only badge view. Labels are already translated. Feature owners
 * retain status derivation, machine-state attributes and announcement policy.
 * No listeners, timers, state inference or automatic live regions are installed.
 * Vue can replace this DOM adapter while retaining the label/hidden contract
 * and the gev-status-badge CSS surface.
 * @param {object} options
 * @param {Document} [options.documentRef]
 * @param {string} [options.label]
 * @param {'pill'|'box'|'plain'} [options.appearance]
 * @param {string} [options.className] Feature/layout hooks.
 * @param {boolean} [options.hidden]
 * @returns {HTMLSpanElement}
 */
export function createStatusBadge({
  documentRef = globalThis.document,
  label = '',
  appearance = 'pill',
  className = '',
  hidden = false,
} = {}) {
  const badge = documentRef.createElement('span');
  badge.className = [
    'gev-status-badge',
    appearance === 'box' && 'gev-status-badge--box',
    appearance === 'plain' && 'gev-status-badge--plain',
    className,
  ]
    .filter(Boolean)
    .join(' ');
  updateStatusBadge(badge, { label, hidden });
  return badge;
}

/** Paint controlled text/visibility without replacing nodes or redundant writes. */
export function updateStatusBadge(badge, { label, hidden = false }) {
  if (badge.textContent !== label) badge.textContent = label;
  if (badge.hidden !== hidden) badge.hidden = hidden;
}
