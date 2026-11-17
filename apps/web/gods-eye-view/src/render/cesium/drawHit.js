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
 * @module render/cesium/drawHit
 * @description A Cesium pick of a draw-set item, as the contract's `Hit`.
 * No imports, so the click dispatcher can use it without the draw port.
 */
/**
 * A Cesium pick as the contract's `Hit` (`query.d.ts`), when what it picked
 * is a draw-set item (its pick id is `{set, id, meta}`); else
 * null. For code that reads a pick Cesium already made (the click
 * dispatcher's); `query.pick` makes its own, and also leaves out items of
 * hidden or unpickable sets. It does not check that the set or item is
 * still drawn (a ground swap can pick a retiring primitive), so a caller
 * matches the hit against its own current sets and item ids.
 * @param {object|null|undefined} picked
 */
export function drawHitOf(picked) {
  const id = picked?.id;
  if (!id || typeof id.set !== 'string' || typeof id.id !== 'string')
    return null;
  return {
    set: id.set,
    id: id.id,
    ...(id.meta === undefined ? {} : { meta: id.meta }),
    surface: false,
  };
}
