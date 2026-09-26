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
import { createApplicationCctv } from '../app/layers/cctv.js';
import { createSourceSlot } from '../sources/sourceSlot.js';
import { createCctvSource } from '../layers/cctv/source.js';

const sourceSlot = createSourceSlot(
  createCctvSource(),
  ['getCatalog', 'getHealth', 'getFrameUrl', 'getMediaUrl'],
  'Cctv source',
);
export const configureCctvSource = sourceSlot.configure;
const layer = createApplicationCctv({
  surface: defaultSurface,
  source: sourceSlot.source,
});
export const calibrationPatchMovesAnchor = layer.calibrationPatchMovesAnchor;
export const migrateRangeScaleForFloor = layer.migrateRangeScaleForFloor;
export const _pushAmbientCardEntriesForTest =
  layer._pushAmbientCardEntriesForTest;
export const _setCctvOverlayHostForTest = layer._setCctvOverlayHostForTest;
export const createCctvProjectionOverlayEntry =
  layer.createCctvProjectionOverlayEntry;
export const setCctvCardPresentationOptions =
  layer.setCctvCardPresentationOptions;
export const surfaceRegimeKey = layer.surfaceRegimeKey;
export const normalizeCoverageMode = layer.normalizeCoverageMode;
export const readCalibrationStoreV2 = layer.readCalibrationStoreV2;
export const writeCalibrationStoreV2 = layer.writeCalibrationStoreV2;
export const deriveCalBadge = layer.deriveCalBadge;
export const computeFrustumGeometry = layer.computeFrustumGeometry;
export const activationProbeClampRange = layer.activationProbeClampRange;
export const frameSignatureFromPixels = layer.frameSignatureFromPixels;
export const _createCctvProjectionPlaneForTest =
  layer._createCctvProjectionPlaneForTest;
export const _updateCctvProjectionPlaneForTest =
  layer._updateCctvProjectionPlaneForTest;
export const applyCctvFocusDeemphasis = layer.applyCctvFocusDeemphasis;
export const createGeometryProgressNotifier =
  layer.createGeometryProgressNotifier;
export const processCctvGeometryQueueBatch =
  layer.processCctvGeometryQueueBatch;
export const cctvGeometryDrainPacing = layer.cctvGeometryDrainPacing;
export const processCctvGeometryDrainBatch =
  layer.processCctvGeometryDrainBatch;
export const prioritizeActiveCctvGeometryRecord =
  layer.prioritizeActiveCctvGeometryRecord;
export const processGeometryBatch = layer.processGeometryBatch;
export const hideCctvRecordVisuals = layer.hideCctvRecordVisuals;
export const refreshCoverageStyles = layer.refreshCoverageStyles;
export const clearProbeClampOnDeactivation =
  layer.clearProbeClampOnDeactivation;
export const cctvRecordNeedsActivation = layer.cctvRecordNeedsActivation;
export const bindCctvWorldClickGesture = layer.bindCctvWorldClickGesture;
export const setActiveCamera = layer.setActiveCamera;
export const deactivateActiveCamera = layer.deactivateActiveCamera;
export const cctvEmptyClickDeselects = layer.cctvEmptyClickDeselects;
export const materializeCctvCoverageEntities =
  layer.materializeCctvCoverageEntities;
export const materializeCctvActiveCoverageEntities =
  layer.materializeCctvActiveCoverageEntities;
export const materializeCctvVisibleCoverageEntities =
  layer.materializeCctvVisibleCoverageEntities;
export const _extractPickedCameraIdForTest =
  layer._extractPickedCameraIdForTest;
export const _setCctvCoverageStateForTest = layer._setCctvCoverageStateForTest;
export const focusCctvRecord = layer.focusCctvRecord;
export const maybeAutoHop = layer.maybeAutoHop;
export const cctvCycleIndex = layer.cctvCycleIndex;
export {
  CCTV_CALIBRATION_STORAGE_KEY_V1,
  CCTV_CALIBRATION_STORAGE_KEY_V2,
  FRUSTUM_GROUND_CLEARANCE_M,
  CCTV_FOCUS_RESULT,
  CCTV_PROJECTION_OVERLAY_SOURCE_ID,
  CCTV_PROJECTION_OVERLAY_SOURCE_OPTIONS,
} from '../layers/cctv/index.js';
export default layer;
