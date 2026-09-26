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
 * Where draped imagery can go on the current map stack. A globe stack drapes
 * on `viewer.imageryLayers`; a 3D-tiles stack hides the globe, and Cesium
 * 1.138 drapes imagery onto the tileset's own `imageryLayers` instead. When
 * neither exists there is nowhere to drape and the caller says so.
 */

/** Guidance shown when the active map stack cannot host draped imagery. */
export const NO_IMAGERY_HOST = 'Hidden by this map source · choose a globe map';

/**
 * Resolve the imagery layer collection for the active map stack.
 * @param {{ viewer?: object, tileset?: object }} scene
 * @returns {{ collection: object | null, kind: 'globe' | 'tileset' | 'none' }}
 */
export function resolveImageryHost({ viewer, tileset } = {}) {
  if (viewer?.scene?.globe?.show === true && viewer.imageryLayers) {
    return { collection: viewer.imageryLayers, kind: 'globe' };
  }
  if (tileset?.imageryLayers && !tileset.isDestroyed?.()) {
    return { collection: tileset.imageryLayers, kind: 'tileset' };
  }
  return { collection: null, kind: 'none' };
}
