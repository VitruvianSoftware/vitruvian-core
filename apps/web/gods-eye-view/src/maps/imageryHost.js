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
 * on the globe port's imagery; a 3D-tiles stack hides the globe, and the
 * renderer drapes that imagery onto the shown base tileset instead. When
 * neither is drawn there is nowhere to drape and the caller says so.
 */

import { msg } from '../i18n/marker.js';
import { findGlobe } from '../render/rendererOf.js';
import { mapEngineFor } from './engine.js';

/** Guidance shown when the active map stack cannot host draped imagery. */
export const NO_IMAGERY_HOST = msg(
  'Hidden by this map source · choose a globe map',
);

const NONE = Object.freeze({ collection: null, kind: 'none' });

/**
 * Resolve the imagery host for the active map stack: the globe port's
 * imagery while the globe is shown, else the shown base tileset (the map
 * stack's `getImageryHostTileset()`), else none. `collection` names the host
 * (one value per host, so a change of host is a change of it). A renderer
 * that does not say whether its globe is shown (no `globeVisibility`) is
 * answered by the scene's map engine, which shows and hides it.
 * @param {{ viewer?: object, tileset?: object }} scene
 * @returns {{ collection: object | null, kind: 'globe' | 'tileset' | 'none' }}
 */
export function resolveImageryHost({ viewer, tileset } = {}) {
  const globe = findGlobe(viewer);
  const shownTileset =
    tileset && tileset.isDestroyed?.() !== true ? tileset : null;
  const globeShown =
    globe &&
    (globe.isGlobeVisible?.() ?? mapEngineFor(viewer).globeShown(viewer));
  if (globe && globeShown) return { collection: globe.imagery, kind: 'globe' };
  if (shownTileset) return { collection: shownTileset, kind: 'tileset' };
  return NONE;
}
