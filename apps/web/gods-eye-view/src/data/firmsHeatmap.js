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
import { createApplicationFirms, firmsServices } from '../app/layers/firms.js';
import { createSourceSlot } from '../sources/sourceSlot.js';
import {
  createFirmsHelpers,
  createFirmsSource,
} from '../layers/firms/index.js';
const sourceSlot = createSourceSlot(
  createFirmsSource(),
  ['getSnapshot'],
  'Fire source',
);
export const configureFirmsSource = sourceSlot.configure;
const helpers = createFirmsHelpers({
  services: { ...firmsServices, anchors: defaultSurface.anchors },
});
export const mapAnalystRecord = helpers.mapAnalystRecord;
export const fireCullPosition = helpers.fireCullPosition;
export const applyHorizonCull = helpers.applyHorizonCull;
export const buildSelectedFireCard = helpers.buildSelectedFireCard;
export const buildFireCard = helpers.buildFireCard;
export const buildCellCard = helpers.buildCellCard;
export const applyFirmsOverlayPolicy = helpers.applyFirmsOverlayPolicy;

/** Retain the existing default feed and helper exports for direct callers. */
export function createFirmsHeatmapLayer(options) {
  return createApplicationFirms({
    surface: defaultSurface,
    ...options,
    feed: options.feed ?? sourceSlot.source,
  });
}
