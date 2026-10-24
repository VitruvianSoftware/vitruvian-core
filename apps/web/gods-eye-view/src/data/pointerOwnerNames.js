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

import { msg } from '../i18n/marker.js';

/**
 * Tool name for a pointer owner. Owner ids (inputOwnership.js) never go on
 * screen; callers translate the English name with translateKnown().
 */

const POINTER_OWNER_NAMES = Object.freeze({
  draw: msg('Draw'),
  directions: msg('Directions'),
  'recent-imagery-box': msg('Recent imagery'),
});

/**
 * English display name of a pointer owner. An owner without a registered name
 * falls back to its id.
 * @param {string|null} owner Pointer-owner id, as `pointerOwner()` returns it.
 * @returns {string}
 */
export function pointerOwnerName(owner) {
  const id = typeof owner === 'string' ? owner.trim() : '';
  if (!id) return '';
  return Object.hasOwn(POINTER_OWNER_NAMES, id) ? POINTER_OWNER_NAMES[id] : id;
}
