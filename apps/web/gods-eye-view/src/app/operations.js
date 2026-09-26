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

import { requireFeatureSource } from '../sources/featureSource.js';
import { createOverpassFeatureSource } from '../sources/overpassFeatures.js';
import { createSurfaceServices } from './surfaceServices.js';
import { createAnnotationResolver } from '../annotations/resolver.js';
import { searchAndFlyTo } from '../locations.js';

/** Assemble application operations from the caller's request services. */
export function createApplicationOperations({ requests, signal, eventTarget }) {
  for (const [name, method] of Object.entries({
    terrain: 'getHeights',
    regional: 'getBrief',
    weather: 'getConditions',
    summary: 'summarize',
  })) {
    if (typeof requests?.[name]?.[method] !== 'function')
      throw new TypeError(`Missing application request service: ${name}`);
  }
  const features = requireFeatureSource(
    requests.features ??
      createOverpassFeatureSource({
        boundarySource: requests.boundaries,
        signal,
      }),
  );
  const surface = createSurfaceServices({
    terrainSource: requests.terrain,
    signal,
    eventTarget,
  });
  const annotationResolver = createAnnotationResolver({
    featureSource: features,
    signal,
  });
  return Object.freeze({
    requests,
    surface,
    annotationResolver,
    searchAndFlyTo: (viewer, query, options = {}) =>
      searchAndFlyTo(viewer, query, {
        ...options,
        features,
        signal:
          signal && options.signal
            ? AbortSignal.any([signal, options.signal])
            : signal || options.signal,
        recoverNearView: annotationResolver.placesNearViewRecovery,
      }),
  });
}
