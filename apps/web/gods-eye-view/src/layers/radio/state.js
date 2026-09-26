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

import * as Cesium from 'cesium';
import {
  EMPTY_ACCEPTED_CATALOG_SNAPSHOT,
  DEFAULT_RADIO_FILTER,
  DEFAULT_RADIO_VOLUME,
} from './policy.js';

export function createState({ services }) {
  const layerState = {};

  layerState._radioEarthScreenCenter = new Cesium.Cartesian2();

  layerState._radioEarthToCenter = new Cesium.Cartesian3();

  layerState._viewer = null;

  layerState._dataSource = null;

  layerState._enabled = false;

  layerState._managerLifecyclePresentation = null;

  layerState._loading = false;

  layerState._stale = false;

  layerState._degraded = false;

  layerState._error = null;

  layerState._updatedAt = null;

  layerState._acceptedCatalogSnapshot = EMPTY_ACCEPTED_CATALOG_SNAPSHOT;

  layerState._stations = [];

  layerState._stationById = new Map();

  layerState._categories = [];

  layerState._renderById = new Map();

  layerState._filter = DEFAULT_RADIO_FILTER;

  layerState._selectedId = null;

  layerState._selectedEntity = null;

  layerState._selectionGeneration = 0;

  layerState._selectionTimer = null;

  layerState._radioCameraNavigationGeneration = 0;

  layerState._radioCameraFlightSequence = 0;

  layerState._activeRadioCameraFlight = null;

  layerState._audio = null;

  layerState._audioStationId = null;

  layerState._audioState = 'stopped';

  layerState._audioError = null;

  layerState._userVolume = DEFAULT_RADIO_VOLUME;

  layerState._tuningActive = false;

  layerState._tuningStatic = false;

  layerState._tuningAwaitingStationId = null;

  layerState._tuningPreviewId = null;

  layerState._tuningStartStationId = null;

  layerState._tuningResolutionSnapshot = EMPTY_ACCEPTED_CATALOG_SNAPSHOT;

  layerState._tuningStationById = new Map();

  layerState._tuningUnavailableStationId = null;

  layerState._cancelledTuningPresentationStation = null;

  layerState._tuningCameraNavigation = null;

  layerState._tuningNoiseContext = null;

  layerState._tuningNoiseSource = null;

  layerState._tuningNoiseFilter = null;

  layerState._tuningNoiseGain = null;

  layerState._voiceDucked = false;

  layerState._voiceRestoring = false;

  layerState._voiceRestoreTimer = null;

  layerState._volumeFadeFrame = null;

  layerState._volumeTransitionGeneration = 0;

  layerState._playGeneration = 0;

  layerState._playAttemptSequence = 0;

  layerState._activePlaybackAttempt = null;

  layerState._playFallbackId = null;

  layerState._playFallbackFocus = null;

  layerState._playFallbackOrigin = 'programmatic';

  layerState._playFallbackAttemptId = null;

  layerState._clickHandler = null;

  layerState._horizonTimer = null;

  layerState._lastHorizonCameraPosition = null;

  layerState._horizonScanCount = 0;

  layerState._abortController = null;

  layerState._requestGeneration = 0;

  layerState._sessionGeneration = 0;

  layerState._removeClusterListener = null;

  layerState._overlayPublishTimer = null;

  layerState._clusterOverlayIdentitySequence = 0;

  layerState._clusterOverlayIdentities = [];

  layerState._overlayDiagnostics = {
    entryCount: 0,
    selectedCount: 0,
    singletonTexts: [],
    singletonIds: [],
    clusterTexts: [],
    clusterIds: [],
    clusterMemberships: [],
  };

  layerState._listeners = new Set();

  layerState._playbackControlListeners = new Set();
  return layerState;
}
