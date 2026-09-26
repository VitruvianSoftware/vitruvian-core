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

/** Catch invalid source graphs before a cached fallback can wait on itself. */
export function indexMapSources(sources) {
  const index = new Map();
  for (const source of sources) {
    const id = source?.descriptor?.id;
    if (typeof id !== 'string' || !id || index.has(id))
      throw new TypeError('Map source IDs must be nonempty and unique');
    index.set(id, source);
  }
  for (const id of index.keys()) {
    const seen = new Set();
    let next = id;
    while (next) {
      if (seen.has(next)) throw new TypeError('Map source fallback cycle');
      if (!index.has(next)) throw new TypeError('Unknown map fallback source');
      seen.add(next);
      next = index.get(next).constructionFallback?.id;
    }
  }
  return index;
}
