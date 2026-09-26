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
/** Reconcile ordered layer/card lists without replacing focused items. */
export function syncRowList(container, list) {
  const document = container?.ownerDocument ?? globalThis.document;
  if (!container) return;
  const items = list?.items || [];
  set(container, 'hidden', items.length === 0);
  attribute(container, 'aria-label', list?.ariaLabel || '');

  const stale = new Map();
  for (const node of [...container.children]) {
    if (node.dataset?.listItemId) stale.set(node.dataset.listItemId, node);
  }
  let index = 0;
  let activeButton = null;
  for (const item of items) {
    let entry = stale.get(item.id);
    stale.delete(item.id);
    let button;
    if (!entry) {
      entry = document.createElement('li');
      entry.dataset.listItemId = item.id;
      button = document.createElement('button');
      button.type = 'button';
      button.className = 'data-row-list-item';
      button.dataset.listItemId = item.id;
      const lead = document.createElement('span');
      lead.className = 'data-row-list-lead';
      const text = document.createElement('span');
      text.className = 'data-row-list-text';
      button.append(lead, text);
      entry.appendChild(button);
    } else {
      button = entry.querySelector('.data-row-list-item');
    }
    // Keep DOM order in step with descriptor order without rebuilding.
    const anchor = container.children[index++] || null;
    if (entry !== anchor) container.insertBefore(entry, anchor);
    if (!button) continue;
    const lead = button.querySelector('.data-row-list-lead');
    const text = button.querySelector('.data-row-list-text');
    const leadText = String(item.lead ?? '');
    const bodyText = String(item.text ?? '');
    if (lead && lead.textContent !== leadText) lead.textContent = leadText;
    if (text && text.textContent !== bodyText) text.textContent = bodyText;
    set(button, 'disabled', Boolean(item.disabled));
    set(
      button,
      'className',
      `data-row-list-item${item.disabled ? ' note' : ''}${item.active ? ' active' : ''}${item.current ? ' current' : ''}`,
    );
    attribute(button, 'aria-current', item.current ? 'step' : 'false');
    attribute(button, 'aria-pressed', item.active ? 'true' : 'false');
    set(button, 'title', bodyText);
    if (item.current) activeButton = button;
  }
  for (const node of stale.values()) node.remove();
  // Follow the flight, but never steal a scroll the reader is making
  // themselves: only when the step actually changed.
  if (
    activeButton &&
    container.dataset.currentId !== activeButton.dataset.listItemId
  ) {
    container.dataset.currentId = activeButton.dataset.listItemId;
    activeButton.scrollIntoView?.({ block: 'nearest' });
  } else if (!activeButton) {
    delete container.dataset.currentId;
  }
}
