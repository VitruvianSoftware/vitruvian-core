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

import { createSurfaceServices } from '../app/surfaceServices.js';
import { createApplicationRequestServices } from '../services/requests.js';
import { createApplicationCatalog } from '../app/constructCatalog.js';
import { createStandaloneLayerSources } from './layerSources.js';
export { createStandaloneReferenceSources } from './layerSources.js';

/** Create fresh layer instances using the existing standalone source choices. */
export function createStandaloneCatalog({
  nepalBoundaryResolver,
  signal = new AbortController().signal,
  surface = createSurfaceServices({
    terrainSource: createApplicationRequestServices().terrain,
    signal,
  }),
} = {}) {
  return createApplicationCatalog({
    nepalBoundaryResolver,
    surface,
    sources: createStandaloneLayerSources(),
    signal,
    vesselOptions: {
      maxRows: import.meta.env?.VITE_AIS_LIVE_MAX_ROWS,
      maxLabels: import.meta.env?.VITE_AIS_LIVE_LABEL_MAX_ROWS,
    },
  });
}

// Direct compatibility callers share one catalog; application startup supplies its own.
let compatibilityCatalog;
export function getStandaloneCatalog() {
  return (compatibilityCatalog ||= createStandaloneCatalog());
}
