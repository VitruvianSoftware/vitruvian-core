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
 * Create an ordinary native action button. Static templates use the same CSS
 * classes. Labels are already translated; feature owners retain callbacks,
 * disabled-state updates and listener cleanup. Construction binds no listeners.
 * @param {object} options
 * @param {Document} [options.documentRef] Document that owns the button.
 * @param {string} options.label Visible text, never interpreted as markup.
 * @param {string} [options.className] Additional feature/layout hooks.
 * @param {'default'|'danger'} [options.variant]
 * @param {'default'|'compact'} [options.size]
 * @param {boolean} [options.disabled]
 * @param {string} [options.ariaLabel] Accessible name when visible text needs context.
 * @param {string} [options.title]
 * @returns {HTMLButtonElement}
 */
export function createActionButton({
  documentRef = globalThis.document,
  label,
  className = '',
  variant = 'default',
  size = 'default',
  disabled = false,
  ariaLabel,
  title,
}) {
  const button = documentRef.createElement('button');
  button.type = 'button';
  button.className = [
    'gev-action-button',
    variant === 'danger' && 'gev-action-button--danger',
    size === 'compact' && 'gev-action-button--compact',
    className,
  ]
    .filter(Boolean)
    .join(' ');
  button.textContent = label;
  button.disabled = disabled;
  if (ariaLabel !== undefined) button.setAttribute('aria-label', ariaLabel);
  if (title !== undefined) button.title = title;
  return button;
}
