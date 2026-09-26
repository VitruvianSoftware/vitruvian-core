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

import { createModel } from './model.js';
import { createIngestion } from './ingestion.js';
import { createRendering } from './rendering.js';
import { createCards } from './cards.js';
import { createSelection } from './selection.js';
import { createViewport } from './viewport.js';
import { createLifecycle } from './lifecycle.js';
import { createQueries } from './queries.js';
import { createFirmsState } from './state.js';

export function createFirmsHelpers({ services }) {
  const layerState = createFirmsState({ services, config: {} });
  return createModel({ layerState, services, config: {}, components: {} });
}

/** Compose one fire layer with explicit source and scene operations. */
export function createFirmsHeatmapLayer({ services, feed, ...config }) {
  if (typeof feed?.getSnapshot !== 'function')
    throw new TypeError('Fires require a snapshot source');
  const layerState = createFirmsState({ services, config });
  const components = {};
  const context = { layerState, services, config, components, feed };
  components.model = createModel(context);
  components.ingestion = createIngestion(context);
  components.rendering = createRendering(context);
  components.cards = createCards(context);
  components.selection = createSelection(context);
  components.viewport = createViewport(context);
  components.lifecycle = createLifecycle(context);
  components.queries = createQueries(context);
  return Object.assign(
    {},
    components.queries.methods,
    components.lifecycle.methods,
    components.ingestion.methods,
  );
}

export { createFirmsSource } from './source.js';
export { createFireAnchors, FIRE_ANCHOR_LIFT_M } from './anchors.js';
export * from '../../data/firmsAdapt.js';
export * from '../../data/firmsLabels.js';
