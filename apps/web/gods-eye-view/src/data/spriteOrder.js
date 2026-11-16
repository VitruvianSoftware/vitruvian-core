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

/** Bottom-to-top order of the sprite layers' icon and dot sets. */
export const SPRITE_LAYER_ORDER = Object.freeze([
  'shipwrecks',
  'cctv',
  'firms',
  'wildlife-sightings',
  'bikeshare',
  'transit',
  'transit-motion',
  'rail',
  'directions',
  'ais',
  'military',
  'flights',
]);

/**
 * The draw order (`SetSpec.drawOrder`) a sprite layer's set is made with:
 * its place in `SPRITE_LAYER_ORDER`, counted back from -1 for flights, so
 * flights draw over every other sprite layer and the rest follow the list,
 * whichever layer was turned on first. Every set at the default order, 0
 * (selection highlights, route endpoints, the tracked plane and the other
 * overlays), stays over all of them, as it did when the sprite sets were
 * raised to the bottom of the scene. A key not in the list gets 0.
 * @param {string} layerId - Stable sprite-order layer key.
 * @returns {number}
 */
export function spriteDrawOrder(layerId) {
  const index = SPRITE_LAYER_ORDER.indexOf(layerId);
  return index < 0 ? 0 : index - SPRITE_LAYER_ORDER.length;
}
