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

import { defaultSurface } from './surfaceServices.js';
import { createApplicationInstallations } from '../app/layers/militaryInstallations.js';
import { createSourceSlot } from '../sources/sourceSlot.js';
import { createInstallationSource } from '../layers/installations/index.js';

const sourceSlot = createSourceSlot(
  createInstallationSource(),
  ['getMappedSites', 'searchNearby'],
  'Installation source',
);
export const configureInstallationSource = sourceSlot.configure;
const layer = createApplicationInstallations({
  surface: defaultSurface,
  source: sourceSlot.source,
});
export const approximateSurfaceDistanceM = layer.approximateSurfaceDistanceM;
export const classifyGoogleMilitaryPlace = layer.classifyGoogleMilitaryPlace;
export const installationSourceLabel = layer.installationSourceLabel;
export const installationSurfaceHeightM = layer.installationSurfaceHeightM;
export const installationWithinViewport = layer.installationWithinViewport;
export const installationResponseSaturated =
  layer.installationResponseSaturated;
export const installationRetryDelayMs = layer.installationRetryDelayMs;
export default layer;
