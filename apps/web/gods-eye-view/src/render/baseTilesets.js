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
 * @module render/baseTilesets
 * @description Tilesets the application draws as its base outside the
 * renderer's globe port, marked so the port drapes imagery on them while
 * they are shown. Cesium-free: code that loads its own base, or hands
 * a layer one (`recentImagery.attachTileset`), marks it here without
 * reaching the renderer; the renderer's globe port reads the marks.
 */

const marked = new WeakSet();

/**
 * Mark a tileset as a base the application draws outside the port, so
 * imagery drapes on it while it is shown. The port's own photoreal tileset
 * needs no mark.
 * @param {object} tileset The renderer's tileset object.
 */
export function markBaseTileset(tileset) {
  if (tileset && typeof tileset === 'object') marked.add(tileset);
}

/** Whether `tileset` was marked as a base (`markBaseTileset`). */
export const isBaseTileset = (tileset) =>
  Boolean(tileset && typeof tileset === 'object' && marked.has(tileset));
