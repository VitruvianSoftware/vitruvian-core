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

import { createAnnotationEngine } from './annotationEngine.js';
import { createHybridAnnotationRenderer } from './hybridAnnotationRenderer.js';

/**
 * Initialize the map-annotation engine and expose it for the voice agent and
 * for manual/dev use via `window.__gevAnnotations`.
 *
 * This module is the single swap point between annotation rendering strategies.
 * This branch (Direction C) uses the HYBRID renderer: world-space draping for
 * footprints + screen-space SVG for callouts/rings/arrows. The engine, resolver,
 * and voice tool wiring are identical to the other two branches.
 */
export function initAnnotations({ viewer, tileset = null }) {
  // World-space footprint draping; clamped marks can use the photoreal tiles.
  if (tileset) {
    try { tileset.enableCollision = true; } catch { /* older tileset */ }
  }
  const renderer = createHybridAnnotationRenderer(viewer);
  const engine = createAnnotationEngine({ viewer, renderer });
  window.__gevAnnotations = engine;
  return engine;
}
