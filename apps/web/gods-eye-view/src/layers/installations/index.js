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
import { createRendering } from './rendering.js';
import { createIngestion } from './ingestion.js';
import { createViewport } from './viewport.js';
import { createSelection } from './selection.js';
import { createControls } from './controls.js';
import { createLifecycle } from './lifecycle.js';
import { createState } from './state.js';

/** Construct one layer with its own scene state and supplied application services. */
export function createInstallationsLayer({ services, source }) {
  if (
    typeof source?.getMappedSites !== 'function' ||
    typeof source?.searchNearby !== 'function'
  )
    throw new TypeError('An installation source is required');
  const state = createState({ services });
  const parts = {};
  const context = { state, services, parts, source };
  parts.model = createModel(context);
  parts.rendering = createRendering(context);
  parts.ingestion = createIngestion(context);
  parts.viewport = createViewport(context);
  parts.selection = createSelection(context);
  parts.controls = createControls(context);
  parts.lifecycle = createLifecycle(context);
  return Object.assign(
    {},
    parts.controls.methods,
    parts.lifecycle.methods,
    parts.ingestion?.methods,
    {
      approximateSurfaceDistanceM: parts.model.approximateSurfaceDistanceM,
      classifyGoogleMilitaryPlace: parts.model.classifyGoogleMilitaryPlace,
      installationSourceLabel: parts.model.installationSourceLabel,
      installationSurfaceHeightM: parts.rendering.installationSurfaceHeightM,
      installationWithinViewport: parts.model.installationWithinViewport,
      installationResponseSaturated: parts.model.installationResponseSaturated,
      installationRetryDelayMs: parts.viewport.installationRetryDelayMs,
    },
  );
}
export { createInstallationSource } from './source.js';
