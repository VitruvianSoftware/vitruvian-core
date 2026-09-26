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
import { createApplicationFlights } from '../app/layers/flights.js';

import { createOpenSkySource } from '../sources/live/standalone.js';
import * as militaryRegistry from './militaryRegistry.js';

const flightsLayer = createApplicationFlights({
  surface: defaultSurface,
  source: createOpenSkySource(),
  militaryRegistry,
});
export { TRACKED_MODEL_MAX_PX } from '../layers/flights/policy.js';
export const _floorGroundedDisplayPositionForTest =
  flightsLayer.testing._floorGroundedDisplayPositionForTest;
export const _clearDisplayFloorStateForTest =
  flightsLayer.testing._clearDisplayFloorStateForTest;
export const _setTrackedFlightRefreshStateForTest =
  flightsLayer.testing._setTrackedFlightRefreshStateForTest;
export const _setFlightTrackingRefreshOutcomeForTest =
  flightsLayer.testing._setFlightTrackingRefreshOutcomeForTest;
export const _addFlightTrackingCandidateForTest =
  flightsLayer.testing._addFlightTrackingCandidateForTest;
export const _militaryLayerSuppressesForTest =
  flightsLayer.testing._militaryLayerSuppressesForTest;
export const _armFlightTrackingRestoreForTest =
  flightsLayer.testing._armFlightTrackingRestoreForTest;
export const _pendingFlightTrackingRestoreForTest =
  flightsLayer.testing._pendingFlightTrackingRestoreForTest;
export const _applyPendingFlightTrackingRestoreForTest =
  flightsLayer.testing._applyPendingFlightTrackingRestoreForTest;
export const _setCockpitDetectionSubjectForTest =
  flightsLayer.testing._setCockpitDetectionSubjectForTest;
export const _trackedModelRegimeActiveForTest =
  flightsLayer.testing._trackedModelRegimeActiveForTest;
export const _updateTrackedModelForTest =
  flightsLayer.testing._updateTrackedModelForTest;
export const _trackedBillboardColorForTest =
  flightsLayer.testing._trackedBillboardColorForTest;
export const _driveFleetModelHandoffForTest =
  flightsLayer.testing._driveFleetModelHandoffForTest;
export const _ensureFleetModelForTest =
  flightsLayer.testing._ensureFleetModelForTest;
export const mapAnalystRecord = flightsLayer.mapAnalystRecord;
export default flightsLayer;
