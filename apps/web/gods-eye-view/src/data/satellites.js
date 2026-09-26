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

import { createApplicationSatellites } from '../app/layers/satellites.js';
import { createSourceSlot } from '../sources/sourceSlot.js';
import { createSatelliteSource } from '../layers/satellites/index.js';

const sourceSlot = createSourceSlot(
  createSatelliteSource(),
  ['readGroup'],
  'Satellite source',
);
export const configureSatelliteSource = sourceSlot.configure;
const layer = createApplicationSatellites({
  source: sourceSlot.source,
});
export const satelliteVisualsVisible = layer.satelliteVisualsVisible;
export const satelliteCatalogModeChanged = layer.satelliteCatalogModeChanged;
export const createIssOverlayEntry = layer.createIssOverlayEntry;
export const orbitFrameModelMatrix = layer.orbitFrameModelMatrix;
export const _setTrackedSatelliteRefreshStateForTest =
  layer._setTrackedSatelliteRefreshStateForTest;
export const _setSatelliteTrackingRefreshOutcomeForTest =
  layer._setSatelliteTrackingRefreshOutcomeForTest;
export const _trackedFrameCartesianForTest =
  layer._trackedFrameCartesianForTest;
export const _runSatellitePreRenderForTest =
  layer._runSatellitePreRenderForTest;
export const _setDenseCatalogStateForTest = layer._setDenseCatalogStateForTest;
export const _clearDenseCatalogStateForTest =
  layer._clearDenseCatalogStateForTest;
export const _catalogGroupForTest = layer._catalogGroupForTest;
export const _setSatelliteLabelLifecycleStateForTest =
  layer._setSatelliteLabelLifecycleStateForTest;
export const _trackIssForTest = layer._trackIssForTest;
export const _pendingSatelliteTrackingRestoreForTest =
  layer._pendingSatelliteTrackingRestoreForTest;
export const _applyPendingSatelliteTrackingRestoreForTest =
  layer._applyPendingSatelliteTrackingRestoreForTest;
export const _removeSatelliteTrackingCandidateForTest =
  layer._removeSatelliteTrackingCandidateForTest;
export const _clearSatelliteLabelLifecycleForTest =
  layer._clearSatelliteLabelLifecycleForTest;
export const applySatellitePointFocusDeemphasis =
  layer.applySatellitePointFocusDeemphasis;
export const getNextIssPass = layer.getNextIssPass;
export const getNextSatellitePass = layer.getNextSatellitePass;
export const scoreSatelliteNameMatch = layer.scoreSatelliteNameMatch;
export const findSatelliteOrbitTrackInTle = layer.findSatelliteOrbitTrackInTle;
export const getSatelliteOrbitTrack = layer.getSatelliteOrbitTrack;
export {
  ISS_OVERLAY_SOURCE_ID,
  ISS_OVERLAY_SOURCE_OPTIONS,
} from '../layers/satellites/index.js';
export default layer;

export { mapAnalystRecord } from '../layers/satellites/records.js';
