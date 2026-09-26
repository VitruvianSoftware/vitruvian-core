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

const set = (node, key, value) => {
  if (node[key] !== value) node[key] = value;
};
const attribute = (node, key, value) => {
  if (node.getAttribute(key) !== value) node.setAttribute(key, value);
};

/** Keyed chips shared by layer rows and rail cards; the caller owns dispatch. */
export function syncChipGroup(container, chips = [], { before = null } = {}) {
  if (!container) return;
  const document = container.ownerDocument ?? globalThis.document;
  const stale = new Map();
  for (const node of [...container.children])
    if (node.dataset?.chipId) stale.set(node.dataset.chipId, node);
  const ordered = [];
  for (const chip of chips) {
    let button = stale.get(chip.id);
    stale.delete(chip.id);
    if (!button) {
      button = document.createElement('button');
      button.type = 'button';
      button.dataset.chipId = chip.id;
    }
    const state = chip.state || (chip.active ? 'active' : 'idle');
    set(
      button,
      'className',
      `data-toggle-chip chip-${state}${chip.active ? ' active' : ''}`,
    );
    set(button, 'textContent', chip.label);
    set(button, 'title', chip.title || '');
    set(button, 'disabled', Boolean(chip.disabled));
    attribute(button, 'aria-pressed', String(Boolean(chip.active)));
    attribute(button, 'aria-busy', String(Boolean(chip.busy)));
    ordered.push(button);
  }
  for (const node of stale.values()) node.remove();
  ordered.forEach((node, index) => {
    if (container.children[index] !== node)
      container.insertBefore(node, container.children[index] || before);
  });
}
