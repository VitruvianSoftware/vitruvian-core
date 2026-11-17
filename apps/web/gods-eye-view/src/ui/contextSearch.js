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

import { computed, ref } from 'vue';

// The Context panel's own search: one field in its header that narrows what
// the panel is showing (the selected item's details, and every list of what
// is nearby or in view) to what holds the typed text.

/** Whether the search field is showing. */
export const contextSearchOpen = ref(false);
/** The text as typed. */
export const contextSearchText = ref('');
/** The text to match against: trimmed, lower case, '' when not searching. */
export const contextNeedle = computed(() =>
  contextSearchOpen.value ? contextSearchText.value.trim().toLowerCase() : '',
);

/** Whether any of the given strings holds the searched text (true when not searching). */
export function matchesContextSearch(...parts) {
  const needle = contextNeedle.value;
  if (!needle) return true;
  return parts.some(
    (part) =>
      part !== null &&
      part !== undefined &&
      String(part).toLowerCase().includes(needle),
  );
}

export function closeContextSearch() {
  contextSearchOpen.value = false;
  contextSearchText.value = '';
}
