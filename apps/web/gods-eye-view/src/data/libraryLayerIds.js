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
 * The Data Library's layer namespace, owned by the layer lifecycle: the
 * manager accepts a late registration only under `lib-<entry id>`, and the
 * library names its layers with the same rule.
 */

/** A library entry id: lowercase, digits and hyphens, 3–48 characters. */
export const LIBRARY_ID_PATTERN = /^[a-z0-9][a-z0-9-]{2,47}$/;
export const LIBRARY_LAYER_PREFIX = 'lib-';

/** The manager id a library entry's layer registers under. */
export function libraryLayerId(entryId) {
  return `${LIBRARY_LAYER_PREFIX}${entryId}`;
}

/** The entry id behind a library layer id, or null. */
export function libraryEntryIdOf(layerId) {
  if (typeof layerId !== 'string' || !layerId.startsWith(LIBRARY_LAYER_PREFIX))
    return null;
  const id = layerId.slice(LIBRARY_LAYER_PREFIX.length);
  return LIBRARY_ID_PATTERN.test(id) ? id : null;
}
