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

import { TRAFFIC_TIMING_ENABLED } from './policy.js';
import { createStyle } from './style.js';
import { createTiming } from './timing.js';
import { createModel } from './model.js';
import { createIngestion } from './ingestion.js';
import { createAnimation } from './animation.js';
import { createViewport } from './viewport.js';
import { createFlow } from './flow.js';
import { createRendering } from './rendering.js';
import { createControls } from './controls.js';
import { createLifecycle } from './lifecycle.js';
import { createState } from './state.js';

/** Construct one layer with its own scene state and supplied application services. */
export function createTrafficLayer({ services, source }) {
  if (
    ![
      'requestRoads',
      'getStatus',
      'fetchFlowForBounds',
      'getFlowSessionStats',
      'resetFlowTileCache',
    ].every((key) => typeof source?.[key] === 'function')
  )
    throw new TypeError('A traffic source is required');
  const state = createState({ services });
  const parts = {};
  const context = { state, services, parts, source };
  parts.style = createStyle(context);
  parts.timing = createTiming(context);
  parts.model = createModel(context);
  parts.ingestion = createIngestion(context);
  parts.animation = createAnimation(context);
  parts.viewport = createViewport(context);
  parts.flow = createFlow(context);
  parts.rendering = createRendering(context);
  parts.controls = createControls(context);
  parts.lifecycle = createLifecycle(context);
  state._parseRoads = TRAFFIC_TIMING_ENABLED
    ? (data, trace) =>
        trace
          ? parts.timing.parseRoadsTimed(data, trace)
          : parts.model.parseRoads(data)
    : parts.model.parseRoads;

  state._loadRoadsForBounds = TRAFFIC_TIMING_ENABLED
    ? parts.timing.loadRoadsForBoundsTimed
    : parts.ingestion.loadRoadsForBounds;

  return Object.assign(
    {},
    parts.controls.methods,
    parts.lifecycle.methods,
    parts.ingestion?.methods,
    {
      getTrafficTimingDiagnostics: parts.timing.getTrafficTimingDiagnostics,
      deriveTrafficFlowError: parts.flow.deriveTrafficFlowError,
      trafficFeedPresentation: parts.model.trafficFeedPresentation,
    },
  );
}

export { createTrafficSource } from './source.js';
