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

import { createTransitSource } from './source.js';
import { createTrails } from './trails.js';
import { createState } from './state.js';
import { createHeight } from './height.js';
import { createRendering } from './rendering.js';
import { createSelection } from './selection.js';
import { createIngestion } from './ingestion.js';
import { createViewport } from './viewport.js';
import { createQueries } from './queries.js';
import { createControls } from './controls.js';
import { createLifecycle } from './lifecycle.js';
import { createTesting } from './testing.js';
import { TRANSIT_POLL_MS } from './policy.js';

/**
 * Construct one Transit layer with its own scene state and supplied services.
 *
 * Nothing here is module-global: the viewer, the point collection, the vehicle
 * and height maps, the in-flight requests, the manager handle and the overlay
 * host all live on the instance this returns, and `destroy()` releases every
 * shared registration it took (sprite collection, pick owner, render hold,
 * camera sensitivity).
 *
 * @param {{services: object}} options
 * @returns {object} The data-layer module the manager registers.
 */
export function createTransitLayer({
  services,
  source = createTransitSource(),
}) {
  if (!services?.overlays || !services?.render || !services?.sprites) {
    throw new TypeError(
      'A transit layer needs overlay, render and sprite services',
    );
  }
  if (
    typeof source?.requestSnapshot !== 'function' ||
    typeof source?.getHistory !== 'function'
  ) {
    throw new TypeError(
      'A transit source needs snapshot and history operations',
    );
  }
  const state = createState({ services });
  const parts = {};
  const context = { state, services, parts, source };
  parts.trails = createTrails(context);
  parts.height = createHeight(context);
  parts.selection = createSelection(context);
  parts.rendering = createRendering(context);
  parts.ingestion = createIngestion(context);
  parts.viewport = createViewport(context);
  parts.queries = createQueries(context);
  parts.controls = createControls(context);
  parts.lifecycle = createLifecycle(context);
  parts.testing = createTesting(context);

  return Object.assign(
    { updateInterval: TRANSIT_POLL_MS },
    parts.lifecycle.methods,
    parts.queries.methods,
    parts.controls.methods,
    parts.testing,
  );
}

export {
  TRANSIT_MODE_COLORS,
  TRANSIT_POLL_MS,
  TRANSIT_SELECTED_OVERLAY_SOURCE_ID,
  TRANSIT_SELECTED_OVERLAY_SOURCE_OPTIONS,
  aggregateTransitFeedHealth,
  buildTransitSelectionCopy,
  createTransitSelectedOverlayEntry,
  interpolatedVehiclePosition,
  isStaleVehicleFix,
  transitDetectionClass,
  transitDetectionId,
  transitDetectionMetric,
  transitVehicleKey,
  vehicleFixAgeMs,
} from './policy.js';
