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

import test from 'node:test';
import assert from 'node:assert/strict';
import { createSurfaceKeyboard } from './surfaceKeyboard.js';
test('surface cycling never targets deliberately excluded controls', () => {
  let handler;
  const documentRef = {
    activeElement: {},
    addEventListener: (_, fn) => (handler = fn),
    removeEventListener() {},
  };
  const node = ({
    attributes = {},
    fieldsetDisabled = false,
    inert = false,
  } = {}) => ({
    hasAttribute: (name) => Object.hasOwn(attributes, name),
    getClientRects: () => [{}],
    getAttribute: (name) => attributes[name] ?? null,
    matches: (selector) => selector === ':disabled' && fieldsetDisabled,
    closest: (selector) =>
      selector === '[inert]' && inert ? { inert: true } : null,
    focus() {
      documentRef.activeElement = this;
    },
  });
  const ignored = [
    node({ attributes: { tabindex: '-1' } }),
    node({ fieldsetDisabled: true }),
    node({ inert: true }),
  ];
  const first = node({}),
    last = node({});
  const controls = [...ignored, first, last];
  const root = {
    ownerDocument: documentRef,
    querySelectorAll: () => controls,
    contains: (n) => controls.includes(n),
  };
  const surface = createSurfaceKeyboard({
    root,
    isActive: () => true,
    onEscape() {},
  });
  surface.activate();
  const press = (shiftKey) =>
    handler({
      key: 'Tab',
      shiftKey,
      preventDefault() {},
      stopPropagation() {},
    });
  press(false);
  assert.equal(documentRef.activeElement, first);
  press(true);
  assert.equal(documentRef.activeElement, last);
  surface.destroy();
});
