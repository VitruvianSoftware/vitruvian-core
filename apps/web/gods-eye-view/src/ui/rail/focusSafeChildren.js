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
 * `v-focus-safe-children`: lets a keyed list reorder without dropping keyboard
 * focus. A browser blurs any element it moves, so Vue moving the row that
 * holds focus would drop it. This directive turns such a move into moves of
 * the rows around the focused one, which reach the same order while the
 * focused row stays put. Before the focused row itself is removed, it calls
 * the directive's value so focus can go somewhere that stays.
 */
const focusedChild = (el, node) =>
  node.parentNode === el && node.contains(el.ownerDocument.activeElement);

/**
 * Place `node` before `anchor` (null: at the end) without moving `node`. Only
 * elements move; the empty text nodes Vue anchors a list with stay put.
 */
function moveAround(el, node, anchor) {
  const insert = (child, before) =>
    Node.prototype.insertBefore.call(el, child, before);
  const children = [...el.childNodes];
  const from = children.indexOf(node);
  const to = anchor === null ? children.length : children.indexOf(anchor);
  const elements = (list) =>
    list.filter((child) => child.nodeType === Node.ELEMENT_NODE);
  if (to > from) {
    // The rows between it and its anchor go in front of it.
    for (const child of elements(children.slice(from + 1, to)))
      insert(child, node);
  } else {
    // The rows from the anchor up to it go behind it, in order.
    const after = node.nextSibling;
    for (const child of elements(children.slice(to, from)))
      insert(child, after);
  }
  return node;
}

export const vFocusSafeChildren = {
  mounted(el, binding) {
    el._focusSafeLeave = binding.value;
    el.insertBefore = function (node, anchor) {
      if (node !== anchor && focusedChild(el, node))
        return moveAround(el, node, anchor ?? null);
      return Node.prototype.insertBefore.call(el, node, anchor);
    };
    el.removeChild = function (node) {
      if (focusedChild(el, node)) el._focusSafeLeave?.();
      return Node.prototype.removeChild.call(el, node);
    };
  },
  updated(el, binding) {
    el._focusSafeLeave = binding.value;
  },
  unmounted(el) {
    delete el.insertBefore;
    delete el.removeChild;
    delete el._focusSafeLeave;
  },
};
