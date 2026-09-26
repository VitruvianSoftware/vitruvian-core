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

import { createControls } from './controls.js';
import { createCatalog } from './catalog.js';
import { createLabels } from './labels.js';
import { createOrbits } from './orbits.js';
import { createRendering } from './rendering.js';
import { createTracking } from './tracking.js';
import { createTesting } from './testing.js';
import { createInteraction } from './interaction.js';
import { createLifecycle } from './lifecycle.js';
import { createIngestion } from './ingestion.js';
import { createRecords } from './records.js';
import { createState } from './state.js';

/** Construct one layer with its own scene state and supplied application services. */
export function createSatellitesLayer({ services, source }) {
  if (typeof source?.readGroup !== 'function')
    throw new TypeError('A satellites source is required');
  const state = createState({ services });
  const parts = {};
  const context = { state, services, parts, source };
  parts.controls = createControls(context);
  parts.catalog = createCatalog(context);
  parts.labels = createLabels(context);
  parts.orbits = createOrbits(context);
  parts.records = createRecords(context);
  parts.rendering = createRendering(context);
  parts.tracking = createTracking(context);
  parts.testing = createTesting(context);
  parts.interaction = createInteraction(context);
  parts.lifecycle = createLifecycle(context);
  parts.ingestion = createIngestion(context);
  return Object.assign(
    {},
    parts.controls.methods,
    parts.lifecycle.methods,
    parts.ingestion.methods,
    {
      satelliteVisualsVisible: parts.controls.satelliteVisualsVisible,
      satelliteCatalogModeChanged: parts.controls.satelliteCatalogModeChanged,
      createIssOverlayEntry: parts.labels.createIssOverlayEntry,
      orbitFrameModelMatrix: parts.orbits.orbitFrameModelMatrix,
      _setTrackedSatelliteRefreshStateForTest:
        parts.testing._setTrackedSatelliteRefreshStateForTest,
      _setSatelliteTrackingRefreshOutcomeForTest:
        parts.testing._setSatelliteTrackingRefreshOutcomeForTest,
      _trackedFrameCartesianForTest:
        parts.testing._trackedFrameCartesianForTest,
      _runSatellitePreRenderForTest:
        parts.testing._runSatellitePreRenderForTest,
      _setDenseCatalogStateForTest: parts.testing._setDenseCatalogStateForTest,
      _clearDenseCatalogStateForTest:
        parts.testing._clearDenseCatalogStateForTest,
      _catalogGroupForTest: parts.testing._catalogGroupForTest,
      _setSatelliteLabelLifecycleStateForTest:
        parts.testing._setSatelliteLabelLifecycleStateForTest,
      _trackIssForTest: parts.testing._trackIssForTest,
      _pendingSatelliteTrackingRestoreForTest:
        parts.testing._pendingSatelliteTrackingRestoreForTest,
      _applyPendingSatelliteTrackingRestoreForTest:
        parts.testing._applyPendingSatelliteTrackingRestoreForTest,
      _removeSatelliteTrackingCandidateForTest:
        parts.testing._removeSatelliteTrackingCandidateForTest,
      _clearSatelliteLabelLifecycleForTest:
        parts.testing._clearSatelliteLabelLifecycleForTest,
      applySatellitePointFocusDeemphasis:
        parts.rendering.applySatellitePointFocusDeemphasis,
      getNextIssPass: parts.orbits.getNextIssPass,
      getNextSatellitePass: parts.orbits.getNextSatellitePass,
      resolveSatelliteForPass: parts.orbits.resolveSatelliteForPass,
      getAnalystRecords: parts.records.getAnalystRecords,
      scoreSatelliteNameMatch: parts.orbits.scoreSatelliteNameMatch,
      findSatelliteOrbitTrackInTle: parts.orbits.findSatelliteOrbitTrackInTle,
      getSatelliteOrbitTrack: parts.orbits.getSatelliteOrbitTrack,
    },
  );
}
export { ISS_OVERLAY_SOURCE_ID, ISS_OVERLAY_SOURCE_OPTIONS } from './policy.js';
export { createSatelliteSource } from './source.js';
