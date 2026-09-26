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

import { createOverpassFeatureSource } from '../sources/overpassFeatures.js';
import { FEATURE_SOURCE_METHODS } from '../sources/featureSource.js';
import { createSourceSlot } from '../sources/sourceSlot.js';
import { createApplicationRequestServices } from './requests.js';

// Compatibility owners are page-scoped, like the viewer and its layer registry.
const defaults = createApplicationRequestServices();
const slots = Object.fromEntries(
  Object.entries({
    boundaries: ['query'],
    terrain: ['getHeights'],
    regional: ['getBrief'],
    weather: ['getConditions'],
    summary: ['summarize'],
  }).map(([name, methods]) => [
    name,
    createSourceSlot(defaults[name], methods, `${name} service`),
  ]),
);
slots.features = createSourceSlot(
  createOverpassFeatureSource({ boundarySource: slots.boundaries.source }),
  FEATURE_SOURCE_METHODS,
  'features service',
);
export const applicationServices = Object.freeze(
  Object.fromEntries(
    Object.entries(slots).map(([name, slot]) => [name, slot.source]),
  ),
);

/** Supply selected services before constructing the application; release after its consumers. */
export function configureApplicationServices(services) {
  const releases = [];
  try {
    for (const [name, service] of Object.entries(services)) {
      if (!slots[name])
        throw new TypeError(`Unknown application service: ${name}`);
      releases.push(slots[name].configure(service));
    }
  } catch (error) {
    for (const release of releases.reverse()) release();
    throw error;
  }
  return () => {
    for (const release of releases.reverse()) release();
  };
}
