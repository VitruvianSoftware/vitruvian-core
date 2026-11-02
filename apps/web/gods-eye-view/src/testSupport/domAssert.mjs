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

import assert from 'node:assert/strict';

const describe = (node) =>
  node?.nodeType === 1
    ? `<${node.tagName.toLowerCase()}${node.id ? `#${node.id}` : ''}>`
    : String(node);

/**
 * Assert that two DOM nodes (or a node and null) are the same. Never hand
 * happy-dom nodes to assert.equal or deepEqual: a failure prints both, and a
 * node reaches the whole page and window, which runs the process out of
 * memory.
 */
export function assertSameNode(actual, expected, message = '') {
  assert.ok(
    actual === expected,
    `${message ? `${message}: ` : ''}${describe(actual)} is not ${describe(expected)}`,
  );
}
