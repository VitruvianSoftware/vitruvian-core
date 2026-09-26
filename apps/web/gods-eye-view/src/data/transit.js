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

import { createTransitLayer } from '../layers/transit/index.js';
import * as render from '../renderGovernor.js';
import * as sprites from './spriteOrder.js';
import * as picking from './pickRegistry.js';
import * as overlays from '../overlays/worldOverlay.js';
import { registerDynamicCredit, transitFeedCredit } from './dataCredits.js';
import {
  GROUND_FLOOR_LIFT_M,
  cachedGroundFloor,
  coarseFloorCoord,
  neighborFloorM,
  warmGroundFloor,
} from './groundFloor.js';
import { sampleMeshFloorCells } from './meshFloorSampler.js';

const layer = createTransitLayer({
  services: {
    render,
    sprites,
    picking,
    overlays,
    credits: { registerDynamicCredit, transitFeedCredit },
    ground: {
      GROUND_FLOOR_LIFT_M,
      cachedGroundFloor,
      coarseFloorCoord,
      neighborFloorM,
      warmGroundFloor,
    },
    // The legacy sampler over the same legacy floor, so this standalone
    // module warms its own mesh floors the way the application layer does.
    mesh: { sampleMeshFloorCells },
  },
});

export const _setTransitOverlayHostForTest =
  layer._setTransitOverlayHostForTest;
export const _transitStateForTest = layer._transitStateForTest;
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
  createTransitLayer,
} from '../layers/transit/index.js';
export default layer;
