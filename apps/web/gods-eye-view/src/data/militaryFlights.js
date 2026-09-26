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
import { createApplicationMilitary } from '../app/layers/militaryFlights.js';

import { createAdsbLolSource } from '../sources/live/standalone.js';
import * as militaryRegistry from './militaryRegistry.js';

const militaryFlightsLayer = createApplicationMilitary({
  surface: defaultSurface,
  source: createAdsbLolSource(),
  militaryRegistry,
});
export { TRACKED_MODEL_MAX_PX } from '../layers/military/policy.js';
export const _setTrackedMilitaryRefreshStateForTest =
  militaryFlightsLayer.testing._setTrackedMilitaryRefreshStateForTest;
export const _setMilitaryTrackingRefreshOutcomeForTest =
  militaryFlightsLayer.testing._setMilitaryTrackingRefreshOutcomeForTest;
export const _addMilitaryTrackingCandidateForTest =
  militaryFlightsLayer.testing._addMilitaryTrackingCandidateForTest;
export const _pendingMilitaryTrackingRestoreForTest =
  militaryFlightsLayer.testing._pendingMilitaryTrackingRestoreForTest;
export const _applyPendingMilitaryTrackingRestoreForTest =
  militaryFlightsLayer.testing._applyPendingMilitaryTrackingRestoreForTest;
export const _setCockpitDetectionSubjectForTest =
  militaryFlightsLayer.testing._setCockpitDetectionSubjectForTest;
export const _trackedModelRegimeActiveForTest =
  militaryFlightsLayer.testing._trackedModelRegimeActiveForTest;
export const _updateTrackedModelForTest =
  militaryFlightsLayer.testing._updateTrackedModelForTest;
export const _trackedBillboardColorForTest =
  militaryFlightsLayer.testing._trackedBillboardColorForTest;
export const _driveFleetModelHandoffForTest =
  militaryFlightsLayer.testing._driveFleetModelHandoffForTest;
export const _ensureFleetModelForTest =
  militaryFlightsLayer.testing._ensureFleetModelForTest;
export const mapAnalystRecord = militaryFlightsLayer.mapAnalystRecord;
export default militaryFlightsLayer;
