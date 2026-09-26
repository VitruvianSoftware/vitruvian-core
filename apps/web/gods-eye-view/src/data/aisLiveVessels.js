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

import { createApplicationVessels } from '../app/layers/aisLiveVessels.js';

import { createAisStreamSource } from '../sources/live/standalone.js';

const aisLiveVesselsLayer = createApplicationVessels({
  source: createAisStreamSource({
    apiUrl: import.meta.env?.VITE_AIS_LIVE_API_URL || '/api/ais-live',
  }),
  options: {
    maxRows: import.meta.env?.VITE_AIS_LIVE_MAX_ROWS,
    maxLabels: import.meta.env?.VITE_AIS_LIVE_LABEL_MAX_ROWS,
  },
});
export { AIS_FIRST_CONNECT_GRACE_MS } from '../layers/vessels/policy.js';
export const deriveAisFeedError = aisLiveVesselsLayer.deriveAisFeedError;
export const classifyAisFeedSnapshot =
  aisLiveVesselsLayer.classifyAisFeedSnapshot;
export const mapAnalystRecord = aisLiveVesselsLayer.mapAnalystRecord;
export const vesselDatumHeightM = aisLiveVesselsLayer.vesselDatumHeightM;
export const reduceVesselSelection = aisLiveVesselsLayer.reduceVesselSelection;
export const applyVesselFocusDeemphasis =
  aisLiveVesselsLayer.applyVesselFocusDeemphasis;
export const buildVesselCard = aisLiveVesselsLayer.buildVesselCard;
export const buildSelectedVesselCard =
  aisLiveVesselsLayer.buildSelectedVesselCard;
export const cardScreenSeparated = aisLiveVesselsLayer.cardScreenSeparated;
export const _bindVesselInteractionForTest =
  aisLiveVesselsLayer.testing._bindVesselInteractionForTest;
export const _setVesselStateForTest =
  aisLiveVesselsLayer.testing._setVesselStateForTest;
export const _setVesselOverlayHostForTest =
  aisLiveVesselsLayer.testing._setVesselOverlayHostForTest;
export const _updateVesselCardsForTest =
  aisLiveVesselsLayer.testing._updateVesselCardsForTest;
export const _reconcileVesselsForTest =
  aisLiveVesselsLayer.testing._reconcileVesselsForTest;
export const _applyAisFeedSnapshotForTest =
  aisLiveVesselsLayer.testing._applyAisFeedSnapshotForTest;
export const _loadLivePositionsForTest =
  aisLiveVesselsLayer.testing._loadLivePositionsForTest;
export const _beginAisSessionForTest =
  aisLiveVesselsLayer.testing._beginAisSessionForTest;
export const _setAisRuntimeForTest =
  aisLiveVesselsLayer.testing._setAisRuntimeForTest;
export const _getVesselFeedStateForTest =
  aisLiveVesselsLayer.testing._getVesselFeedStateForTest;
export const _getVesselStateForTest =
  aisLiveVesselsLayer.testing._getVesselStateForTest;
export default aisLiveVesselsLayer;
