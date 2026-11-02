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
 * `v-field-value`: a form field's live value, written only when it differs
 * and the field is not focused, so a render never overwrites what a person
 * is typing, picking or dragging. Focus is read before the render patches
 * the field too, since disabling it drops focus. A null value leaves the
 * field as it is. Unlike a `:value` binding, the value attribute is never
 * rewritten.
 */
const focused = (el) => el.ownerDocument?.activeElement === el;
const apply = (el, { value }) => {
  const held = focused(el) || el.__fieldValueFocused;
  el.__fieldValueFocused = false;
  if (value == null || held) return;
  const next = String(value);
  if (el.value !== next) el.value = next;
};
export const vFieldValue = {
  mounted: apply,
  beforeUpdate(el) {
    el.__fieldValueFocused = focused(el);
  },
  updated: apply,
};
